module Domain.AuditLog.AuditIngestionSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditIngestion (
  AuditIngestion (..),
  AuditIngestionIdentifier (..),
  DispatchDecision (..),
  TargetEventType (..),
  checkIdempotency,
  decideDispatch,
  isDuplicate,
  markFailed,
  markProcessed,
  startIngestion,
 )
import Domain.AuditLog.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 1 1) 0

mkNewIngestion :: Domain.AuditLog.AuditIngestion.AuditIngestion
mkNewIngestion =
  startIngestion
    (AuditIngestionIdentifier (mkULID 10))
    (Trace (mkULID 20))

spec :: Spec
spec =
  describe "Domain.AuditLog.AuditIngestion" $ do
    describe "AuditIngestionIdentifier" $ do
      it "supports equality and ordering" $ do
        AuditIngestionIdentifier (mkULID 1) `shouldBe` AuditIngestionIdentifier (mkULID 1)
        compare (AuditIngestionIdentifier (mkULID 1)) (AuditIngestionIdentifier (mkULID 2)) `shouldBe` LT

    describe "DispatchDecision" $ do
      it "constructs with all fields" $ do
        let decision = DispatchDecision True (Just AuditRecorded) Nothing
        decision.shouldPublish `shouldBe` True
        decision.targetEventType `shouldBe` Just AuditRecorded

    describe "startIngestion" $ do
      it "creates a new unprocessed ingestion" $ do
        let ingestion = mkNewIngestion
        ingestion.processed `shouldBe` False
        ingestion.processedAt `shouldBe` Nothing
        ingestion.reasonCode `shouldBe` Nothing
        ingestion.dispatchDecision `shouldBe` Nothing

    describe "checkIdempotency" $ do
      it "passes for new ingestion" $ do
        checkIdempotency mkNewIngestion `shouldSatisfy` isRight

      it "fails for processed ingestion" $ do
        let Right processed = markProcessed fixedTime mkNewIngestion
        checkIdempotency processed `shouldSatisfy` isLeft

      it "fails for failed ingestion" $ do
        let Right failed = markFailed DataSchemaInvalid mkNewIngestion
        checkIdempotency failed `shouldSatisfy` isLeft

    describe "markProcessed" $ do
      it "transitions to processed state" $ do
        let Right processed = markProcessed fixedTime mkNewIngestion
        processed.processed `shouldBe` True
        processed.processedAt `shouldBe` Just fixedTime

      it "rejects already processed ingestion" $ do
        let Right processed = markProcessed fixedTime mkNewIngestion
        markProcessed fixedTime processed `shouldSatisfy` isLeft

      it "rejects failed ingestion" $ do
        let Right failed = markFailed DataSchemaInvalid mkNewIngestion
        markProcessed fixedTime failed `shouldSatisfy` isLeft

    describe "markFailed" $ do
      it "sets reasonCode on new ingestion" $ do
        let Right failed = markFailed DataSchemaInvalid mkNewIngestion
        failed.reasonCode `shouldBe` Just DataSchemaInvalid

      it "rejects processed ingestion" $ do
        let Right processed = markProcessed fixedTime mkNewIngestion
        markFailed DataSchemaInvalid processed `shouldSatisfy` isLeft

      it "rejects already failed ingestion" $ do
        let Right failed = markFailed DataSchemaInvalid mkNewIngestion
        markFailed AuditWriteFailed failed `shouldSatisfy` isLeft

    describe "decideDispatch" $ do
      it "sets dispatch decision after processing" $ do
        let Right processed = markProcessed fixedTime mkNewIngestion
            decision = DispatchDecision True (Just AuditRecorded) Nothing
            Right dispatched = decideDispatch decision processed
        dispatched.dispatchDecision `shouldBe` Just decision

      it "rejects from new state" $ do
        let decision = DispatchDecision False Nothing Nothing
        decideDispatch decision mkNewIngestion `shouldSatisfy` isLeft

    describe "isDuplicate" $ do
      it "returns False for new ingestion" $ do
        isDuplicate mkNewIngestion `shouldBe` False

      it "returns True for processed ingestion" $ do
        let Right processed = markProcessed fixedTime mkNewIngestion
        isDuplicate processed `shouldBe` True

      it "returns True for failed ingestion" $ do
        let Right failed = markFailed DataSchemaInvalid mkNewIngestion
        isDuplicate failed `shouldBe` True
