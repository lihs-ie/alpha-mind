module Domain.AuditLog.AuditIngestionSpec (spec) where

import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditIngestion
  ( AuditIngestion (..)
  , AuditIngestionIdentifier (..)
  , DispatchDecision (..)
  , TargetEventType (..)
  )
import Domain.AuditLog.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 1 1) 0

spec :: Spec
spec =
  describe "Domain.AuditLog.AuditIngestion" $ do
    describe "AuditIngestionIdentifier" $ do
      it "constructs and accesses value" $ do
        let identifier = AuditIngestionIdentifier (mkULID 100)
        identifier.value `shouldBe` mkULID 100

      it "supports equality" $ do
        AuditIngestionIdentifier (mkULID 1) `shouldBe` AuditIngestionIdentifier (mkULID 1)
        AuditIngestionIdentifier (mkULID 1) `shouldNotBe` AuditIngestionIdentifier (mkULID 2)

      it "supports ordering" $ do
        compare (AuditIngestionIdentifier (mkULID 1)) (AuditIngestionIdentifier (mkULID 2)) `shouldBe` LT
        compare (AuditIngestionIdentifier (mkULID 2)) (AuditIngestionIdentifier (mkULID 1)) `shouldBe` GT
        compare (AuditIngestionIdentifier (mkULID 1)) (AuditIngestionIdentifier (mkULID 1)) `shouldBe` EQ

      it "supports show" $ do
        show (AuditIngestionIdentifier (mkULID 1)) `shouldSatisfy` (not . null)

    describe "TargetEventType" $ do
      it "constructs AuditRecorded" $ do
        AuditRecorded `shouldBe` AuditRecorded

      it "supports show" $ do
        show AuditRecorded `shouldBe` "AuditRecorded"

      it "supports ordering" $ do
        compare AuditRecorded AuditRecorded `shouldBe` EQ

    describe "DispatchDecision" $ do
      it "constructs with all fields" $ do
        let decision = DispatchDecision
              { shouldPublish = True
              , targetEventType = Just AuditRecorded
              , reasonCode = Just DataSchemaInvalid
              }
        decision.shouldPublish `shouldBe` True
        decision.targetEventType `shouldBe` Just AuditRecorded
        decision.reasonCode `shouldBe` Just DataSchemaInvalid

      it "constructs with Nothing fields" $ do
        let decision = DispatchDecision
              { shouldPublish = False
              , targetEventType = Nothing
              , reasonCode = Nothing
              }
        decision.shouldPublish `shouldBe` False
        decision.targetEventType `shouldBe` Nothing
        decision.reasonCode `shouldBe` Nothing

      it "supports equality" $ do
        let decision1 = DispatchDecision True (Just AuditRecorded) Nothing
        let decision2 = DispatchDecision True (Just AuditRecorded) Nothing
        let decision3 = DispatchDecision False Nothing Nothing
        decision1 `shouldBe` decision2
        decision1 `shouldNotBe` decision3

      it "supports show" $ do
        show (DispatchDecision True Nothing Nothing) `shouldSatisfy` (not . null)

    describe "AuditIngestion" $ do
      it "constructs with all fields populated" $ do
        let decision = DispatchDecision True (Just AuditRecorded) (Just AuditWriteFailed)
        let ingestion = AuditIngestion
              { identifier = AuditIngestionIdentifier (mkULID 10)
              , processed = True
              , processedAt = Just fixedTime
              , trace = Trace (mkULID 20)
              , reasonCode = Just DataSchemaInvalid
              , dispatchDecision = Just decision
              }
        ingestion.identifier `shouldBe` AuditIngestionIdentifier (mkULID 10)
        ingestion.processed `shouldBe` True
        ingestion.processedAt `shouldBe` Just fixedTime
        ingestion.trace `shouldBe` Trace (mkULID 20)
        ingestion.reasonCode `shouldBe` Just DataSchemaInvalid
        ingestion.dispatchDecision `shouldBe` Just decision

      it "constructs with Nothing fields" $ do
        let ingestion = AuditIngestion
              { identifier = AuditIngestionIdentifier (mkULID 10)
              , processed = False
              , processedAt = Nothing
              , trace = Trace (mkULID 20)
              , reasonCode = Nothing
              , dispatchDecision = Nothing
              }
        ingestion.processed `shouldBe` False
        ingestion.processedAt `shouldBe` Nothing
        ingestion.reasonCode `shouldBe` Nothing
        ingestion.dispatchDecision `shouldBe` Nothing

      it "supports equality" $ do
        let ingestion1 = AuditIngestion
              { identifier = AuditIngestionIdentifier (mkULID 10)
              , processed = False
              , processedAt = Nothing
              , trace = Trace (mkULID 20)
              , reasonCode = Nothing
              , dispatchDecision = Nothing
              }
        let ingestion2 = ingestion1
        let ingestion3 = ingestion1 {processed = True}
        ingestion1 `shouldBe` ingestion2
        ingestion1 `shouldNotBe` ingestion3

      it "supports show" $ do
        let ingestion = AuditIngestion
              { identifier = AuditIngestionIdentifier (mkULID 10)
              , processed = False
              , processedAt = Nothing
              , trace = Trace (mkULID 20)
              , reasonCode = Nothing
              , dispatchDecision = Nothing
              }
        show ingestion `shouldSatisfy` (not . null)
