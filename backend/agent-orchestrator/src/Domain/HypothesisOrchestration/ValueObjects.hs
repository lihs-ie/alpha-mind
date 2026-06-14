{-# LANGUAGE NoFieldSelectors #-}

module Domain.HypothesisOrchestration.ValueObjects (
  -- * GenerationContext
  GenerationContext,
  mkGenerationContext,
  generationContextSkill,
  generationContextSkillVersion,
  generationContextInstructionProfile,
  generationContextInstructionProfileVersion,
  generationContextPromptHash,

  -- * DuplicateAssessment
  DuplicateAssessmentDecision (..),
  DuplicateAssessment,
  mkDuplicateAssessment,
  duplicateAssessmentSimilarityHash,
  duplicateAssessmentMaxSimilarityScore,
  duplicateAssessmentThreshold,
  duplicateAssessmentDecision,
  duplicateAssessmentMatchedKnowledge,

  -- * ProposalArtifact
  ProposalArtifact,
  mkProposalArtifact,
  proposalArtifactReportPath,
  proposalArtifactLlmModel,
  proposalArtifactGeneratedAt,

  -- * FailureKnowledgeSummary
  FailureKnowledgeSummary,
  mkFailureKnowledgeSummary,
  failureKnowledgeSummaryReasonCode,
  failureKnowledgeSummarySummary,
  failureKnowledgeSummaryMarkdownSummary,

  -- * SourceEventSnapshot
  SourceEventType (..),
  SourceEventSnapshot,
  mkSourceEventSnapshot,
  sourceEventSnapshotIdentifier,
  sourceEventSnapshotEventType,
  sourceEventSnapshotOccurredAt,
  sourceEventSnapshotTrace,
  sourceEventSnapshotPayload,

  -- * DispatchDecision
  PublishedEventType (..),
  DispatchDecision,
  mkDispatchDecision,
  dispatchDecisionPublishedEvent,
  dispatchDecisionRetryable,

  -- * InsiderRiskLevel
  InsiderRiskLevel (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- InsiderRiskLevel
-- ---------------------------------------------------------------------

-- | インサイダー取引リスクレベル。
data InsiderRiskLevel
  = Low
  | Medium
  | High
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- GenerationContext (Must-11)
-- ---------------------------------------------------------------------

-- | Must-11: GenerationContext — Skill/指示書/テンプレート解決コンテキスト（immutable, 値比較）。
data GenerationContext = GenerationContext
  { gcSkill :: Text
  , gcSkillVersion :: Text
  , gcInstructionProfile :: Text
  , gcInstructionProfileVersion :: Text
  , gcPromptHash :: Text
  }
  deriving stock (Eq, Show)

mkGenerationContext :: Text -> Text -> Text -> Text -> Text -> GenerationContext
mkGenerationContext skillName skillVersion instructionProfile instructionProfileVersion promptHash =
  GenerationContext
    { gcSkill = skillName
    , gcSkillVersion = skillVersion
    , gcInstructionProfile = instructionProfile
    , gcInstructionProfileVersion = instructionProfileVersion
    , gcPromptHash = promptHash
    }

generationContextSkill :: GenerationContext -> Text
generationContextSkill GenerationContext{gcSkill = x} = x

generationContextSkillVersion :: GenerationContext -> Text
generationContextSkillVersion GenerationContext{gcSkillVersion = x} = x

generationContextInstructionProfile :: GenerationContext -> Text
generationContextInstructionProfile GenerationContext{gcInstructionProfile = x} = x

generationContextInstructionProfileVersion :: GenerationContext -> Text
generationContextInstructionProfileVersion GenerationContext{gcInstructionProfileVersion = x} = x

generationContextPromptHash :: GenerationContext -> Text
generationContextPromptHash GenerationContext{gcPromptHash = x} = x

instance HasField "skill" GenerationContext Text where
  getField GenerationContext{gcSkill = x} = x

instance HasField "skillVersion" GenerationContext Text where
  getField GenerationContext{gcSkillVersion = x} = x

instance HasField "instructionProfile" GenerationContext Text where
  getField GenerationContext{gcInstructionProfile = x} = x

instance HasField "instructionProfileVersion" GenerationContext Text where
  getField GenerationContext{gcInstructionProfileVersion = x} = x

instance HasField "promptHash" GenerationContext Text where
  getField GenerationContext{gcPromptHash = x} = x

-- ---------------------------------------------------------------------
-- DuplicateAssessment (Must-12)
-- ---------------------------------------------------------------------

-- | 重複アセスメントの最終決定。
data DuplicateAssessmentDecision
  = Allow
  | Block
  deriving stock (Eq, Ord, Show)

-- | Must-12: DuplicateAssessment — 類似度評価結果（immutable, 値比較）。
data DuplicateAssessment = DuplicateAssessment
  { dasSimilarityHash :: Text
  , dasMaxSimilarityScore :: Double
  , dasThreshold :: Double
  , dasDecision :: DuplicateAssessmentDecision
  , dasMatchedKnowledge :: Maybe Text
  }
  deriving stock (Eq, Show)

mkDuplicateAssessment ::
  Text ->
  Double ->
  Double ->
  DuplicateAssessmentDecision ->
  Maybe Text ->
  DuplicateAssessment
mkDuplicateAssessment similarityHash maxScore threshold decision matchedKnowledge =
  DuplicateAssessment
    { dasSimilarityHash = similarityHash
    , dasMaxSimilarityScore = maxScore
    , dasThreshold = threshold
    , dasDecision = decision
    , dasMatchedKnowledge = matchedKnowledge
    }

duplicateAssessmentSimilarityHash :: DuplicateAssessment -> Text
duplicateAssessmentSimilarityHash DuplicateAssessment{dasSimilarityHash = x} = x

duplicateAssessmentMaxSimilarityScore :: DuplicateAssessment -> Double
duplicateAssessmentMaxSimilarityScore DuplicateAssessment{dasMaxSimilarityScore = x} = x

duplicateAssessmentThreshold :: DuplicateAssessment -> Double
duplicateAssessmentThreshold DuplicateAssessment{dasThreshold = x} = x

duplicateAssessmentDecision :: DuplicateAssessment -> DuplicateAssessmentDecision
duplicateAssessmentDecision DuplicateAssessment{dasDecision = x} = x

duplicateAssessmentMatchedKnowledge :: DuplicateAssessment -> Maybe Text
duplicateAssessmentMatchedKnowledge DuplicateAssessment{dasMatchedKnowledge = x} = x

instance HasField "similarityHash" DuplicateAssessment Text where
  getField DuplicateAssessment{dasSimilarityHash = x} = x

instance HasField "maxSimilarityScore" DuplicateAssessment Double where
  getField DuplicateAssessment{dasMaxSimilarityScore = x} = x

instance HasField "threshold" DuplicateAssessment Double where
  getField DuplicateAssessment{dasThreshold = x} = x

instance HasField "decision" DuplicateAssessment DuplicateAssessmentDecision where
  getField DuplicateAssessment{dasDecision = x} = x

instance HasField "matchedKnowledge" DuplicateAssessment (Maybe Text) where
  getField DuplicateAssessment{dasMatchedKnowledge = x} = x

-- ---------------------------------------------------------------------
-- ProposalArtifact (Must-13)
-- ---------------------------------------------------------------------

-- | Must-13: ProposalArtifact — 生成仮説成果物のメタデータ（immutable, 値比較）。
data ProposalArtifact = ProposalArtifact
  { paReportPath :: Text
  , paLlmModel :: Text
  , paGeneratedAt :: UTCTime
  }
  deriving stock (Eq, Show)

mkProposalArtifact :: Text -> Text -> UTCTime -> ProposalArtifact
mkProposalArtifact reportPath llmModel generatedAt =
  ProposalArtifact
    { paReportPath = reportPath
    , paLlmModel = llmModel
    , paGeneratedAt = generatedAt
    }

proposalArtifactReportPath :: ProposalArtifact -> Text
proposalArtifactReportPath ProposalArtifact{paReportPath = x} = x

proposalArtifactLlmModel :: ProposalArtifact -> Text
proposalArtifactLlmModel ProposalArtifact{paLlmModel = x} = x

proposalArtifactGeneratedAt :: ProposalArtifact -> UTCTime
proposalArtifactGeneratedAt ProposalArtifact{paGeneratedAt = x} = x

instance HasField "reportPath" ProposalArtifact Text where
  getField ProposalArtifact{paReportPath = x} = x

instance HasField "llmModel" ProposalArtifact Text where
  getField ProposalArtifact{paLlmModel = x} = x

instance HasField "generatedAt" ProposalArtifact UTCTime where
  getField ProposalArtifact{paGeneratedAt = x} = x

-- ---------------------------------------------------------------------
-- FailureKnowledgeSummary (Must-14)
-- ---------------------------------------------------------------------

-- | Must-14: FailureKnowledgeSummary — 失敗知見の要約（immutable, 値比較）。
data FailureKnowledgeSummary = FailureKnowledgeSummary
  { fksReasonCode :: ReasonCode
  , fksSummary :: Text
  , fksMarkdownSummary :: Text
  }
  deriving stock (Eq, Show)

mkFailureKnowledgeSummary :: ReasonCode -> Text -> Text -> FailureKnowledgeSummary
mkFailureKnowledgeSummary reasonCode summary markdownSummary =
  FailureKnowledgeSummary
    { fksReasonCode = reasonCode
    , fksSummary = summary
    , fksMarkdownSummary = markdownSummary
    }

failureKnowledgeSummaryReasonCode :: FailureKnowledgeSummary -> ReasonCode
failureKnowledgeSummaryReasonCode FailureKnowledgeSummary{fksReasonCode = x} = x

failureKnowledgeSummarySummary :: FailureKnowledgeSummary -> Text
failureKnowledgeSummarySummary FailureKnowledgeSummary{fksSummary = x} = x

failureKnowledgeSummaryMarkdownSummary :: FailureKnowledgeSummary -> Text
failureKnowledgeSummaryMarkdownSummary FailureKnowledgeSummary{fksMarkdownSummary = x} = x

instance HasField "reasonCode" FailureKnowledgeSummary ReasonCode where
  getField FailureKnowledgeSummary{fksReasonCode = x} = x

instance HasField "summary" FailureKnowledgeSummary Text where
  getField FailureKnowledgeSummary{fksSummary = x} = x

instance HasField "markdownSummary" FailureKnowledgeSummary Text where
  getField FailureKnowledgeSummary{fksMarkdownSummary = x} = x

-- ---------------------------------------------------------------------
-- SourceEventSnapshot (Must-15)
-- ---------------------------------------------------------------------

-- | ソースイベント種別。
data SourceEventType
  = InsightCollected
  | HypothesisRetestRequested
  deriving stock (Eq, Ord, Show)

{- | Must-15: SourceEventSnapshot — 受信イベントの不変スナップショット（immutable, 値比較）。
コンストラクタは隠蔽。mkSourceEventSnapshot 経由でのみ生成可能（Must-40）。
-}
data SourceEventSnapshot = SourceEventSnapshot
  { sesIdentifier :: Text
  , sesEventType :: SourceEventType
  , sesOccurredAt :: UTCTime
  , sesTrace :: Text
  , sesPayload :: Text
  }
  deriving stock (Eq, Show)

{- | Must-40: SourceEventSnapshot スマートコンストラクタ。
必須フィールド欠損時に REQUEST_VALIDATION_FAILED を返す。
-}
mkSourceEventSnapshot ::
  Text ->
  SourceEventType ->
  UTCTime ->
  Text ->
  Text ->
  Either DomainError SourceEventSnapshot
mkSourceEventSnapshot eventIdentifier eventType occurredAt traceValue payload =
  let missingFields =
        ["identifier" | eventIdentifier == ""]
          ++ ["trace" | traceValue == ""]
          ++ ["payload" | payload == ""]
   in case missingFields of
        [] ->
          Right
            SourceEventSnapshot
              { sesIdentifier = eventIdentifier
              , sesEventType = eventType
              , sesOccurredAt = occurredAt
              , sesTrace = traceValue
              , sesPayload = payload
              }
        fields ->
          Left
            ( MissingRequiredFields
                fields
                RequestValidationFailed
            )

sourceEventSnapshotIdentifier :: SourceEventSnapshot -> Text
sourceEventSnapshotIdentifier SourceEventSnapshot{sesIdentifier = x} = x

sourceEventSnapshotEventType :: SourceEventSnapshot -> SourceEventType
sourceEventSnapshotEventType SourceEventSnapshot{sesEventType = x} = x

sourceEventSnapshotOccurredAt :: SourceEventSnapshot -> UTCTime
sourceEventSnapshotOccurredAt SourceEventSnapshot{sesOccurredAt = x} = x

sourceEventSnapshotTrace :: SourceEventSnapshot -> Text
sourceEventSnapshotTrace SourceEventSnapshot{sesTrace = x} = x

sourceEventSnapshotPayload :: SourceEventSnapshot -> Text
sourceEventSnapshotPayload SourceEventSnapshot{sesPayload = x} = x

-- ---------------------------------------------------------------------
-- DispatchDecision (Must-16)
-- ---------------------------------------------------------------------

-- | 発行イベント種別。
data PublishedEventType
  = HypothesisProposed
  | HypothesisProposalFailed
  deriving stock (Eq, Ord, Show)

-- | Must-16: DispatchDecision — ディスパッチ判定結果（immutable, 値比較）。
data DispatchDecision = DispatchDecision
  { ddPublishedEvent :: PublishedEventType
  , ddRetryable :: Bool
  }
  deriving stock (Eq, Show)

mkDispatchDecision :: PublishedEventType -> Bool -> DispatchDecision
mkDispatchDecision publishedEvent retryable =
  DispatchDecision
    { ddPublishedEvent = publishedEvent
    , ddRetryable = retryable
    }

dispatchDecisionPublishedEvent :: DispatchDecision -> PublishedEventType
dispatchDecisionPublishedEvent DispatchDecision{ddPublishedEvent = x} = x

dispatchDecisionRetryable :: DispatchDecision -> Bool
dispatchDecisionRetryable DispatchDecision{ddRetryable = x} = x

instance HasField "publishedEvent" DispatchDecision PublishedEventType where
  getField DispatchDecision{ddPublishedEvent = x} = x

instance HasField "retryable" DispatchDecision Bool where
  getField DispatchDecision{ddRetryable = x} = x
