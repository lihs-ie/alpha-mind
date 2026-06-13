module Domain.AuditLog.AuditRecordFactorySpec (spec) where

import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Either (isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditRecord (
  AuditRecordIdentifier (..),
  ResultNormalization (..),
  SourceEventIdentifier (..),
  SourceEventSnapshot (..),
 )
import Domain.AuditLog.AuditRecordFactory (fromSourceEvent)
import Domain.AuditLog.ReasonSource (ReasonSource (..))
import Domain.AuditLog.Result qualified as Result
import Domain.AuditLog.Status qualified as Status
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 1 1) 0

mkSnapshot :: Value -> SourceEventSnapshot
mkSnapshot payload =
  SourceEventSnapshot
    { identifier = SourceEventIdentifier (mkULID 50)
    , eventType = "orders.executed"
    , occurredAt = fixedTime
    , trace = Trace (mkULID 60)
    , payload = payload
    }

mkFailedSnapshot :: Value -> SourceEventSnapshot
mkFailedSnapshot payload =
  SourceEventSnapshot
    { identifier = SourceEventIdentifier (mkULID 50)
    , eventType = "orders.execution.failed"
    , occurredAt = fixedTime
    , trace = Trace (mkULID 60)
    , payload = payload
    }

spec :: Spec
spec =
  describe "Domain.AuditLog.AuditRecordFactory" $ do
    describe "fromSourceEvent" $ do
      it "returns Right (AuditRecord, events) for a valid success event" $ do
        let snapshot = mkSnapshot (Object KeyMap.empty)
            result = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "execution"
        result `shouldSatisfy` isRight

      it "sets result to Success for non-failed eventType" $ do
        let snapshot = mkSnapshot (Object KeyMap.empty)
            Right (record, _) = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "execution"
        record.result `shouldBe` Result.Success

      it "sets result to Failed for *.failed eventType" $ do
        let snapshot = mkFailedSnapshot (Object KeyMap.empty)
            Right (record, _) = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "execution"
        record.result `shouldBe` Result.Failed

      it "creates record in Pending status" $ do
        let snapshot = mkSnapshot (Object KeyMap.empty)
            Right (record, _) = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "execution"
        record.status `shouldBe` Status.Pending

      it "sets identifier correctly" $ do
        let snapshot = mkSnapshot (Object KeyMap.empty)
            Right (record, _) = fromSourceEvent (AuditRecordIdentifier (mkULID 99)) snapshot "execution"
        record.identifier `shouldBe` AuditRecordIdentifier (mkULID 99)

      it "sets service correctly" $ do
        let snapshot = mkSnapshot (Object KeyMap.empty)
            Right (record, _) = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "risk-guard"
        record.service `shouldBe` "risk-guard"

      -- reason 優先順位: reasonCode > actionReasonCode > reason > none
      it "extracts reason from reasonCode with highest priority" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [ (Key.fromText "reasonCode", String "RISK_LIMIT")
                  , (Key.fromText "actionReasonCode", String "MANUAL")
                  , (Key.fromText "reason", String "fallback")
                  ]
            snapshot = mkSnapshot payload
            Right (record, _) = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "execution"
            ResultNormalization{reasonSource = resolvedReasonSource} = record.resultNormalization
        record.reason `shouldBe` Just "RISK_LIMIT"
        resolvedReasonSource `shouldBe` FromReasonCode

      it "falls back to actionReasonCode when reasonCode is absent" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [ (Key.fromText "actionReasonCode", String "MANUAL")
                  , (Key.fromText "reason", String "fallback")
                  ]
            snapshot = mkSnapshot payload
            Right (record, _) = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "execution"
            ResultNormalization{reasonSource = resolvedReasonSource} = record.resultNormalization
        record.reason `shouldBe` Just "MANUAL"
        resolvedReasonSource `shouldBe` FromActionReasonCode

      it "falls back to reason when reasonCode and actionReasonCode are absent" $ do
        let payload =
              Object $
                KeyMap.fromList
                  [(Key.fromText "reason", String "user request")]
            snapshot = mkSnapshot payload
            Right (record, _) = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "execution"
            ResultNormalization{reasonSource = resolvedReasonSource} = record.resultNormalization
        record.reason `shouldBe` Just "user request"
        resolvedReasonSource `shouldBe` FromReason

      it "sets reason to Nothing when no reason fields are present" $ do
        let snapshot = mkSnapshot (Object KeyMap.empty)
            Right (record, _) = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "execution"
            ResultNormalization{reasonSource = resolvedReasonSource} = record.resultNormalization
        record.reason `shouldBe` Nothing
        resolvedReasonSource `shouldBe` FromNone

      it "emits AuditRecordAccepted event" $ do
        let snapshot = mkSnapshot (Object KeyMap.empty)
            Right (_, events) = fromSourceEvent (AuditRecordIdentifier (mkULID 1)) snapshot "execution"
        length events `shouldBe` 1
