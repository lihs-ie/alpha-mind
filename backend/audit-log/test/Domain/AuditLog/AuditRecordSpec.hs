module Domain.AuditLog.AuditRecordSpec (spec) where

import Data.Aeson (Value (..))
import Data.Map.Strict qualified as Map
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.AuditLog (Trace (..))
import Domain.AuditLog.AuditRecord
  ( AuditRecord (..)
  , AuditRecordIdentifier (..)
  , DomainEvent (..)
  , PayloadDigest (..)
  , PayloadSummaryValue (..)
  , ResultNormalization (..)
  , SourceEventIdentifier (..)
  , SourceEventSnapshot (..)
  )
import Domain.AuditLog.ReasonCode (ReasonCode (..))
import Domain.AuditLog.ReasonSource (ReasonSource (..))
import Domain.AuditLog.Result (Result (..))
import Domain.AuditLog.Result qualified as Result
import Domain.AuditLog.Status (Status (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 1 1) 0

spec :: Spec
spec =
  describe "Domain.AuditLog.AuditRecord" $ do
    describe "AuditRecordIdentifier" $ do
      it "constructs and accesses value" $ do
        let identifier = AuditRecordIdentifier (mkULID 1)
        identifier.value `shouldBe` mkULID 1

      it "supports equality" $ do
        AuditRecordIdentifier (mkULID 1) `shouldBe` AuditRecordIdentifier (mkULID 1)
        AuditRecordIdentifier (mkULID 1) `shouldNotBe` AuditRecordIdentifier (mkULID 2)

      it "supports ordering" $ do
        compare (AuditRecordIdentifier (mkULID 1)) (AuditRecordIdentifier (mkULID 2)) `shouldBe` LT
        compare (AuditRecordIdentifier (mkULID 2)) (AuditRecordIdentifier (mkULID 1)) `shouldBe` GT
        compare (AuditRecordIdentifier (mkULID 1)) (AuditRecordIdentifier (mkULID 1)) `shouldBe` EQ

      it "supports show" $ do
        show (AuditRecordIdentifier (mkULID 1)) `shouldSatisfy` (not . null)

    describe "SourceEventIdentifier" $ do
      it "constructs and accesses value" $ do
        let identifier = SourceEventIdentifier (mkULID 1)
        identifier.value `shouldBe` mkULID 1

      it "supports equality" $ do
        SourceEventIdentifier (mkULID 1) `shouldBe` SourceEventIdentifier (mkULID 1)
        SourceEventIdentifier (mkULID 1) `shouldNotBe` SourceEventIdentifier (mkULID 2)

      it "supports ordering" $ do
        compare (SourceEventIdentifier (mkULID 1)) (SourceEventIdentifier (mkULID 2)) `shouldBe` LT

      it "supports show" $ do
        show (SourceEventIdentifier (mkULID 1)) `shouldSatisfy` (not . null)

    describe "PayloadSummaryValue" $ do
      it "constructs SummaryString" $ do
        let value = SummaryString "test"
        value `shouldBe` SummaryString "test"

      it "constructs SummaryNumber" $ do
        let value = SummaryNumber 42.0
        value `shouldBe` SummaryNumber 42.0

      it "constructs SummaryBool" $ do
        let value = SummaryBool True
        value `shouldBe` SummaryBool True

      it "distinguishes different constructors" $ do
        SummaryString "1" `shouldNotBe` SummaryNumber 1.0
        SummaryBool True `shouldNotBe` SummaryString "True"
        SummaryNumber 0.0 `shouldNotBe` SummaryBool False

      it "supports show for all variants" $ do
        show (SummaryString "x") `shouldSatisfy` (not . null)
        show (SummaryNumber 1.0) `shouldSatisfy` (not . null)
        show (SummaryBool True) `shouldSatisfy` (not . null)

    describe "SourceEventSnapshot" $ do
      let snapshot = SourceEventSnapshot
            { identifier = SourceEventIdentifier (mkULID 1)
            , eventType = "order.created"
            , occurredAt = fixedTime
            , trace = Trace (mkULID 2)
            , payload = Null
            }

      it "constructs with all fields" $ do
        snapshot.identifier `shouldBe` SourceEventIdentifier (mkULID 1)
        snapshot.eventType `shouldBe` "order.created"
        snapshot.occurredAt `shouldBe` fixedTime
        snapshot.trace `shouldBe` Trace (mkULID 2)
        snapshot.payload `shouldBe` Null

      it "supports equality" $ do
        let snapshot2 = SourceEventSnapshot
              { identifier = SourceEventIdentifier (mkULID 1)
              , eventType = "order.created"
              , occurredAt = fixedTime
              , trace = Trace (mkULID 2)
              , payload = Null
              }
        let differentSnapshot = SourceEventSnapshot
              { identifier = SourceEventIdentifier (mkULID 1)
              , eventType = "order.updated"
              , occurredAt = fixedTime
              , trace = Trace (mkULID 2)
              , payload = Null
              }
        snapshot `shouldBe` snapshot2
        snapshot `shouldNotBe` differentSnapshot

      it "supports show" $ do
        show snapshot `shouldSatisfy` (not . null)

    describe "ResultNormalization" $ do
      it "constructs with reason" $ do
        let normalization = ResultNormalization
              { result = Success
              , reason = Just "approved"
              , reasonSource = FromReason
              }
        normalization.result `shouldBe` Success
        normalization.reason `shouldBe` Just "approved"
        normalization.reasonSource `shouldBe` FromReason

      it "constructs without reason" $ do
        let normalization = ResultNormalization
              { result = Result.Failed
              , reason = Nothing
              , reasonSource = FromNone
              }
        normalization.reason `shouldBe` Nothing

      it "supports equality" $ do
        let n1 = ResultNormalization Success Nothing FromNone
        let n2 = ResultNormalization Success Nothing FromNone
        let n3 = ResultNormalization Result.Failed Nothing FromNone
        n1 `shouldBe` n2
        n1 `shouldNotBe` n3

      it "supports show" $ do
        show (ResultNormalization Success Nothing FromNone) `shouldSatisfy` (not . null)

    describe "PayloadDigest" $ do
      it "constructs with all fields" $ do
        let digest = PayloadDigest
              { fieldCount = 3
              , topLevelKeys = ["id", "type", "data"]
              , summary = Map.fromList [("id", SummaryString "abc")]
              }
        digest.fieldCount `shouldBe` 3
        digest.topLevelKeys `shouldBe` ["id", "type", "data"]
        Map.lookup "id" digest.summary `shouldBe` Just (SummaryString "abc")

      it "supports equality" $ do
        let d1 = PayloadDigest 1 ["k"] Map.empty
        let d2 = PayloadDigest 1 ["k"] Map.empty
        let d3 = PayloadDigest 2 ["k"] Map.empty
        d1 `shouldBe` d2
        d1 `shouldNotBe` d3

      it "supports show" $ do
        show (PayloadDigest 0 [] Map.empty) `shouldSatisfy` (not . null)

    describe "AuditRecord" $ do
      let snapshot = SourceEventSnapshot
            { identifier = SourceEventIdentifier (mkULID 50)
            , eventType = "order.created"
            , occurredAt = fixedTime
            , trace = Trace (mkULID 60)
            , payload = Null
            }
      let normalization = ResultNormalization Success Nothing FromNone
      let record = AuditRecord
            { identifier = AuditRecordIdentifier (mkULID 1)
            , eventType = "order.created"
            , service = "execution"
            , result = Success
            , trace = Trace (mkULID 10)
            , occurredAt = fixedTime
            , reason = Nothing
            , payloadSummary = Nothing
            , status = Pending
            , reasonCode = Nothing
            , recordedAt = Nothing
            , sourceEventSnapshot = snapshot
            , resultNormalization = normalization
            , payloadDigest = Nothing
            }

      it "constructs with minimal optional fields" $ do
        record.identifier `shouldBe` AuditRecordIdentifier (mkULID 1)
        record.eventType `shouldBe` "order.created"
        record.service `shouldBe` "execution"
        record.result `shouldBe` Success
        record.status `shouldBe` Pending
        record.reason `shouldBe` Nothing
        record.payloadSummary `shouldBe` Nothing
        record.reasonCode `shouldBe` Nothing
        record.recordedAt `shouldBe` Nothing
        record.payloadDigest `shouldBe` Nothing

      it "constructs with all optional fields populated" $ do
        let digest = PayloadDigest 1 ["key"] (Map.fromList [("key", SummaryNumber 1.0)])
        let fullRecord = record
              { reason = Just "manual override"
              , payloadSummary = Just (Map.fromList [("count", SummaryNumber 5.0)])
              , status = Recorded
              , reasonCode = Just AuditWriteFailed
              , recordedAt = Just fixedTime
              , payloadDigest = Just digest
              }
        fullRecord.reason `shouldBe` Just "manual override"
        fullRecord.payloadSummary `shouldSatisfy` (/= Nothing)
        fullRecord.status `shouldBe` Recorded
        fullRecord.reasonCode `shouldBe` Just AuditWriteFailed
        fullRecord.recordedAt `shouldBe` Just fixedTime
        fullRecord.payloadDigest `shouldBe` Just digest

      it "supports equality" $ do
        record `shouldBe` record
        record `shouldNotBe` record {status = Recorded}

      it "supports show" $ do
        show record `shouldSatisfy` (not . null)

    describe "DomainEvent" $ do
      it "constructs AuditRecordAccepted" $ do
        let event = AuditRecordAccepted
              { identifier = AuditRecordIdentifier (mkULID 1)
              , eventType = "order.created"
              , trace = Trace (mkULID 10)
              }
        event.identifier `shouldBe` AuditRecordIdentifier (mkULID 1)
        event.eventType `shouldBe` "order.created"
        event.trace `shouldBe` Trace (mkULID 10)

      it "constructs AuditRecordPersisted" $ do
        let event = AuditRecordPersisted
              { identifier = AuditRecordIdentifier (mkULID 2)
              , eventType = "order.executed"
              , service = "execution"
              , result = Success
              , trace = Trace (mkULID 20)
              }
        event.identifier `shouldBe` AuditRecordIdentifier (mkULID 2)
        event.service `shouldBe` "execution"
        event.result `shouldBe` Success

      it "constructs AuditRecordPersistenceFailed" $ do
        let event = AuditRecordPersistenceFailed
              { identifier = AuditRecordIdentifier (mkULID 3)
              , reasonCode = AuditWriteFailed
              , trace = Trace (mkULID 30)
              }
        event.identifier `shouldBe` AuditRecordIdentifier (mkULID 3)
        event.reasonCode `shouldBe` AuditWriteFailed
        event.trace `shouldBe` Trace (mkULID 30)

      it "distinguishes different event types" $ do
        let accepted = AuditRecordAccepted
              { identifier = AuditRecordIdentifier (mkULID 1)
              , eventType = "order.created"
              , trace = Trace (mkULID 10)
              }
        let persisted = AuditRecordPersisted
              { identifier = AuditRecordIdentifier (mkULID 1)
              , eventType = "order.created"
              , service = "execution"
              , result = Success
              , trace = Trace (mkULID 10)
              }
        let failed = AuditRecordPersistenceFailed
              { identifier = AuditRecordIdentifier (mkULID 1)
              , reasonCode = AuditWriteFailed
              , trace = Trace (mkULID 10)
              }
        accepted `shouldNotBe` persisted
        persisted `shouldNotBe` failed
        failed `shouldNotBe` accepted

      it "supports show for all variants" $ do
        show (AuditRecordAccepted (AuditRecordIdentifier (mkULID 1)) "e" (Trace (mkULID 2)))
          `shouldSatisfy` (not . null)
        show (AuditRecordPersisted (AuditRecordIdentifier (mkULID 1)) "e" "s" Success (Trace (mkULID 2)))
          `shouldSatisfy` (not . null)
        show (AuditRecordPersistenceFailed (AuditRecordIdentifier (mkULID 1)) DataSchemaInvalid (Trace (mkULID 2)))
          `shouldSatisfy` (not . null)
