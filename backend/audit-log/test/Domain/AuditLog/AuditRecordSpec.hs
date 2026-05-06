module Domain.AuditLog.AuditRecordSpec (spec) where

import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Either (isLeft)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditRecord (
  AuditRecord (..),
  AuditRecordEvent (..),
  AuditRecordIdentifier (..),
  PayloadDigest (..),
  PayloadSummaryValue (..),
  ResultNormalization (..),
  SourceEventIdentifier (..),
  SourceEventSnapshot (..),
  acceptSourceEvent,
  extractReasonFromPayload,
  markFailed,
  markRecorded,
  normalizeReason,
  normalizeResult,
  normalizeResultFromEventType,
  summarizePayload,
 )
import Domain.AuditLog.ReasonCode (ReasonCode (..))
import Domain.AuditLog.ReasonSource (ReasonSource (..))
import Domain.AuditLog.Result qualified as Result
import Domain.AuditLog.Status qualified as Status
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 1 1) 0

fixedTime2 :: UTCTime
fixedTime2 = UTCTime (fromGregorian 2025 6 15) 0

testSnapshot :: SourceEventSnapshot
testSnapshot =
  SourceEventSnapshot
    { identifier = SourceEventIdentifier (mkULID 50)
    , eventType = "orders.executed"
    , occurredAt = fixedTime
    , trace = Trace (mkULID 60)
    , payload = Null
    }

mkPendingRecord :: (AuditRecord, [AuditRecordEvent])
mkPendingRecord =
  acceptSourceEvent
    (AuditRecordIdentifier (mkULID 1))
    testSnapshot
    "execution"
    Result.Success

spec :: Spec
spec =
  describe "Domain.AuditLog.AuditRecord" $ do
    describe "AuditRecordIdentifier" $ do
      it "supports equality" $ do
        AuditRecordIdentifier (mkULID 1) `shouldBe` AuditRecordIdentifier (mkULID 1)
        AuditRecordIdentifier (mkULID 1) `shouldNotBe` AuditRecordIdentifier (mkULID 2)

      it "supports ordering" $ do
        compare (AuditRecordIdentifier (mkULID 1)) (AuditRecordIdentifier (mkULID 2)) `shouldBe` LT

    describe "SourceEventIdentifier" $ do
      it "supports equality" $ do
        SourceEventIdentifier (mkULID 1) `shouldBe` SourceEventIdentifier (mkULID 1)
        SourceEventIdentifier (mkULID 1) `shouldNotBe` SourceEventIdentifier (mkULID 2)

    describe "PayloadSummaryValue" $ do
      it "distinguishes different constructors" $ do
        SummaryString "1" `shouldNotBe` SummaryNumber 1.0
        SummaryBool True `shouldNotBe` SummaryString "True"

    describe "ResultNormalization" $ do
      it "constructs with and without reason" $ do
        let withReason = ResultNormalization Result.Success (Just "approved") FromReason
        withReason.result `shouldBe` Result.Success
        withReason.reason `shouldBe` Just ("approved" :: Text)
        let withoutReason = ResultNormalization Result.Failed Nothing FromNone
        withoutReason.reason `shouldBe` (Nothing :: Maybe Text)

    describe "PayloadDigest" $ do
      it "constructs with all fields" $ do
        let digest = PayloadDigest 3 ["a", "b", "c"] (Map.fromList [("a" :: Text, SummaryNumber 1.0)])
        digest.fieldCount `shouldBe` 3
        Map.lookup ("a" :: Text) digest.summary `shouldBe` Just (SummaryNumber 1.0)

    describe "acceptSourceEvent" $ do
      it "creates a pending record" $ do
        let (record, _) = mkPendingRecord
        record.status `shouldBe` Status.Pending
        record.identifier `shouldBe` AuditRecordIdentifier (mkULID 1)
        record.service `shouldBe` ("execution" :: Text)
        record.result `shouldBe` Result.Success
        record.reason `shouldBe` (Nothing :: Maybe Text)
        record.reasonCode `shouldBe` Nothing
        record.recordedAt `shouldBe` Nothing

      it "emits AuditRecordAccepted event" $ do
        let (_, [event]) = mkPendingRecord
        event
          `shouldBe` AuditRecordAccepted
            { identifier = AuditRecordIdentifier (mkULID 1)
            , eventType = "orders.executed"
            , trace = Trace (mkULID 60)
            }

    describe "normalizeResult" $ do
      it "updates result in pending state" $ do
        let (record, _) = mkPendingRecord
            Right updated = normalizeResult Result.Failed record
        updated.result `shouldBe` Result.Failed
        let ResultNormalization{result = normalizedResult} = updated.resultNormalization
        normalizedResult `shouldBe` Result.Failed

      it "rejects from recorded state" $ do
        let (record, _) = mkPendingRecord
            Right (recorded, _) = markRecorded fixedTime2 record
        normalizeResult Result.Failed recorded `shouldSatisfy` isLeft

    describe "normalizeReason" $ do
      it "updates reason and reasonSource in pending state" $ do
        let (record, _) = mkPendingRecord
            Right updated = normalizeReason (Just "RISK_LIMIT") FromReasonCode record
        updated.reason `shouldBe` Just ("RISK_LIMIT" :: Text)
        let ResultNormalization{reasonSource = src} = updated.resultNormalization
        src `shouldBe` FromReasonCode

      it "rejects from non-pending state" $ do
        let (record, _) = mkPendingRecord
            Right (failed, _) = markFailed DataSchemaInvalid record
        normalizeReason (Just "x") FromReason failed `shouldSatisfy` isLeft

    describe "summarizePayload" $ do
      it "sets payloadDigest and payloadSummary" $ do
        let (record, _) = mkPendingRecord
            digest = PayloadDigest 2 ["k1", "k2"] (Map.fromList [("k1" :: Text, SummaryBool True)])
            Right updated = summarizePayload digest record
        updated.payloadDigest `shouldBe` Just digest
        updated.payloadSummary `shouldBe` Just (Map.fromList [("k1" :: Text, SummaryBool True)])

    describe "markRecorded" $ do
      it "transitions to recorded state with timestamp" $ do
        let (record, _) = mkPendingRecord
            Right (recorded, events) = markRecorded fixedTime2 record
        recorded.status `shouldBe` Status.Recorded
        recorded.recordedAt `shouldBe` Just fixedTime2
        length events `shouldBe` 1

      it "emits AuditRecordPersisted event" $ do
        let (record, _) = mkPendingRecord
            Right (_, [event]) = markRecorded fixedTime2 record
        event
          `shouldBe` AuditRecordPersisted
            { identifier = AuditRecordIdentifier (mkULID 1)
            , eventType = "orders.executed"
            , service = "execution"
            , result = Result.Success
            , trace = Trace (mkULID 60)
            }

      it "rejects from recorded state" $ do
        let (record, _) = mkPendingRecord
            Right (recorded, _) = markRecorded fixedTime2 record
        markRecorded fixedTime2 recorded `shouldSatisfy` isLeft

    describe "markFailed" $ do
      it "transitions to failed state with reasonCode" $ do
        let (record, _) = mkPendingRecord
            Right (failed, events) = markFailed DataSchemaInvalid record
        failed.status `shouldBe` Status.Failed
        failed.reasonCode `shouldBe` Just DataSchemaInvalid
        length events `shouldBe` 1

      it "emits AuditRecordPersistenceFailed event" $ do
        let (record, _) = mkPendingRecord
            Right (_, [event]) = markFailed AuditWriteFailed record
        event
          `shouldBe` AuditRecordPersistenceFailed
            { identifier = AuditRecordIdentifier (mkULID 1)
            , reasonCode = AuditWriteFailed
            , trace = Trace (mkULID 60)
            }

      it "rejects from failed state" $ do
        let (record, _) = mkPendingRecord
            Right (failed, _) = markFailed DataSchemaInvalid record
        markFailed AuditWriteFailed failed `shouldSatisfy` isLeft

    describe "normalizeResultFromEventType" $ do
      it "returns Failed for *.failed event types" $ do
        normalizeResultFromEventType "orders.execution.failed" `shouldBe` Result.Failed
        normalizeResultFromEventType "market.collect.failed" `shouldBe` Result.Failed

      it "returns Success for non-failed event types" $ do
        normalizeResultFromEventType "orders.executed" `shouldBe` Result.Success
        normalizeResultFromEventType "market.collected" `shouldBe` Result.Success

    describe "extractReasonFromPayload" $ do
      it "extracts reasonCode with highest priority" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [ (Key.fromText "reasonCode", String "RISK_LIMIT")
                  , (Key.fromText "actionReasonCode", String "MANUAL")
                  , (Key.fromText "reason", String "fallback")
                  ]
        extractReasonFromPayload payload `shouldBe` (Just ("RISK_LIMIT" :: Text), FromReasonCode)

      it "falls back to actionReasonCode" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [(Key.fromText "actionReasonCode", String "MANUAL")]
        extractReasonFromPayload payload `shouldBe` (Just ("MANUAL" :: Text), FromActionReasonCode)

      it "falls back to reason" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [(Key.fromText "reason", String "user request")]
        extractReasonFromPayload payload `shouldBe` (Just ("user request" :: Text), FromReason)

      it "returns Nothing when no reason fields" $ do
        extractReasonFromPayload (Object KeyMap.empty) `shouldBe` (Nothing :: Maybe Text, FromNone)
        extractReasonFromPayload Null `shouldBe` (Nothing :: Maybe Text, FromNone)

    describe "AuditRecordEvent" $ do
      it "distinguishes different event types" $ do
        let accepted = AuditRecordAccepted (AuditRecordIdentifier (mkULID 1)) "e" (Trace (mkULID 2))
        let persisted = AuditRecordPersisted (AuditRecordIdentifier (mkULID 1)) "e" "s" Result.Success (Trace (mkULID 2))
        let failed = AuditRecordPersistenceFailed (AuditRecordIdentifier (mkULID 1)) DataSchemaInvalid (Trace (mkULID 2))
        accepted `shouldNotBe` persisted
        persisted `shouldNotBe` failed
