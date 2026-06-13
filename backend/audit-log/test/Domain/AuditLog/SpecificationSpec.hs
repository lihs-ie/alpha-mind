module Domain.AuditLog.SpecificationSpec (spec) where

import Data.Aeson (Value (..))
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Either (isLeft)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditRecord (
  AuditRecordIdentifier (..),
  SourceEventIdentifier (..),
  SourceEventSnapshot (..),
  acceptSourceEvent,
  markFailed,
  markRecorded,
 )
import Domain.AuditLog.Error (DomainError (..))
import Domain.AuditLog.ReasonCode (ReasonCode (..))
import Domain.AuditLog.Result qualified as Result
import Domain.AuditLog.Specification (
  RawSourceEvent (..),
  isEligibleForPublication,
  validateSourceEventEnvelope,
 )
import Domain.AuditLog.Status qualified as Status
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 1 1) 0

fixedTime2 :: UTCTime
fixedTime2 = UTCTime (fromGregorian 2025 6 15) 0

-- | 全フィールドが揃った正常な RawSourceEvent
validRawSourceEvent :: RawSourceEvent
validRawSourceEvent =
  RawSourceEvent
    { identifier = Just (mkULID 100)
    , eventType = Just "orders.executed"
    , occurredAt = Just fixedTime
    , trace = Just (mkULID 200)
    , payload = Just (Object KeyMap.empty)
    }

spec :: Spec
spec =
  describe "Domain.AuditLog.Specification" $ do
    -- -----------------------------------------------------------------
    -- RULE-AU-001: validateSourceEventEnvelope (Must-7)
    -- -----------------------------------------------------------------
    describe "validateSourceEventEnvelope" $ do
      it "returns Right SourceEventSnapshot when all fields are present" $ do
        let result = validateSourceEventEnvelope validRawSourceEvent
        case result of
          Left message -> fail ("expected Right but got Left: " <> show message)
          Right snapshot -> do
            snapshot.identifier `shouldBe` SourceEventIdentifier (mkULID 100)
            snapshot.eventType `shouldBe` "orders.executed"
            snapshot.occurredAt `shouldBe` fixedTime
            snapshot.trace `shouldBe` Trace (mkULID 200)
            snapshot.payload `shouldBe` Object KeyMap.empty

      it "returns Left MissingRequiredFields when identifier is missing" $ do
        let rawEvent =
              RawSourceEvent
                { identifier = Nothing
                , eventType = Just "orders.executed"
                , occurredAt = Just fixedTime
                , trace = Just (mkULID 200)
                , payload = Just (Object KeyMap.empty)
                }
        validateSourceEventEnvelope rawEvent `shouldSatisfy` isLeft

      it "returns Left MissingRequiredFields when eventType is missing" $ do
        let rawEvent =
              RawSourceEvent
                { identifier = Just (mkULID 100)
                , eventType = Nothing
                , occurredAt = Just fixedTime
                , trace = Just (mkULID 200)
                , payload = Just (Object KeyMap.empty)
                }
        validateSourceEventEnvelope rawEvent `shouldSatisfy` isLeft

      it "returns Left MissingRequiredFields when occurredAt is missing" $ do
        let rawEvent =
              RawSourceEvent
                { identifier = Just (mkULID 100)
                , eventType = Just "orders.executed"
                , occurredAt = Nothing
                , trace = Just (mkULID 200)
                , payload = Just (Object KeyMap.empty)
                }
        validateSourceEventEnvelope rawEvent `shouldSatisfy` isLeft

      it "returns Left MissingRequiredFields when trace is missing" $ do
        let rawEvent =
              RawSourceEvent
                { identifier = Just (mkULID 100)
                , eventType = Just "orders.executed"
                , occurredAt = Just fixedTime
                , trace = Nothing
                , payload = Just (Object KeyMap.empty)
                }
        validateSourceEventEnvelope rawEvent `shouldSatisfy` isLeft

      it "returns Left MissingRequiredFields when payload is missing" $ do
        let rawEvent =
              RawSourceEvent
                { identifier = Just (mkULID 100)
                , eventType = Just "orders.executed"
                , occurredAt = Just fixedTime
                , trace = Just (mkULID 200)
                , payload = Nothing
                }
        validateSourceEventEnvelope rawEvent `shouldSatisfy` isLeft

      it "returns Left MissingRequiredFields when all fields are missing" $ do
        let rawEvent =
              RawSourceEvent
                { identifier = Nothing
                , eventType = Nothing
                , occurredAt = Nothing
                , trace = Nothing
                , payload = Nothing
                }
        case validateSourceEventEnvelope rawEvent of
          Left (MissingRequiredFields fields) -> length fields `shouldBe` 5
          Left message -> fail ("expected MissingRequiredFields but got: " <> show message)
          Right _ -> fail "expected Left but got Right"

      it "does not generate SourceEventSnapshot when multiple fields are missing" $
        let rawEvent =
              RawSourceEvent
                { identifier = Nothing
                , eventType = Nothing
                , occurredAt = Just fixedTime
                , trace = Just (mkULID 200)
                , payload = Just (Object KeyMap.empty)
                }
         in validateSourceEventEnvelope rawEvent `shouldSatisfy` isLeft

    -- -----------------------------------------------------------------
    -- RULE-AU-005 / INV-AU-004: isEligibleForPublication (Must-10)
    -- -----------------------------------------------------------------
    describe "isEligibleForPublication" $ do
      it "returns True for Recorded status" $ do
        let snapshot =
              SourceEventSnapshot
                { identifier = SourceEventIdentifier (mkULID 50)
                , eventType = "orders.executed"
                , occurredAt = fixedTime
                , trace = Trace (mkULID 60)
                , payload = Null
                }
            (pendingRecord, _) =
              acceptSourceEvent
                (AuditRecordIdentifier (mkULID 1))
                snapshot
                "execution"
                Result.Success
        case markRecorded fixedTime2 pendingRecord of
          Left message -> fail ("expected Right but got Left: " <> show message)
          Right (recordedRecord, _) -> do
            recordedRecord.status `shouldBe` Status.Recorded
            isEligibleForPublication recordedRecord `shouldBe` True

      it "returns False for Pending status" $ do
        let snapshot =
              SourceEventSnapshot
                { identifier = SourceEventIdentifier (mkULID 50)
                , eventType = "orders.executed"
                , occurredAt = fixedTime
                , trace = Trace (mkULID 60)
                , payload = Null
                }
            (pendingRecord, _) =
              acceptSourceEvent
                (AuditRecordIdentifier (mkULID 1))
                snapshot
                "execution"
                Result.Success
        pendingRecord.status `shouldBe` Status.Pending
        isEligibleForPublication pendingRecord `shouldBe` False

      it "returns False for Failed status" $ do
        let snapshot =
              SourceEventSnapshot
                { identifier = SourceEventIdentifier (mkULID 50)
                , eventType = "orders.execution.failed"
                , occurredAt = fixedTime
                , trace = Trace (mkULID 60)
                , payload = Null
                }
            (pendingRecord, _) =
              acceptSourceEvent
                (AuditRecordIdentifier (mkULID 1))
                snapshot
                "execution"
                Result.Failed
        case markFailed DataSchemaInvalid pendingRecord of
          Left message -> fail ("expected Right but got Left: " <> show message)
          Right (failedRecord, _) -> do
            failedRecord.status `shouldBe` Status.Failed
            isEligibleForPublication failedRecord `shouldBe` False
