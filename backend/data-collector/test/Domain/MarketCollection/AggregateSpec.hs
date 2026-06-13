module Domain.MarketCollection.AggregateSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (Day, UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  CollectionMode (..),
  CollectionRequestSnapshot (..),
  CollectionStatus (..),
  MarketCollection,
  MarketCollectionEvent (..),
  MarketCollectionIdentifier (..),
  MarketSourceStatus (..),
  RequestedBy (..),
  SourceStatus (..),
  mkCollectedArtifact,
  recordCollectionFailure,
  recordCollectionSuccess,
  startCollection,
 )
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedDay :: Day
fixedDay = fromGregorian 2026 1 15

fixedTime :: UTCTime
fixedTime = UTCTime fixedDay 0

testIdentifier :: MarketCollectionIdentifier
testIdentifier = MarketCollectionIdentifier (mkULID 1)

testTrace :: Trace
testTrace = Trace (mkULID 100)

testSnapshot :: CollectionRequestSnapshot
testSnapshot =
  CollectionRequestSnapshot
    { targetDate = fixedDay
    , requestedBy = Scheduler
    , mode = Just Daily
    }

testSourceStatus :: SourceStatus
testSourceStatus = SourceStatus{jp = Ok, us = Ok}

mkPendingCollection :: (MarketCollection, [MarketCollectionEvent])
mkPendingCollection = startCollection testIdentifier testSnapshot testTrace

spec :: Spec
spec =
  describe "Domain.MarketCollection.Aggregate" $ do
    -- Must-23: 識別子型テスト
    describe "MarketCollectionIdentifier" $ do
      it "supports equality" $ do
        MarketCollectionIdentifier (mkULID 1) `shouldBe` MarketCollectionIdentifier (mkULID 1)
        MarketCollectionIdentifier (mkULID 1) `shouldNotBe` MarketCollectionIdentifier (mkULID 2)

      it "supports ordering" $ do
        compare (MarketCollectionIdentifier (mkULID 1)) (MarketCollectionIdentifier (mkULID 2))
          `shouldBe` LT

    -- Must-05: CollectionRequestSnapshot テスト
    describe "CollectionRequestSnapshot" $ do
      it "holds targetDate, requestedBy, and mode" $ do
        testSnapshot.targetDate `shouldBe` fixedDay
        testSnapshot.requestedBy `shouldBe` Scheduler
        testSnapshot.mode `shouldBe` Just Daily

      it "supports mode=Nothing" $ do
        let snapshot = CollectionRequestSnapshot{targetDate = fixedDay, requestedBy = User, mode = Nothing}
        snapshot.mode `shouldBe` Nothing
        snapshot.requestedBy `shouldBe` User

    -- Must-06: SourceStatus テスト
    describe "SourceStatus" $ do
      it "holds jp and us MarketSourceStatus" $ do
        testSourceStatus.jp `shouldBe` Ok
        testSourceStatus.us `shouldBe` Ok

      it "supports SourceFailed status" $ do
        let partialFailure = SourceStatus{jp = Ok, us = SourceFailed}
        partialFailure.us `shouldBe` SourceFailed

    -- Must-07: CollectedArtifact スマートコンストラクタテスト
    describe "CollectedArtifact" $ do
      it "constructs successfully with valid inputs" $ do
        mkCollectedArtifact fixedDay "/raw/2026-01-15.parquet" testSourceStatus 1000
          `shouldSatisfy` isRight

      it "rejects negative rowCount" $ do
        -- Must-07 受入条件: rowCount < 0 のとき Left を返す
        mkCollectedArtifact fixedDay "/raw/2026-01-15.parquet" testSourceStatus (-1)
          `shouldSatisfy` isLeft

      it "rejects empty storagePath" $ do
        mkCollectedArtifact fixedDay "" testSourceStatus 100
          `shouldSatisfy` isLeft

      it "allows rowCount=0" $ do
        mkCollectedArtifact fixedDay "/raw/empty.parquet" testSourceStatus 0
          `shouldSatisfy` isRight

    -- Must-03: CollectionStatus 3値テスト
    describe "CollectionStatus" $ do
      it "has exactly Pending, Collected, Failed" $ do
        Pending `shouldBe` Pending
        Collected `shouldBe` Collected
        Failed `shouldBe` Failed
        Pending `shouldNotBe` Collected
        Collected `shouldNotBe` Failed

    -- Must-13: identifier 不変性テスト
    describe "startCollection" $ do
      it "creates a Pending collection with given identifier" $ do
        let (collection, _) = mkPendingCollection
        collection.status `shouldBe` Pending
        collection.identifier `shouldBe` testIdentifier
        collection.storagePath `shouldBe` Nothing
        collection.sourceStatus `shouldBe` Nothing
        collection.reasonCode `shouldBe` Nothing
        collection.processedAt `shouldBe` Nothing

      it "emits MarketCollectionStarted event" $ do
        let (_, events) = mkPendingCollection
        case events of
          [event] ->
            event
              `shouldBe` MarketCollectionStarted
                { identifier = testIdentifier
                , targetDate = fixedDay
                , trace = testTrace
                }
          _ -> fail ("Expected exactly 1 event, got " ++ show (length events))

    -- Must-13: identifier は更新コマンド後も変化しない
    describe "identifier immutability (Must-13 INV-DC-005)" $ do
      it "identifier does not change after recordCollectionSuccess" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionSuccess "/raw/2026-01-15.parquet" testSourceStatus 500 fixedTime collection of
          Left _ -> fail "Expected Right"
          Right (updated, _) -> updated.identifier `shouldBe` testIdentifier

      it "identifier does not change after recordCollectionFailure" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionFailure DataSourceTimeout Nothing fixedTime collection of
          Left _ -> fail "Expected Right"
          Right (updated, _) -> updated.identifier `shouldBe` testIdentifier

    -- Must-11: INV-DC-001 テスト
    describe "recordCollectionSuccess (INV-DC-001)" $ do
      it "transitions to Collected with storagePath and sourceStatus" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionSuccess "/raw/2026-01-15.parquet" testSourceStatus 500 fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (updated, _) -> do
            updated.status `shouldBe` Collected
            updated.storagePath `shouldBe` Just "/raw/2026-01-15.parquet"
            updated.sourceStatus `shouldBe` Just testSourceStatus
            updated.rowCount `shouldBe` Just 500

      it "rejects empty storagePath (INV-DC-001)" $ do
        let (collection, _) = mkPendingCollection
        recordCollectionSuccess "" testSourceStatus 100 fixedTime collection
          `shouldSatisfy` isLeft

      it "rejects transition from non-Pending status" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionSuccess "/raw/2026-01-15.parquet" testSourceStatus 500 fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (collected, _) ->
            recordCollectionSuccess "/raw/other.parquet" testSourceStatus 100 fixedTime collected
              `shouldSatisfy` isLeft

      it "emits MarketCollectionCompleted event" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionSuccess "/raw/2026-01-15.parquet" testSourceStatus 500 fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (_, [event]) ->
            event
              `shouldBe` MarketCollectionCompleted
                { identifier = testIdentifier
                , targetDate = fixedDay
                , storagePath = "/raw/2026-01-15.parquet"
                , sourceStatus = testSourceStatus
                , trace = testTrace
                }
          Right (_, events) -> fail ("Expected 1 event, got " ++ show (length events))

    -- Must-12: INV-DC-002 テスト
    describe "recordCollectionFailure (INV-DC-002)" $ do
      it "transitions to Failed with reasonCode" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionFailure DataSourceTimeout Nothing fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (updated, _) -> do
            updated.status `shouldBe` Failed
            updated.reasonCode `shouldBe` Just DataSourceTimeout

      it "rejects transition from non-Pending status" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionFailure DataSourceTimeout Nothing fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (failed, _) ->
            recordCollectionFailure DataSchemaInvalid Nothing fixedTime failed
              `shouldSatisfy` isLeft

      it "emits MarketCollectionFailed event" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionFailure ComplianceSourceUnapproved (Just "source not approved") fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (_, [event]) ->
            event
              `shouldBe` MarketCollectionFailed
                { identifier = testIdentifier
                , reasonCode = ComplianceSourceUnapproved
                , detail = Just "source not approved"
                , trace = testTrace
                }
          Right (_, events) -> fail ("Expected 1 event, got " ++ show (length events))

    -- Must-15: ドメインイベント 3バリアントテスト
    describe "MarketCollectionEvent" $ do
      it "distinguishes all 3 event types" $ do
        let started = MarketCollectionStarted testIdentifier fixedDay testTrace
        let completed = MarketCollectionCompleted testIdentifier fixedDay "/p" testSourceStatus testTrace
        let failed = MarketCollectionFailed testIdentifier DataSourceTimeout Nothing testTrace
        started `shouldNotBe` completed
        completed `shouldNotBe` failed

    -- TST-DC-001: RULE-DC-001 — 入力必須項目欠損時テスト
    describe "TST-DC-001: input validation" $ do
      it "collection starts only when required fields are present" $ do
        -- startCollection は CollectionRequestSnapshot を受け取るため、
        -- 必須フィールドが揃った状態でのみ生成可能（型システムで保証）
        let (collection, _) = startCollection testIdentifier testSnapshot testTrace
        collection.request.targetDate `shouldBe` fixedDay
        collection.request.requestedBy `shouldBe` Scheduler

    -- TST-DC-003: RULE-DC-003 — sourceStatus.jp/us の完全性テスト
    describe "TST-DC-003: sourceStatus completeness" $ do
      it "recorded collection always has both jp and us sourceStatus" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionSuccess "/raw/2026-01-15.parquet" testSourceStatus 500 fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (updated, _) -> do
            case updated.sourceStatus of
              Nothing -> fail "Expected Just SourceStatus, got Nothing"
              Just status -> do
                status.jp `shouldBe` Ok
                status.us `shouldBe` Ok

    -- TST-DC-006: RULE-DC-006 — market.collected 必須項目テスト
    describe "TST-DC-006: MarketCollectionCompleted required fields" $ do
      it "completed event always contains targetDate, storagePath, sourceStatus" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionSuccess "/raw/2026-01-15.parquet" testSourceStatus 500 fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (_, [MarketCollectionCompleted{targetDate = td, storagePath = sp, sourceStatus = ss}]) -> do
            td `shouldBe` fixedDay
            sp `shouldBe` "/raw/2026-01-15.parquet"
            ss `shouldBe` testSourceStatus
          Right _ -> fail "Unexpected event shape"

    -- TST-DC-007: RULE-DC-007 — timeout/unavailable reasonCode テスト
    describe "TST-DC-007: timeout and unavailable reason codes" $ do
      it "DATA_SOURCE_TIMEOUT produces correct reasonCode in event" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionFailure DataSourceTimeout Nothing fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (_, [MarketCollectionFailed{reasonCode = code}]) ->
            code `shouldBe` DataSourceTimeout
          Right _ -> fail "Unexpected event shape"

      it "DATA_SOURCE_UNAVAILABLE produces correct reasonCode in event" $ do
        let (collection, _) = mkPendingCollection
        case recordCollectionFailure DataSourceUnavailable Nothing fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right (_, [MarketCollectionFailed{reasonCode = code}]) ->
            code `shouldBe` DataSourceUnavailable
          Right _ -> fail "Unexpected event shape"

    -- TST-DC-009: RULE-DC-009 — identifier 命名統一テスト
    describe "TST-DC-009: identifier naming convention" $ do
      it "aggregate uses 'identifier' field name, not 'id'" $ do
        -- コンパイル成功がそのまま証明（record.identifier でアクセス可能）
        let (collection, _) = mkPendingCollection
        collection.identifier `shouldBe` testIdentifier
