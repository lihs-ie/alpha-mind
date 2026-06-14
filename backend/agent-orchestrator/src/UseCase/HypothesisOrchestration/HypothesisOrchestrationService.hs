module UseCase.HypothesisOrchestration.HypothesisOrchestrationService (
  -- * Use case functions
  orchestrateFromInsight,
  orchestrateFromRetest,
) where

import Data.Text (pack)
import Data.Time (UTCTime)
import Domain.HypothesisOrchestration (Trace)
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposal,
  HypothesisProposalIdentifier,
  HypothesisProposalRepository,
  InstrumentType (..),
  attachGenerationContext,
  blockProposal,
  completeProposal,
  failProposal,
 )
import Domain.HypothesisOrchestration.Aggregate qualified as ProposalRepository
import Domain.HypothesisOrchestration.DuplicateSuppressionPolicy (
  DuplicateSuppressionPolicy (..),
  shouldSuppress,
 )
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.FailureKnowledge (
  FailureKnowledgeIdentifier,
  FailureKnowledgeRepository,
  emptyFailureKnowledgeSearchCriteria,
 )
import Domain.HypothesisOrchestration.FailureKnowledge qualified as FailureKnowledgeRepository
import Domain.HypothesisOrchestration.GenerationContextResolutionPolicy (
  GenerationContextResolutionPolicy (..),
  ProfileResolutionInput (..),
  SkillResolutionInput (..),
  TemplateResolutionInput (..),
  resolveGenerationContext,
 )
import Domain.HypothesisOrchestration.HypothesisProposalFactory (
  InsightCollectedEvent (..),
  RetestRequestedEvent (..),
  fromInsightCollected,
  fromRetestRequested,
 )
import Domain.HypothesisOrchestration.InstructionProfile (
  InstructionProfile (..),
  InstructionProfileRepository,
 )
import Domain.HypothesisOrchestration.InstructionProfile qualified as InstructionProfileRepository
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  OrchestrationDispatch,
  OrchestrationDispatchIdentifier,
  OrchestrationDispatchRepository,
  markPublished,
 )
import Domain.HypothesisOrchestration.OrchestrationDispatch qualified as DispatchRepository
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.SkillExecutor (
  SkillExecutor (..),
  SkillInput (..),
  SkillOutput (..),
 )
import Domain.HypothesisOrchestration.SkillRegistry (
  Skill (..),
  SkillRegistryRepository,
 )
import Domain.HypothesisOrchestration.SkillRegistry qualified as SkillRegistryRepository
import Domain.HypothesisOrchestration.ValueObjects (
  DuplicateAssessmentDecision (..),
  PublishedEventType (..),
  SourceEventSnapshot,
  SourceEventType (..),
  mkDispatchDecision,
  mkDuplicateAssessment,
  mkFailureKnowledgeSummary,
  mkGenerationContext,
  mkProposalArtifact,
  mkSourceEventSnapshot,
 )
import UseCase.HypothesisOrchestration.DispatchService (checkIdempotency)
import UseCase.HypothesisOrchestration.FailureKnowledgeRegistrar (registerFailure)

-- ---------------------------------------------------------------------------
-- Public entry points
-- ---------------------------------------------------------------------------

{- | UC-AO: insight.collected イベントを受信して仮説提案をオーケストレーションする。

処理順序（RULE-AO-006 に従い persist BEFORE publish）:
1. SourceEventSnapshot 生成
2. 冪等性チェック（DispatchService.checkIdempotency）
3. HypothesisProposal 生成（Pending）
4. Skill 解決
5. InstructionProfile 解決
6. GenerationContext 解決
7. GenerationContext アタッチ
8. FailureKnowledge 重複チェック → 重複時は blockProposal
9. SkillExecutor 実行
10. completeProposal
11. RULE-AO-006: HypothesisProposalRepository.persist 先
12. OrchestrationDispatch.markPublished + persist
-}
orchestrateFromInsight ::
  ( OrchestrationDispatchRepository m
  , HypothesisProposalRepository m
  , SkillRegistryRepository m
  , InstructionProfileRepository m
  , FailureKnowledgeRepository m
  , SkillExecutor m
  ) =>
  OrchestrationDispatchIdentifier ->
  HypothesisProposalIdentifier ->
  FailureKnowledgeIdentifier ->
  InsightCollectedEvent ->
  UTCTime ->
  m (Either DomainError ())
orchestrateFromInsight dispatchIdentifier proposalIdentifier failureKnowledgeIdentifier event currentTime = do
  let traceText = pack (show event.trace)
  let snapshotResult =
        mkSourceEventSnapshot
          event.insightIdentifier
          InsightCollected
          event.occurredAt
          traceText
          "{}"
  case snapshotResult of
    Left domainError -> pure (Left domainError)
    Right snapshot -> do
      let (proposal, _) = fromInsightCollected proposalIdentifier event
      orchestrateCore
        dispatchIdentifier
        failureKnowledgeIdentifier
        snapshot
        event.trace
        proposal
        currentTime

{- | UC-AO: hypothesis.retest.requested イベントを受信して仮説提案をオーケストレーションする。

処理順序は orchestrateFromInsight と同一（RULE-AO-006 に従う）。
-}
orchestrateFromRetest ::
  ( OrchestrationDispatchRepository m
  , HypothesisProposalRepository m
  , SkillRegistryRepository m
  , InstructionProfileRepository m
  , FailureKnowledgeRepository m
  , SkillExecutor m
  ) =>
  OrchestrationDispatchIdentifier ->
  HypothesisProposalIdentifier ->
  FailureKnowledgeIdentifier ->
  RetestRequestedEvent ->
  UTCTime ->
  m (Either DomainError ())
orchestrateFromRetest dispatchIdentifier proposalIdentifier failureKnowledgeIdentifier event currentTime = do
  let retestTraceText = pack (show event.trace)
  let snapshotResult =
        mkSourceEventSnapshot
          event.retestIdentifier
          HypothesisRetestRequested
          event.occurredAt
          retestTraceText
          "{}"
  case snapshotResult of
    Left domainError -> pure (Left domainError)
    Right snapshot -> do
      let (proposal, _) = fromRetestRequested proposalIdentifier event
      orchestrateCore
        dispatchIdentifier
        failureKnowledgeIdentifier
        snapshot
        event.trace
        proposal
        currentTime

-- ---------------------------------------------------------------------------
-- Core orchestration (shared by both entry points)
-- ---------------------------------------------------------------------------

orchestrateCore ::
  ( OrchestrationDispatchRepository m
  , HypothesisProposalRepository m
  , SkillRegistryRepository m
  , InstructionProfileRepository m
  , FailureKnowledgeRepository m
  , SkillExecutor m
  ) =>
  OrchestrationDispatchIdentifier ->
  FailureKnowledgeIdentifier ->
  SourceEventSnapshot ->
  Trace ->
  HypothesisProposal ->
  UTCTime ->
  m (Either DomainError ())
orchestrateCore dispatchIdentifier failureKnowledgeIdentifier snapshot traceValue proposal currentTime = do
  -- Step 2: 冪等性チェック
  idempotencyResult <- checkIdempotency dispatchIdentifier snapshot traceValue currentTime
  case idempotencyResult of
    Left (AlreadyProcessed _) ->
      -- 重複イベント — サイレントスキップ
      pure (Right ())
    Left otherError ->
      pure (Left otherError)
    Right dispatchValue -> do
      -- Step 4: Skill 解決
      maybeSkill <- SkillRegistryRepository.find proposal.dispatch
      case maybeSkill of
        Nothing -> do
          let failResult = failProposal ResourceNotFound currentTime proposal
          let failedProposal = case failResult of
                Right (p, _) -> p
                Left _ -> proposal
          ProposalRepository.persist failedProposal
          _ <-
            registerFailure
              failureKnowledgeIdentifier
              ResourceNotFound
              "Skill not found"
              "## Skill Not Found\nThe required skill could not be resolved."
              currentTime
          pure (Left (InvariantViolation "HypothesisOrchestration" "Skill not found" ResourceNotFound))
        Just skill -> do
          -- Step 5: InstructionProfile 解決
          maybeProfile <- InstructionProfileRepository.findByVersion skill.version
          case maybeProfile of
            Nothing -> do
              let failResult = failProposal ResourceNotFound currentTime proposal
              let failedProposal = case failResult of
                    Right (p, _) -> p
                    Left _ -> proposal
              ProposalRepository.persist failedProposal
              _ <-
                registerFailure
                  failureKnowledgeIdentifier
                  ResourceNotFound
                  "InstructionProfile not found"
                  "## InstructionProfile Not Found\nThe required instruction profile could not be resolved."
                  currentTime
              pure (Left (InvariantViolation "HypothesisOrchestration" "InstructionProfile not found" ResourceNotFound))
            Just profile ->
              resolveAndExecute
                dispatchValue
                failureKnowledgeIdentifier
                proposal
                skill
                profile
                currentTime

resolveAndExecute ::
  ( OrchestrationDispatchRepository m
  , HypothesisProposalRepository m
  , FailureKnowledgeRepository m
  , SkillExecutor m
  ) =>
  OrchestrationDispatch ->
  FailureKnowledgeIdentifier ->
  HypothesisProposal ->
  Skill ->
  InstructionProfile ->
  UTCTime ->
  m (Either DomainError ())
resolveAndExecute dispatchValue failureKnowledgeIdentifier proposal skill profile currentTime = do
  -- Step 6: GenerationContext 解決
  -- "hypothesis-generation" スコープを必須として設定する（テンプレート不使用時も単一スコープで統一）
  let defaultTemplateScope = "hypothesis-generation"
  let policy = GenerationContextResolutionPolicy{requiredTemplateScopes = [defaultTemplateScope]}
  let skillResolutionInput =
        SkillResolutionInput
          { skillName = skill.name
          , skillVersion = skill.version
          , available = True
          }
  let profileResolutionInput =
        ProfileResolutionInput
          { profileName = profile.name
          , profileVersion = profile.version
          , available = True
          }
  let templateResolutionInput =
        TemplateResolutionInput
          { templateScope = defaultTemplateScope
          , available = True
          }
  case resolveGenerationContext policy skillResolutionInput profileResolutionInput templateResolutionInput of
    Left domainError -> do
      let failResult = failProposal ResourceNotFound currentTime proposal
      let failedProposal = case failResult of
            Right (p, _) -> p
            Left _ -> proposal
      ProposalRepository.persist failedProposal
      _ <-
        registerFailure
          failureKnowledgeIdentifier
          ResourceNotFound
          "GenerationContext resolution failed"
          "## GenerationContext Resolution Failed\nRequired resources could not be resolved."
          currentTime
      pure (Left domainError)
    Right () -> do
      -- Step 7: GenerationContext アタッチ
      let generationContext =
            mkGenerationContext
              skill.name
              skill.version
              profile.name
              profile.version
              ""
      case attachGenerationContext generationContext currentTime proposal of
        Left domainError -> pure (Left domainError)
        Right (proposalWithContext, _) -> do
          -- Step 8: FailureKnowledge 重複チェック
          existingKnowledgeEntries <- FailureKnowledgeRepository.search emptyFailureKnowledgeSearchCriteria
          let suppressionPolicy = DuplicateSuppressionPolicy{suppressOnBlock = True}
          -- 類似知見が存在する場合は Block 判定のアセスメントを生成し、閾値未満なら Allow とする
          let duplicateDecision = if null existingKnowledgeEntries then Allow else Block
          let similarityScore = if null existingKnowledgeEntries then 0.0 else 1.0
          let duplicateAssessment = mkDuplicateAssessment "" similarityScore 0.5 duplicateDecision Nothing
          let isDuplicate = shouldSuppress suppressionPolicy duplicateAssessment
          if isDuplicate
            then do
              let knowledgeSummary =
                    mkFailureKnowledgeSummary StateConflict "Duplicate detected" "## Duplicate\nSimilar hypothesis already exists."
              case blockProposal StateConflict knowledgeSummary currentTime proposalWithContext of
                Left domainError -> pure (Left domainError)
                Right (blockedProposal, _) -> do
                  ProposalRepository.persist blockedProposal
                  _ <-
                    registerFailure
                      failureKnowledgeIdentifier
                      StateConflict
                      "Duplicate proposal blocked"
                      "## Duplicate Proposal Blocked\nSimilar hypothesis already exists in knowledge base."
                      currentTime
                  pure (Left (InvariantViolation "HypothesisOrchestration" "Duplicate suppressed" StateConflict))
            else do
              -- Step 10: SkillExecutor 実行
              let executionInput =
                    SkillInput
                      { skillName = skill.name
                      , skillVersion = skill.version
                      , promptHash = ""
                      , contextPayload = "{}"
                      }
              executionResult <- executeSkill executionInput
              case executionResult of
                Left domainError -> do
                  let reasonCodeValue = extractReasonCode domainError
                  let failResult = failProposal reasonCodeValue currentTime proposalWithContext
                  let failedProposal = case failResult of
                        Right (p, _) -> p
                        Left _ -> proposalWithContext
                  ProposalRepository.persist failedProposal
                  _ <-
                    registerFailure
                      failureKnowledgeIdentifier
                      reasonCodeValue
                      "Skill execution failed"
                      "## Skill Execution Failed\nThe skill executor returned an error."
                      currentTime
                  pure (Left domainError)
                Right skillOutput -> do
                  -- Step 11: completeProposal
                  let artifact = mkProposalArtifact "/reports/generated.md" skillOutput.llmModel currentTime
                  case completeProposal
                    "GENERATED"
                    ETF
                    "Generated Hypothesis"
                    skillOutput.sourceEvidence
                    skill.version
                    profile.version
                    Nothing
                    Nothing
                    artifact
                    currentTime
                    proposalWithContext of
                    Left domainError -> pure (Left domainError)
                    Right (completedProposal, _) -> do
                      -- Step 12: RULE-AO-006 — persist proposal FIRST
                      ProposalRepository.persist completedProposal
                      -- Step 13: markPublished + persist dispatch
                      let decision = mkDispatchDecision HypothesisProposed True
                      let proposalIdentifierValue = completedProposal.identifier.value
                      let proposalReference = pack (show proposalIdentifierValue)
                      case markPublished HypothesisProposed decision proposalReference currentTime dispatchValue of
                        Left _ ->
                          -- Dispatch 更新失敗は非致命的（Proposal は既に永続化済み）
                          pure (Right ())
                        Right publishedDispatch -> do
                          DispatchRepository.persist publishedDispatch
                          pure (Right ())

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

extractReasonCode :: DomainError -> ReasonCode
extractReasonCode (InvalidStateTransition _ _ code) = code
extractReasonCode (MissingRequiredFields _ code) = code
extractReasonCode (InvariantViolation _ _ code) = code
extractReasonCode (AlreadyProcessed code) = code
