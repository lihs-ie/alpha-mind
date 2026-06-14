module UseCase.ProposalAuditWriterSpec (spec) where

import Control.Monad.State.Strict (State, execState, modify, runState)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.ProposalDispatch (ProposalDispatchIdentifier (..))
import Domain.OrderProposal.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe)
import UseCase.ProposalAuditWriter (
  ProposalAuditPort (..),
  ProposalAuditRecord (..),
  ProposalAuditResult (..),
  recordProposalAudit,
 )

-- ---------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

testTrace :: Trace
testTrace = Trace (mkULID 100)

testDispatchIdentifier :: ProposalDispatchIdentifier
testDispatchIdentifier = ProposalDispatchIdentifier (mkULID 1)

successAuditRecord :: ProposalAuditRecord
successAuditRecord =
  ProposalAuditRecord
    { identifier = testDispatchIdentifier
    , result = AuditSucceeded
    , reasonCode = Nothing
    , trace = testTrace
    , processedAt = fixedTime
    }

failureAuditRecord :: ProposalAuditRecord
failureAuditRecord =
  ProposalAuditRecord
    { identifier = testDispatchIdentifier
    , result = AuditFailed
    , reasonCode = Just ComplianceReviewRequired
    , trace = testTrace
    , processedAt = fixedTime
    }

-- ---------------------------------------------------------------------
-- Test monad: State-based audit capture
-- ---------------------------------------------------------------------

newtype TestAuditState = TestAuditState
  { capturedAuditRecords :: [ProposalAuditRecord]
  }

emptyTestAuditState :: TestAuditState
emptyTestAuditState = TestAuditState{capturedAuditRecords = []}

newtype TestAuditMonad a = TestAuditMonad {runTestAuditMonad :: State TestAuditState a}
  deriving newtype (Functor, Applicative, Monad)

instance ProposalAuditPort TestAuditMonad where
  writeProposalAudit auditRecord =
    TestAuditMonad $
      modify
        ( \s ->
            s{capturedAuditRecords = capturedAuditRecords s ++ [auditRecord]}
        )

runAuditTest :: TestAuditMonad a -> TestAuditState -> (a, TestAuditState)
runAuditTest action = runState (runTestAuditMonad action)

execAuditTest :: TestAuditMonad a -> TestAuditState -> TestAuditState
execAuditTest action = execState (runTestAuditMonad action)

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.ProposalAuditWriter" $ do
    -- MUST-12: Orchestration only, no business logic
    describe "recordProposalAudit — success case (MUST-14)" $ do
      it "writes exactly one audit record for a success result" $ do
        let finalState = execAuditTest (recordProposalAudit successAuditRecord) emptyTestAuditState
        length finalState.capturedAuditRecords `shouldBe` 1

      it "written audit record contains the input identifier (MUST-14)" $ do
        let finalState = execAuditTest (recordProposalAudit successAuditRecord) emptyTestAuditState
        case finalState.capturedAuditRecords of
          [record] -> record.identifier `shouldBe` testDispatchIdentifier
          other -> error ("Expected 1 record, got " ++ show (length other))

      it "written audit record contains the input trace (MUST-14)" $ do
        let finalState = execAuditTest (recordProposalAudit successAuditRecord) emptyTestAuditState
        case finalState.capturedAuditRecords of
          [record] -> record.trace `shouldBe` testTrace
          other -> error ("Expected 1 record, got " ++ show (length other))

      it "written audit record contains result = AuditSucceeded (MUST-14)" $ do
        let finalState = execAuditTest (recordProposalAudit successAuditRecord) emptyTestAuditState
        case finalState.capturedAuditRecords of
          [record] -> record.result `shouldBe` AuditSucceeded
          other -> error ("Expected 1 record, got " ++ show (length other))

      it "success record has reasonCode = Nothing (MUST-14)" $ do
        let finalState = execAuditTest (recordProposalAudit successAuditRecord) emptyTestAuditState
        case finalState.capturedAuditRecords of
          [record] -> record.reasonCode `shouldBe` Nothing
          other -> error ("Expected 1 record, got " ++ show (length other))

    -- MUST-14: Failure case contains reasonCode
    describe "recordProposalAudit — failure case (MUST-14)" $ do
      it "writes exactly one audit record for a failure result" $ do
        let finalState = execAuditTest (recordProposalAudit failureAuditRecord) emptyTestAuditState
        length finalState.capturedAuditRecords `shouldBe` 1

      it "failure record contains result = AuditFailed (MUST-14)" $ do
        let finalState = execAuditTest (recordProposalAudit failureAuditRecord) emptyTestAuditState
        case finalState.capturedAuditRecords of
          [record] -> record.result `shouldBe` AuditFailed
          other -> error ("Expected 1 record, got " ++ show (length other))

      it "failure record contains reasonCode (MUST-14)" $ do
        let finalState = execAuditTest (recordProposalAudit failureAuditRecord) emptyTestAuditState
        case finalState.capturedAuditRecords of
          [record] -> record.reasonCode `shouldBe` Just ComplianceReviewRequired
          other -> error ("Expected 1 record, got " ++ show (length other))

      it "failure record contains trace (MUST-14)" $ do
        let finalState = execAuditTest (recordProposalAudit failureAuditRecord) emptyTestAuditState
        case finalState.capturedAuditRecords of
          [record] -> record.trace `shouldBe` testTrace
          other -> error ("Expected 1 record, got " ++ show (length other))

      it "failure record contains identifier (MUST-14)" $ do
        let finalState = execAuditTest (recordProposalAudit failureAuditRecord) emptyTestAuditState
        case finalState.capturedAuditRecords of
          [record] -> record.identifier `shouldBe` testDispatchIdentifier
          other -> error ("Expected 1 record, got " ++ show (length other))

    -- MUST-13: Audit is called after state confirmation (ordering test via call sequence)
    describe "recordProposalAudit — ordering (MUST-13)" $ do
      it "audit record is written when called (simulating post-state-confirmation)" $ do
        -- The ordering guarantee is enforced by the caller (PortfolioPlanningService),
        -- which only calls recordProposalAudit after all persist calls succeed.
        -- Here we verify that recordProposalAudit itself is a simple write (no pre-conditions).
        let (_, finalState) = runAuditTest (recordProposalAudit successAuditRecord) emptyTestAuditState
        length finalState.capturedAuditRecords `shouldBe` 1
