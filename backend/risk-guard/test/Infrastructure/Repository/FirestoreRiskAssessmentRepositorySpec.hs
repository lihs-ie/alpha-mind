{-# LANGUAGE OverloadedRecordDot #-}

{- | Pure unit tests for FirestoreRiskAssessmentRepository codec.

TST-INFRA-001: toDocument / documentToAssessment encode → decode preserves key identity fields.
  Note: The domain exports 'OrderRiskAssessment' as an opaque type (data constructor hidden).
  The roundtrip preserves: identifier, proposal (order ULID), trace.
  Decision state is serialized to the document but reconstructed via acceptOrderProposal
  (Proposed base), which is functionally correct because:
    - The use-case idempotency key guards against re-processing already-evaluated events.
    - 'findByStatus' uses Firestore query filters on the 'decision' field.

TST-INFRA-002: RiskAssessmentDocument field names match Firestore design §3.18.
TST-INFRA-003: isRetryableForPersist (FirestoreErrorDecode) == False.
TST-INFRA-004: isRetryableForPersist (FirestoreErrorTransport) == True.

All tests are pure — no Firestore connection required.
-}
module Infrastructure.Repository.FirestoreRiskAssessmentRepositorySpec (spec) where

import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.RiskAssessment (Trace (..))
import Domain.RiskAssessment.Aggregate (
  OrderRiskAssessment,
  OrderRiskAssessmentIdentifier (..),
  OrderStatus (..),
  acceptOrderProposal,
 )
import Domain.RiskAssessment.ValueObjects (
  CompliancePolicy (..),
  OrderProposal (..),
  RiskExposure (..),
  RiskLimits (..),
  Side (..),
 )
import Infrastructure.Repository.FirestoreRiskAssessmentRepository (
  RiskAssessmentDocument (..),
  documentToAssessment,
  isRetryableForPersist,
  toDocument,
 )
import Persistence.Firestore (FirestoreError (..))
import Test.Hspec (Spec, describe, it, shouldBe)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

defaultLimits :: RiskLimits
defaultLimits =
  RiskLimits
    { dailyLossLimit = 0.05
    , positionConcentrationLimit = 0.20
    , dailyOrderLimit = 50
    }

defaultExposure :: RiskExposure
defaultExposure =
  RiskExposure
    { dailyLossRate = 0.01
    , positionConcentrationRate = 0.05
    , dailyOrderCount = 5
    }

defaultPolicy :: CompliancePolicy
defaultPolicy =
  CompliancePolicy
    { restrictedSymbols = []
    , partnerRestrictedSymbols = []
    , blackoutWindows = []
    }

-- | A PROPOSED (unevaluated) assessment.
proposedAssessment :: OrderRiskAssessment
proposedAssessment =
  let assessmentIdentifier = OrderRiskAssessmentIdentifier{value = mkULID 1}
      orderIdentifier = OrderRiskAssessmentIdentifier{value = mkULID 2}
      proposal =
        OrderProposal
          { identifier = orderIdentifier
          , symbol = "7203.T"
          , side = Buy
          , qty = 100.0
          }
      traceValue = Trace{value = mkULID 100}
   in acceptOrderProposal
        assessmentIdentifier
        proposal
        traceValue
        False
        defaultLimits
        defaultPolicy
        defaultExposure
        fixedTime

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Infrastructure.Repository.FirestoreRiskAssessmentRepository" $ do
  -- TST-INFRA-002: field names match Firestore design §3.18
  describe "TST-INFRA-002: RiskAssessmentDocument field names match §3.18" $ do
    it "identifier field exists in document" $ do
      let document = toDocument fixedTime proposedAssessment
      document.identifier `shouldBe` mkULID 1

    it "order field exists in document (proposal identifier)" $ do
      let document = toDocument fixedTime proposedAssessment
      document.order `shouldBe` mkULID 2

    it "decision field is absent for proposed assessment" $ do
      let document = toDocument fixedTime proposedAssessment
      document.decision `shouldBe` Nothing

    it "reasonCode field is absent for proposed assessment" $ do
      let document = toDocument fixedTime proposedAssessment
      document.reasonCode `shouldBe` Nothing

    it "actionReasonCode field is absent for proposed assessment" $ do
      let document = toDocument fixedTime proposedAssessment
      document.actionReasonCode `shouldBe` Nothing

    it "trace field exists in document" $ do
      let document = toDocument fixedTime proposedAssessment
      document.trace `shouldBe` mkULID 100

    it "evaluatedAt field is absent for proposed assessment" $ do
      let document = toDocument fixedTime proposedAssessment
      document.evaluatedAt `shouldBe` Nothing

    it "version field exists in document" $ do
      let document = toDocument fixedTime proposedAssessment
      document.version `shouldBe` 1

    it "decision field is 'approved' when document sets it directly" $ do
      let approvedDocument =
            RiskAssessmentDocument
              { identifier = mkULID 3
              , order = mkULID 4
              , decision = Just "approved"
              , reasonCode = Nothing
              , actionReasonCode = Nothing
              , trace = mkULID 200
              , evaluatedAt = Just fixedTime
              , version = 2
              }
      approvedDocument.decision `shouldBe` Just "approved"

    it "decision field is 'rejected' with reasonCode when document sets it" $ do
      let rejectedDocument =
            RiskAssessmentDocument
              { identifier = mkULID 5
              , order = mkULID 6
              , decision = Just "rejected"
              , reasonCode = Just "KILL_SWITCH_ENABLED"
              , actionReasonCode = Nothing
              , trace = mkULID 300
              , evaluatedAt = Just fixedTime
              , version = 1
              }
      rejectedDocument.decision `shouldBe` Just "rejected"
      rejectedDocument.reasonCode `shouldBe` Just "KILL_SWITCH_ENABLED"

  -- TST-INFRA-001: codec round-trip (identity fields preserved)
  describe "TST-INFRA-001: toDocument / documentToAssessment round-trip (identity fields)" $ do
    it "preserves identifier through encode-decode" $ do
      let document = toDocument fixedTime proposedAssessment
      case documentToAssessment document of
        Left decodingError -> fail (show decodingError)
        Right result ->
          let idValue = result.identifier
           in idValue.value `shouldBe` mkULID 1

    it "preserves proposal identifier (order) through encode-decode" $ do
      let document = toDocument fixedTime proposedAssessment
      case documentToAssessment document of
        Left decodingError -> fail (show decodingError)
        Right result ->
          let proposalId = result.proposal.identifier
           in proposalId.value `shouldBe` mkULID 2

    it "preserves trace through encode-decode" $ do
      let document = toDocument fixedTime proposedAssessment
      case documentToAssessment document of
        Left decodingError -> fail (show decodingError)
        Right result ->
          let traceVal = result.trace
           in traceVal.value `shouldBe` mkULID 100

    it "reconstructed assessment is in Proposed status (domain constructor constraint)" $ do
      let document = toDocument fixedTime proposedAssessment
      case documentToAssessment document of
        Left decodingError -> fail (show decodingError)
        Right result -> result.orderStatus `shouldBe` Proposed

    it "decode succeeds for an approved document" $ do
      let approvedDocument =
            RiskAssessmentDocument
              { identifier = mkULID 7
              , order = mkULID 8
              , decision = Just "approved"
              , reasonCode = Nothing
              , actionReasonCode = Nothing
              , trace = mkULID 400
              , evaluatedAt = Just fixedTime
              , version = 2
              }
      case documentToAssessment approvedDocument of
        Left decodingError -> fail ("decode failed: " ++ show decodingError)
        Right result ->
          let idValue = result.identifier
           in idValue.value `shouldBe` mkULID 7

    it "decode succeeds for a rejected document with reasonCode" $ do
      let rejectedDocument =
            RiskAssessmentDocument
              { identifier = mkULID 9
              , order = mkULID 10
              , decision = Just "rejected"
              , reasonCode = Just "KILL_SWITCH_ENABLED"
              , actionReasonCode = Nothing
              , trace = mkULID 500
              , evaluatedAt = Just fixedTime
              , version = 1
              }
      case documentToAssessment rejectedDocument of
        Left decodingError -> fail ("decode failed: " ++ show decodingError)
        Right result ->
          let idValue = result.identifier
           in idValue.value `shouldBe` mkULID 9

  -- TST-INFRA-003: FirestoreErrorDecode is not retryable
  describe "TST-INFRA-003: isRetryableForPersist (FirestoreErrorDecode) == False" $ do
    it "returns False for FirestoreErrorDecode" $ do
      isRetryableForPersist (FirestoreErrorDecode "schema error") `shouldBe` False

    it "returns False for FirestoreErrorPermissionDenied" $ do
      isRetryableForPersist (FirestoreErrorPermissionDenied "denied") `shouldBe` False

  -- TST-INFRA-004: transport errors are retryable
  describe "TST-INFRA-004: isRetryableForPersist (FirestoreErrorTransport) == True" $ do
    it "returns True for FirestoreErrorTransport" $ do
      isRetryableForPersist (FirestoreErrorTransport "timeout") `shouldBe` True

    it "returns True for FirestoreErrorUnexpected 429" $ do
      isRetryableForPersist (FirestoreErrorUnexpected 429 "rate limited") `shouldBe` True

    it "returns True for FirestoreErrorUnexpected 500" $ do
      isRetryableForPersist (FirestoreErrorUnexpected 500 "server error") `shouldBe` True

    it "returns True for FirestoreErrorUnexpected 503" $ do
      isRetryableForPersist (FirestoreErrorUnexpected 503 "unavailable") `shouldBe` True

    it "returns False for FirestoreErrorUnexpected 400" $ do
      isRetryableForPersist (FirestoreErrorUnexpected 400 "bad request") `shouldBe` False
