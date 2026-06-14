module Domain.HypothesisOrchestration.AggregateSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposal,
  HypothesisProposalEvent (..),
  HypothesisProposalIdentifier (..),
  InstrumentType (..),
  ProposalStatus (..),
  assessDuplicateRisk,
  attachGenerationContext,
  blockProposal,
  completeProposal,
  failProposal,
  startProposal,
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (
  DuplicateAssessment,
  DuplicateAssessmentDecision (..),
  FailureKnowledgeSummary,
  GenerationContext,
  ProposalArtifact,
  duplicateAssessmentDecision,
  mkDuplicateAssessment,
  mkFailureKnowledgeSummary,
  mkGenerationContext,
  mkProposalArtifact,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

fixedTime2 :: UTCTime
fixedTime2 = UTCTime (fromGregorian 2026 1 16) 0

testIdentifier :: HypothesisProposalIdentifier
testIdentifier = HypothesisProposalIdentifier (mkULID 1)

testTrace :: Trace
testTrace = Trace (mkULID 100)

mkPendingProposal :: (HypothesisProposal, [HypothesisProposalEvent])
mkPendingProposal = startProposal testIdentifier "dispatch-ref-001" testTrace fixedTime

testContext :: GenerationContext
testContext =
  mkGenerationContext "hypothesis-skill" "1.0.0" "default-profile" "2.0.0" "abc123"

testAssessment :: DuplicateAssessment
testAssessment =
  mkDuplicateAssessment "hash-001" 0.3 0.8 Allow Nothing

testArtifact :: ProposalArtifact
testArtifact =
  mkProposalArtifact "/reports/2026-01-15.md" "gpt-4o" fixedTime

testKnowledgeSummary :: FailureKnowledgeSummary
testKnowledgeSummary =
  mkFailureKnowledgeSummary StateConflict "Duplicate detected" "## Duplicate\n..."

spec :: Spec
spec =
  describe "Domain.HypothesisOrchestration.Aggregate" $ do
    -- Must-36: 識別子型テスト
    describe "HypothesisProposalIdentifier (Must-36)" $ do
      it "supports equality" $ do
        HypothesisProposalIdentifier (mkULID 1) `shouldBe` HypothesisProposalIdentifier (mkULID 1)
        HypothesisProposalIdentifier (mkULID 1) `shouldNotBe` HypothesisProposalIdentifier (mkULID 2)

      it "supports ordering" $ do
        compare (HypothesisProposalIdentifier (mkULID 1)) (HypothesisProposalIdentifier (mkULID 2))
          `shouldBe` LT

    -- Must-02: ProposalStatus テスト
    describe "ProposalStatus (Must-02)" $ do
      it "has exactly Pending, Proposed, Blocked, Failed" $ do
        Pending `shouldBe` Pending
        Proposed `shouldBe` Proposed
        Blocked `shouldBe` Blocked
        Failed `shouldBe` Failed
        Pending `shouldNotBe` Proposed
        Proposed `shouldNotBe` Blocked
        Blocked `shouldNotBe` Failed

    -- Must-01 / Must-37: startProposal テスト
    describe "startProposal (Must-01, Must-37)" $ do
      it "creates Pending proposal with given identifier" $ do
        let (proposal, _) = mkPendingProposal
        proposal.status `shouldBe` Pending
        proposal.identifier `shouldBe` testIdentifier
        proposal.symbol `shouldBe` Nothing
        proposal.sourceEvidence `shouldBe` []
        proposal.reasonCode `shouldBe` Nothing

      it "uses 'identifier' field name (Must-37)" $ do
        let (proposal, _) = mkPendingProposal
        proposal.identifier `shouldBe` testIdentifier

      it "uses 'dispatch' field name without Identifier suffix (Must-38)" $ do
        let (proposal, _) = mkPendingProposal
        proposal.dispatch `shouldBe` "dispatch-ref-001"

      it "emits HypothesisProposalStarted event" $ do
        let (_, events) = mkPendingProposal
        case events of
          [event] ->
            event
              `shouldBe` HypothesisProposalStarted
                { identifier = testIdentifier
                , dispatch = "dispatch-ref-001"
                , trace = testTrace
                }
          _ -> fail ("Expected exactly 1 event, got " ++ show (length events))

    -- Must-05 INV-AO-005: identifier immutability テスト
    describe "identifier immutability (Must-05 INV-AO-005)" $ do
      it "identifier does not change after attachGenerationContext" $ do
        let (proposal, _) = mkPendingProposal
        case attachGenerationContext testContext fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (updated, _) -> updated.identifier `shouldBe` testIdentifier

      it "identifier does not change after completeProposal" $ do
        let (proposal, _) = mkPendingProposal
        case completeProposal
          "7203.T"
          Stock
          "Toyota Recovery Hypothesis"
          ["evidence-1", "evidence-2"]
          "1.0.0"
          "2.0.0"
          Nothing
          Nothing
          testArtifact
          fixedTime2
          proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (updated, _) -> updated.identifier `shouldBe` testIdentifier

    -- Must-03 INV-AO-001: completeProposal バリデーションテスト
    describe "completeProposal INV-AO-001 (Must-03)" $ do
      it "transitions Pending to Proposed with all required fields" $ do
        let (proposal, _) = mkPendingProposal
        completeProposal
          "7203.T"
          Stock
          "Toyota Recovery Hypothesis"
          ["evidence-1", "evidence-2"]
          "1.0.0"
          "2.0.0"
          Nothing
          Nothing
          testArtifact
          fixedTime2
          proposal
          `shouldSatisfy` isRight

      it "rejects when symbol is empty (INV-AO-001)" $ do
        let (proposal, _) = mkPendingProposal
        completeProposal
          ""
          Stock
          "Toyota Recovery Hypothesis"
          ["evidence-1"]
          "1.0.0"
          "2.0.0"
          Nothing
          Nothing
          testArtifact
          fixedTime2
          proposal
          `shouldSatisfy` isLeft

      it "rejects when title is empty (INV-AO-001)" $ do
        let (proposal, _) = mkPendingProposal
        completeProposal
          "7203.T"
          Stock
          ""
          ["evidence-1"]
          "1.0.0"
          "2.0.0"
          Nothing
          Nothing
          testArtifact
          fixedTime2
          proposal
          `shouldSatisfy` isLeft

      it "rejects when sourceEvidence is empty (INV-AO-001)" $ do
        let (proposal, _) = mkPendingProposal
        completeProposal
          "7203.T"
          Stock
          "Title"
          []
          "1.0.0"
          "2.0.0"
          Nothing
          Nothing
          testArtifact
          fixedTime2
          proposal
          `shouldSatisfy` isLeft

      it "rejects when skillVersion is empty (INV-AO-001)" $ do
        let (proposal, _) = mkPendingProposal
        completeProposal
          "7203.T"
          Stock
          "Title"
          ["ev-1"]
          ""
          "2.0.0"
          Nothing
          Nothing
          testArtifact
          fixedTime2
          proposal
          `shouldSatisfy` isLeft

      it "rejects when instructionProfileVersion is empty (INV-AO-001)" $ do
        let (proposal, _) = mkPendingProposal
        completeProposal
          "7203.T"
          Stock
          "Title"
          ["ev-1"]
          "1.0.0"
          ""
          Nothing
          Nothing
          testArtifact
          fixedTime2
          proposal
          `shouldSatisfy` isLeft

      it "rejects transition from non-Pending status" $ do
        let (proposal, _) = mkPendingProposal
        case completeProposal
          "7203.T"
          Stock
          "Title"
          ["ev-1"]
          "1.0.0"
          "2.0.0"
          Nothing
          Nothing
          testArtifact
          fixedTime2
          proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (proposed, _) ->
            completeProposal
              "7203.T"
              Stock
              "Title"
              ["ev-1"]
              "1.0.0"
              "2.0.0"
              Nothing
              Nothing
              testArtifact
              fixedTime2
              proposed
              `shouldSatisfy` isLeft

      it "emits HypothesisProposalComposed event on success" $ do
        let (proposal, _) = mkPendingProposal
        case completeProposal
          "7203.T"
          Stock
          "Toyota Recovery Hypothesis"
          ["evidence-1", "evidence-2"]
          "1.0.0"
          "2.0.0"
          Nothing
          Nothing
          testArtifact
          fixedTime2
          proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (_, [event]) ->
            event
              `shouldBe` HypothesisProposalComposed
                { identifier = testIdentifier
                , symbol = "7203.T"
                , instrumentType = Stock
                , skillVersion = "1.0.0"
                , instructionProfileVersion = "2.0.0"
                , trace = testTrace
                }
          Right (_, events) -> fail ("Expected 1 event, got " ++ show (length events))

    -- Must-04 INV-AO-002: blockProposal テスト
    describe "blockProposal INV-AO-002 (Must-04)" $ do
      it "transitions Pending to Blocked with reasonCode" $ do
        let (proposal, _) = mkPendingProposal
        case blockProposal StateConflict testKnowledgeSummary fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (updated, _) -> do
            updated.status `shouldBe` Blocked
            updated.reasonCode `shouldBe` Just StateConflict

      it "rejects transition from non-Pending status (INV-AO-002)" $ do
        let (proposal, _) = mkPendingProposal
        case blockProposal StateConflict testKnowledgeSummary fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (blocked, _) ->
            blockProposal StateConflict testKnowledgeSummary fixedTime2 blocked
              `shouldSatisfy` isLeft

      it "emits HypothesisProposalBlocked event" $ do
        let (proposal, _) = mkPendingProposal
        case blockProposal StateConflict testKnowledgeSummary fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (_, [event]) ->
            event
              `shouldBe` HypothesisProposalBlocked
                { identifier = testIdentifier
                , reasonCode = StateConflict
                , trace = testTrace
                }
          Right (_, events) -> fail ("Expected 1 event, got " ++ show (length events))

      -- Must-42 RULE-AO-003: blockProposal は STATE_CONFLICT を reasonCode に設定できる
      it "can use STATE_CONFLICT as reasonCode (Must-42 RULE-AO-003)" $ do
        let (proposal, _) = mkPendingProposal
        case blockProposal StateConflict testKnowledgeSummary fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (updated, _) -> updated.reasonCode `shouldBe` Just StateConflict

    -- Must-04 INV-AO-002: failProposal テスト
    describe "failProposal INV-AO-002 (Must-04)" $ do
      it "transitions Pending to Failed with reasonCode" $ do
        let (proposal, _) = mkPendingProposal
        case failProposal DependencyTimeout fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (updated, _) -> do
            updated.status `shouldBe` Failed
            updated.reasonCode `shouldBe` Just DependencyTimeout

      it "rejects transition from non-Pending status" $ do
        let (proposal, _) = mkPendingProposal
        case failProposal DependencyTimeout fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (failed, _) ->
            failProposal DependencyUnavailable fixedTime2 failed
              `shouldSatisfy` isLeft

      it "emits HypothesisProposalFailed event" $ do
        let (proposal, _) = mkPendingProposal
        case failProposal DependencyTimeout fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (_, [event]) ->
            event
              `shouldBe` HypothesisProposalFailed
                { identifier = testIdentifier
                , reasonCode = DependencyTimeout
                , trace = testTrace
                }
          Right (_, events) -> fail ("Expected 1 event, got " ++ show (length events))

    -- attachGenerationContext テスト
    describe "attachGenerationContext" $ do
      it "attaches context to Pending proposal" $ do
        let (proposal, _) = mkPendingProposal
        case attachGenerationContext testContext fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (updated, events) -> do
            updated.generationContext `shouldBe` Just testContext
            events `shouldBe` []

      it "rejects from non-Pending status" $ do
        let (proposal, _) = mkPendingProposal
        case blockProposal StateConflict testKnowledgeSummary fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (blocked, _) ->
            attachGenerationContext testContext fixedTime2 blocked
              `shouldSatisfy` isLeft

    -- assessDuplicateRisk テスト
    describe "assessDuplicateRisk" $ do
      it "records duplicate assessment on Pending proposal" $ do
        let (proposal, _) = mkPendingProposal
        case assessDuplicateRisk testAssessment fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (updated, events) -> do
            let storedAssessment = updated.duplicateAssessment
            case storedAssessment of
              Nothing -> fail "Expected Just DuplicateAssessment"
              Just assessment -> duplicateAssessmentDecision assessment `shouldBe` Allow
            events `shouldBe` []

      it "rejects from non-Pending status" $ do
        let (proposal, _) = mkPendingProposal
        case blockProposal StateConflict testKnowledgeSummary fixedTime2 proposal of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right (blocked, _) ->
            assessDuplicateRisk testAssessment fixedTime2 blocked
              `shouldSatisfy` isLeft
