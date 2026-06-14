module Domain.HypothesisOrchestration.ValueObjectsSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (
  DuplicateAssessmentDecision (..),
  InsiderRiskLevel (..),
  PublishedEventType (..),
  SourceEventType (..),
  dispatchDecisionPublishedEvent,
  dispatchDecisionRetryable,
  duplicateAssessmentDecision,
  duplicateAssessmentMatchedKnowledge,
  duplicateAssessmentMaxSimilarityScore,
  duplicateAssessmentSimilarityHash,
  duplicateAssessmentThreshold,
  failureKnowledgeSummaryMarkdownSummary,
  failureKnowledgeSummaryReasonCode,
  failureKnowledgeSummarySummary,
  generationContextInstructionProfile,
  generationContextInstructionProfileVersion,
  generationContextPromptHash,
  generationContextSkill,
  generationContextSkillVersion,
  mkDispatchDecision,
  mkDuplicateAssessment,
  mkFailureKnowledgeSummary,
  mkGenerationContext,
  mkProposalArtifact,
  mkSourceEventSnapshot,
  proposalArtifactGeneratedAt,
  proposalArtifactLlmModel,
  proposalArtifactReportPath,
  sourceEventSnapshotEventType,
  sourceEventSnapshotIdentifier,
  sourceEventSnapshotOccurredAt,
  sourceEventSnapshotPayload,
  sourceEventSnapshotTrace,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

spec :: Spec
spec =
  describe "Domain.HypothesisOrchestration.ValueObjects" $ do
    -- Must-11: GenerationContext テスト
    describe "GenerationContext (Must-11)" $ do
      it "holds all required fields" $ do
        let context = mkGenerationContext "hypothesis-skill" "1.0.0" "default-profile" "2.0.0" "abc123"
        generationContextSkill context `shouldBe` "hypothesis-skill"
        generationContextSkillVersion context `shouldBe` "1.0.0"
        generationContextInstructionProfile context `shouldBe` "default-profile"
        generationContextInstructionProfileVersion context `shouldBe` "2.0.0"
        generationContextPromptHash context `shouldBe` "abc123"

      it "supports value equality" $ do
        let context1 = mkGenerationContext "s" "1" "p" "1" "h"
            context2 = mkGenerationContext "s" "1" "p" "1" "h"
        context1 `shouldBe` context2

    -- Must-12: DuplicateAssessment テスト
    describe "DuplicateAssessment (Must-12)" $ do
      it "holds all required fields" $ do
        let assessment = mkDuplicateAssessment "hash-001" 0.85 0.80 Allow Nothing
        duplicateAssessmentSimilarityHash assessment `shouldBe` "hash-001"
        duplicateAssessmentMaxSimilarityScore assessment `shouldBe` 0.85
        duplicateAssessmentThreshold assessment `shouldBe` 0.80
        duplicateAssessmentDecision assessment `shouldBe` Allow
        duplicateAssessmentMatchedKnowledge assessment `shouldBe` Nothing

      it "supports Block decision with matchedKnowledge" $ do
        let assessment = mkDuplicateAssessment "hash-002" 0.95 0.80 Block (Just "knowledge-001")
        duplicateAssessmentDecision assessment `shouldBe` Block
        duplicateAssessmentMatchedKnowledge assessment `shouldBe` Just "knowledge-001"

    -- Must-13: ProposalArtifact テスト
    describe "ProposalArtifact (Must-13)" $ do
      it "holds reportPath, llmModel, generatedAt" $ do
        let artifact = mkProposalArtifact "/reports/2026-01-15.md" "gpt-4o" fixedTime
        proposalArtifactReportPath artifact `shouldBe` "/reports/2026-01-15.md"
        proposalArtifactLlmModel artifact `shouldBe` "gpt-4o"
        proposalArtifactGeneratedAt artifact `shouldBe` fixedTime

    -- Must-14: FailureKnowledgeSummary テスト
    describe "FailureKnowledgeSummary (Must-14)" $ do
      it "holds reasonCode, summary, markdownSummary" $ do
        let knowledgeSummary = mkFailureKnowledgeSummary ResourceNotFound "Skill not found" "## Skill not found\n..."
        failureKnowledgeSummaryReasonCode knowledgeSummary `shouldBe` ResourceNotFound
        failureKnowledgeSummarySummary knowledgeSummary `shouldBe` "Skill not found"
        failureKnowledgeSummaryMarkdownSummary knowledgeSummary `shouldBe` "## Skill not found\n..."

    -- Must-15 / Must-40: SourceEventSnapshot テスト
    describe "SourceEventSnapshot (Must-15, Must-40)" $ do
      it "constructs successfully with all required fields" $ do
        mkSourceEventSnapshot
          "event-001"
          InsightCollected
          fixedTime
          "trace-001"
          "{\"key\":\"value\"}"
          `shouldSatisfy` isRight

      it "rejects empty identifier (Must-40 REQUEST_VALIDATION_FAILED)" $ do
        let result = mkSourceEventSnapshot "" InsightCollected fixedTime "trace-001" "payload"
        result `shouldSatisfy` isLeft
        case result of
          Left (MissingRequiredFields fields RequestValidationFailed) ->
            fields `shouldBe` ["identifier"]
          Left other -> fail ("Unexpected error: " ++ show other)
          Right _ -> fail "Expected Left"

      it "rejects empty trace (Must-40 REQUEST_VALIDATION_FAILED)" $ do
        let result = mkSourceEventSnapshot "id-001" InsightCollected fixedTime "" "payload"
        result `shouldSatisfy` isLeft
        case result of
          Left (MissingRequiredFields fields RequestValidationFailed) ->
            fields `shouldBe` ["trace"]
          Left other -> fail ("Unexpected error: " ++ show other)
          Right _ -> fail "Expected Left"

      it "rejects empty payload (Must-40 REQUEST_VALIDATION_FAILED)" $ do
        let result = mkSourceEventSnapshot "id-001" InsightCollected fixedTime "trace-001" ""
        result `shouldSatisfy` isLeft
        case result of
          Left (MissingRequiredFields fields RequestValidationFailed) ->
            fields `shouldBe` ["payload"]
          Left other -> fail ("Unexpected error: " ++ show other)
          Right _ -> fail "Expected Left"

      it "provides accessor functions for all fields" $ do
        case mkSourceEventSnapshot "event-123" HypothesisRetestRequested fixedTime "trace-abc" "data" of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right snapshot -> do
            sourceEventSnapshotIdentifier snapshot `shouldBe` "event-123"
            sourceEventSnapshotEventType snapshot `shouldBe` HypothesisRetestRequested
            sourceEventSnapshotOccurredAt snapshot `shouldBe` fixedTime
            sourceEventSnapshotTrace snapshot `shouldBe` "trace-abc"
            sourceEventSnapshotPayload snapshot `shouldBe` "data"

    -- Must-16: DispatchDecision テスト
    describe "DispatchDecision (Must-16)" $ do
      it "holds publishedEvent and retryable" $ do
        let decision = mkDispatchDecision HypothesisProposed False
        dispatchDecisionPublishedEvent decision `shouldBe` HypothesisProposed
        dispatchDecisionRetryable decision `shouldBe` False

      it "supports HypothesisProposalFailed event type" $ do
        let decision = mkDispatchDecision HypothesisProposalFailed True
        dispatchDecisionPublishedEvent decision `shouldBe` HypothesisProposalFailed
        dispatchDecisionRetryable decision `shouldBe` True

    -- InsiderRiskLevel テスト
    describe "InsiderRiskLevel" $ do
      it "has Low, Medium, High values" $ do
        Low `shouldBe` Low
        Medium `shouldBe` Medium
        High `shouldBe` High
