module Domain.InsightCollection.AggregateSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (Day, UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (
  CollectionOptions (..),
  CollectionStatus (..),
  FailureDetail (..),
  FailureStage (..),
  InsightArtifact (..),
  InsightCollection,
  InsightCollectionIdentifier (..),
  InsightCollectionRequestSnapshot (..),
  InsightRecord (..),
  InsightRecordIdentifier (..),
  RequestedBy (..),
  SignalClass (..),
  SourceCollectionStatus (..),
  SourceOutcome (..),
  SourceType (..),
  mkInsightCollectionRequestSnapshot,
  recordCollectionFailure,
  recordCollectionSuccess,
  startCollection,
 )
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedDay :: Day
fixedDay = fromGregorian 2026 1 15

fixedTime :: UTCTime
fixedTime = UTCTime fixedDay 0

testIdentifier :: InsightCollectionIdentifier
testIdentifier = InsightCollectionIdentifier (mkULID 1)

testTrace :: Trace
testTrace = Trace (mkULID 100)

testRecordIdentifier :: InsightRecordIdentifier
testRecordIdentifier = InsightRecordIdentifier (mkULID 200)

testSnapshot :: InsightCollectionRequestSnapshot
testSnapshot =
  InsightCollectionRequestSnapshot
    { targetDate = fixedDay
    , requestedBy = Scheduler
    , sourceTypes = [X, GitHub]
    , options = Nothing
    }

testRecord :: InsightRecord
testRecord =
  InsightRecord
    { identifier = testRecordIdentifier
    , sourceType = X
    , sourceUrl = "https://x.com/example/status/1"
    , evidenceSnippet = "Market anomaly detected in semiconductor sector"
    , collectedAt = fixedTime
    , summary = "Significant structural anomaly in tech stocks"
    , signalClass = StructuralAnomaly
    , soWhatScore = 0.85
    , skillVersion = "v1.0.0"
    }

testSourceCollectionStatus :: SourceCollectionStatus
testSourceCollectionStatus =
  SourceCollectionStatus
    { sourceType = X
    , status = SourceSuccess
    }

testArtifact :: InsightArtifact
testArtifact =
  InsightArtifact
    { identifier = testIdentifier
    , count = 10
    , storagePath = "/insight/2026-01-15.parquet"
    , sourceStatus = [testSourceCollectionStatus]
    , partialFailure = False
    }

testFailureDetail :: FailureDetail
testFailureDetail =
  FailureDetail
    { reasonCode = DependencyTimeout
    , detail = Just "X API timeout"
    , retryable = True
    , sourceType = Just X
    , stage = Just Collect
    }

mkPendingCollection :: InsightCollection
mkPendingCollection =
  case startCollection testIdentifier testTrace testSnapshot of
    Left failure -> error ("Unexpected Left: " ++ show failure)
    Right collection -> collection

spec :: Spec
spec =
  describe "Domain.InsightCollection.Aggregate" $ do
    -- Must-3: 識別子型テスト (XXXIdentifier形式)
    describe "InsightCollectionIdentifier" $ do
      it "supports equality" $ do
        InsightCollectionIdentifier (mkULID 1) `shouldBe` InsightCollectionIdentifier (mkULID 1)
        InsightCollectionIdentifier (mkULID 1) `shouldNotBe` InsightCollectionIdentifier (mkULID 2)

      it "supports ordering" $ do
        compare (InsightCollectionIdentifier (mkULID 1)) (InsightCollectionIdentifier (mkULID 2))
          `shouldBe` LT

    -- Must-4: InsightCollectionRequestSnapshot テスト
    describe "InsightCollectionRequestSnapshot" $ do
      it "holds targetDate, requestedBy, sourceTypes, and options" $ do
        testSnapshot.targetDate `shouldBe` fixedDay
        testSnapshot.requestedBy `shouldBe` Scheduler
        testSnapshot.sourceTypes `shouldBe` [X, GitHub]
        testSnapshot.options `shouldBe` Nothing

      it "supports all 4 SourceTypes" $ do
        let allTypes = [X, YouTube, Paper, GitHub]
        length allTypes `shouldBe` 4

      it "supports CollectionOptions" $ do
        let options =
              CollectionOptions
                { forceRecollect = True
                , dryRun = False
                , maxItemsPerSource = Just 100
                }
        options.forceRecollect `shouldBe` True
        options.maxItemsPerSource `shouldBe` Just 100

    -- Must-6: InsightRecord テスト
    describe "InsightRecord" $ do
      it "holds all required fields" $ do
        testRecord.sourceType `shouldBe` X
        testRecord.sourceUrl `shouldBe` "https://x.com/example/status/1"
        testRecord.evidenceSnippet `shouldBe` "Market anomaly detected in semiconductor sector"
        testRecord.signalClass `shouldBe` StructuralAnomaly
        testRecord.soWhatScore `shouldBe` 0.85
        testRecord.skillVersion `shouldBe` "v1.0.0"

    -- Must-7: InsightArtifact テスト
    describe "InsightArtifact" $ do
      it "holds identifier, count, storagePath, sourceStatus, and partialFailure" $ do
        testArtifact.count `shouldBe` 10
        testArtifact.storagePath `shouldBe` "/insight/2026-01-15.parquet"
        testArtifact.partialFailure `shouldBe` False
        length testArtifact.sourceStatus `shouldBe` 1

    -- Must-8: FailureDetail テスト
    describe "FailureDetail" $ do
      it "holds reasonCode, detail, retryable, sourceType, and stage" $ do
        testFailureDetail.reasonCode `shouldBe` DependencyTimeout
        testFailureDetail.detail `shouldBe` Just "X API timeout"
        testFailureDetail.retryable `shouldBe` True
        testFailureDetail.sourceType `shouldBe` Just X
        testFailureDetail.stage `shouldBe` Just Collect

    -- Must-1 + Must-26: startCollection テスト
    describe "startCollection" $ do
      it "creates a Pending collection with given identifier (Must-26 identifier immutability)" $ do
        let collection = mkPendingCollection
        collection.status `shouldBe` Pending
        collection.identifier `shouldBe` testIdentifier
        collection.count `shouldBe` Nothing
        collection.storagePath `shouldBe` Nothing
        collection.reasonCode `shouldBe` Nothing
        collection.processedAt `shouldBe` Nothing
        collection.insightArtifact `shouldBe` Nothing
        collection.failureDetail `shouldBe` Nothing

      it "returns Right for valid snapshot" $ do
        startCollection testIdentifier testTrace testSnapshot `shouldSatisfy` isRight

    -- Must-23 INV-IC-001: recordCollectionSuccess テスト
    describe "recordCollectionSuccess (INV-IC-001)" $ do
      it "transitions Pending to Collected with required fields" $ do
        -- TST-IC-005: status=collected 時に count/storagePath/insightArtifact.sourceStatus が必須
        let collection = mkPendingCollection
        case recordCollectionSuccess 10 "/insight/2026-01-15.parquet" testArtifact [testRecord] fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right updated -> do
            updated.status `shouldBe` Collected
            updated.count `shouldBe` Just 10
            updated.storagePath `shouldBe` Just "/insight/2026-01-15.parquet"
            updated.insightArtifact `shouldBe` Just testArtifact

      it "rejects empty storagePath (INV-IC-001)" $ do
        let collection = mkPendingCollection
        recordCollectionSuccess 10 "" testArtifact [testRecord] fixedTime collection
          `shouldSatisfy` isLeft

      it "rejects artifact with empty sourceStatus (INV-IC-001)" $ do
        let collection = mkPendingCollection
        let emptyArtifact =
              InsightArtifact
                { identifier = testIdentifier
                , count = 0
                , storagePath = "/insight/2026-01-15.parquet"
                , sourceStatus = []
                , partialFailure = False
                }
        recordCollectionSuccess 10 "/insight/2026-01-15.parquet" emptyArtifact [testRecord] fixedTime collection
          `shouldSatisfy` isLeft

      it "rejects transition from non-Pending status" $ do
        let collection = mkPendingCollection
        case recordCollectionSuccess 10 "/insight/2026-01-15.parquet" testArtifact [testRecord] fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right collected ->
            recordCollectionSuccess 5 "/insight/other.parquet" testArtifact [] fixedTime collected
              `shouldSatisfy` isLeft

    -- Must-24 INV-IC-003: recordCollectionFailure テスト
    describe "recordCollectionFailure (INV-IC-003)" $ do
      it "transitions Pending to Failed with reasonCode" $ do
        let collection = mkPendingCollection
        case recordCollectionFailure testFailureDetail fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right updated -> do
            updated.status `shouldBe` Failed
            updated.reasonCode `shouldBe` Just DependencyTimeout
            updated.failureDetail `shouldBe` Just testFailureDetail

      it "rejects transition from non-Pending status" $ do
        let collection = mkPendingCollection
        case recordCollectionFailure testFailureDetail fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right failed ->
            recordCollectionFailure testFailureDetail fixedTime failed
              `shouldSatisfy` isLeft

    -- Must-26: identifier 不変性テスト
    describe "identifier immutability (Must-26 INV-IC-005)" $ do
      it "identifier does not change after recordCollectionSuccess" $ do
        let collection = mkPendingCollection
        case recordCollectionSuccess 10 "/insight/2026-01-15.parquet" testArtifact [testRecord] fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right updated -> updated.identifier `shouldBe` testIdentifier

      it "identifier does not change after recordCollectionFailure" $ do
        let collection = mkPendingCollection
        case recordCollectionFailure testFailureDetail fixedTime collection of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right updated -> updated.identifier `shouldBe` testIdentifier

    -- TST-IC-001: TST input validation (RULE-IC-001)
    describe "TST-IC-001: input validation (RULE-IC-001)" $ do
      it "collection starts with targetDate and requestedBy present" $ do
        -- 型システムにより必須フィールドが揃った状態のみ生成可能
        let collection = mkPendingCollection
        collection.request.targetDate `shouldBe` fixedDay
        collection.request.requestedBy `shouldBe` Scheduler

    -- Must-20: mkInsightCollectionRequestSnapshot smart constructor テスト
    describe "mkInsightCollectionRequestSnapshot (Must-20)" $ do
      it "returns Right for valid inputs" $ do
        mkInsightCollectionRequestSnapshot fixedDay Scheduler [X, GitHub] Nothing
          `shouldSatisfy` isRight

      it "returns Right for User requestedBy" $ do
        mkInsightCollectionRequestSnapshot fixedDay User [YouTube] Nothing
          `shouldSatisfy` isRight

      it "returns Right for empty sourceTypes (all sources)" $ do
        mkInsightCollectionRequestSnapshot fixedDay Scheduler [] Nothing
          `shouldSatisfy` isRight

    -- INV-IC-002: recordCollectionSuccess records evidence completeness テスト
    describe "INV-IC-002: evidence completeness in recordCollectionSuccess" $ do
      it "rejects record with empty sourceUrl (INV-IC-002)" $ do
        let collection = mkPendingCollection
        let invalidRecord =
              InsightRecord
                { identifier = testRecordIdentifier
                , sourceType = X
                , sourceUrl = ""
                , evidenceSnippet = "some evidence"
                , collectedAt = fixedTime
                , summary = "summary"
                , signalClass = StructuralAnomaly
                , soWhatScore = 0.5
                , skillVersion = "v1.0.0"
                }
        recordCollectionSuccess 1 "/path/to/data.parquet" testArtifact [invalidRecord] fixedTime collection
          `shouldSatisfy` isLeft

      it "rejects record with empty evidenceSnippet (INV-IC-002)" $ do
        let collection = mkPendingCollection
        let invalidRecord =
              InsightRecord
                { identifier = testRecordIdentifier
                , sourceType = X
                , sourceUrl = "https://x.com/example"
                , evidenceSnippet = ""
                , collectedAt = fixedTime
                , summary = "summary"
                , signalClass = StructuralAnomaly
                , soWhatScore = 0.5
                , skillVersion = "v1.0.0"
                }
        recordCollectionSuccess 1 "/path/to/data.parquet" testArtifact [invalidRecord] fixedTime collection
          `shouldSatisfy` isLeft

      it "accepts records with non-empty sourceUrl and evidenceSnippet (INV-IC-002)" $ do
        let collection = mkPendingCollection
        recordCollectionSuccess 10 "/insight/2026-01-15.parquet" testArtifact [testRecord] fixedTime collection
          `shouldSatisfy` isRight
