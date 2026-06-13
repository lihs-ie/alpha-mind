module UseCase.CollectMarketDataSpec (spec) where

import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (Day, UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ulidFromInteger)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  CollectedArtifact,
  CollectionStatus (..),
  FailureDetail (..),
  MarketCollection,
  MarketCollectionIdentifier (..),
  MarketCollectionRepository (..),
  MarketSourceStatus (..),
  RequestedBy (..),
  SourceStatus (..),
  collectedArtifactSourceStatus,
  collectedArtifactStoragePath,
 )
import Domain.MarketCollection.CollectionDispatch (
  CollectionDispatch,
  CollectionDispatchRepository (..),
  DispatchStatus,
 )
import Domain.MarketCollection.CollectionDispatch qualified as DispatchStatus
import Domain.MarketCollection.CollectionQualityPolicy (
  MarketSchemaIntegritySpecification (..),
  RawMarketField (..),
  RawMarketRecord (..),
 )
import Domain.MarketCollection.MarketDataSource (MarketDataSource (..))
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Domain.MarketCollection.SourcePolicySpecificationService (
  ApprovedSourceSpecification (..),
  DataSourceName (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.CollectMarketData (
  CollectMarketDataResult (..),
  CollectionEventPublisher (..),
  NormalizedMarketDataset,
  RawMarketDataPort (..),
  RawSourceEvent (..),
  collectMarketData,
 )
import UseCase.RecordCollectionAudit (
  CollectionAuditEntry,
  CollectionAuditPort (..),
 )

-- ---------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------

mkULIDTrace :: Integer -> Trace
mkULIDTrace n = case ulidFromInteger n of
  Right ulid -> Trace ulid
  Left message -> error (show message)

mkCollectionIdentifier :: Integer -> MarketCollectionIdentifier
mkCollectionIdentifier n = case ulidFromInteger n of
  Right ulid -> MarketCollectionIdentifier ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2025 6 1) 0

fixedDay :: Day
fixedDay = fromGregorian 2025 6 1

fixedTrace :: Trace
fixedTrace = mkULIDTrace 100

fixedIdentifier :: MarketCollectionIdentifier
fixedIdentifier = mkCollectionIdentifier 1

-- | テスト用承認済みソース仕様。フィールド名と衝突しないよう testApprovedSources とする。
testApprovedSources :: ApprovedSourceSpecification
testApprovedSources =
  ApprovedSourceSpecification
    { approvedSources = [DataSourceName "jquants"]
    }

testSchemaSpecification :: MarketSchemaIntegritySpecification
testSchemaSpecification =
  MarketSchemaIntegritySpecification
    { requiredFields = ["date", "close"]
    }

validRawEvent :: RawSourceEvent
validRawEvent =
  RawSourceEvent
    { targetDate = Just fixedDay
    , requestedBy = Just Scheduler
    , requestedSources = [DataSourceName "jquants"]
    , trace = Just fixedTrace
    }

validRecord :: RawMarketRecord
validRecord =
  RawMarketRecord
    { fields =
        [ ("date", FieldText "2025-06-01")
        , ("close", FieldDouble 1000.0)
        ]
    }

-- ---------------------------------------------------------------------
-- Mock state
-- ---------------------------------------------------------------------

data MockState = MockState
  { collectionStore :: Map.Map Text MarketCollection
  , dispatchStore :: Map.Map Text CollectionDispatch
  , persistedDatasets :: [(MarketCollectionIdentifier, Day, NormalizedMarketDataset)]
  , publishedCollected :: [(MarketCollectionIdentifier, CollectedArtifact, Trace)]
  , publishedFailed :: [(MarketCollectionIdentifier, ReasonCode, Maybe Text, Trace)]
  , auditEntries :: [(MarketCollectionIdentifier, Trace, CollectionAuditEntry)]
  , fetchJapanCallCount :: Int
  , fetchUsCallCount :: Int
  , persistDataCallCount :: Int
  , publishCollectedCallCount :: Int
  , publishFailedCallCount :: Int
  , fakeJapanResult :: Either FailureDetail [RawMarketRecord]
  -- ^ fake で返す JP データ
  , fakeUsResult :: Either FailureDetail [RawMarketRecord]
  -- ^ fake で返す US データ
  , fakePersistResult :: Either Text Text
  -- ^ fake で返す persist 結果
  , preloadedDispatch :: Maybe CollectionDispatch
  -- ^ 事前設定の既存 dispatch（冪等テスト用）
  }

newMockState :: IO (IORef MockState)
newMockState =
  newIORef
    MockState
      { collectionStore = Map.empty
      , dispatchStore = Map.empty
      , persistedDatasets = []
      , publishedCollected = []
      , publishedFailed = []
      , auditEntries = []
      , fetchJapanCallCount = 0
      , fetchUsCallCount = 0
      , persistDataCallCount = 0
      , publishCollectedCallCount = 0
      , publishFailedCallCount = 0
      , fakeJapanResult = Right [validRecord]
      , fakeUsResult = Right [validRecord]
      , fakePersistResult = Right "gs://bucket/2025-06-01.parquet"
      , preloadedDispatch = Nothing
      }

-- ---------------------------------------------------------------------
-- Mock monad
-- ---------------------------------------------------------------------

newtype MockM a = MockM {runMockM :: IORef MockState -> IO a}

instance Functor MockM where
  fmap f (MockM g) = MockM $ \ref -> fmap f (g ref)

instance Applicative MockM where
  pure a = MockM $ \_ -> pure a
  MockM f <*> MockM a = MockM $ \ref -> f ref <*> a ref

instance Monad MockM where
  MockM a >>= f = MockM $ \ref -> do
    value <- a ref
    runMockM (f value) ref

-- ---------------------------------------------------------------------
-- Port instances (fake)
-- ---------------------------------------------------------------------

instance MarketCollectionRepository MockM where
  find collectionIdentifier = MockM $ \ref -> do
    state <- readIORef ref
    pure $ Map.lookup (showText collectionIdentifier.value) state.collectionStore
  findByStatus _ = pure []
  search _ = pure []
  persist collection = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { collectionStore =
            Map.insert
              (showText collection.identifier.value)
              collection
              state.collectionStore
        }
  terminate _ = pure ()

instance CollectionDispatchRepository MockM where
  find collectionIdentifier = MockM $ \ref -> do
    state <- readIORef ref
    case state.preloadedDispatch of
      Just dispatch
        | dispatch.identifier == collectionIdentifier -> pure (Just dispatch)
      _ ->
        pure $ Map.lookup (showText collectionIdentifier.value) state.dispatchStore
  persist dispatch = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { dispatchStore =
            Map.insert
              (showText dispatch.identifier.value)
              dispatch
              state.dispatchStore
        }
  terminate _ = pure ()

instance MarketDataSource MockM where
  fetchJapanMarketData _ = MockM $ \ref -> do
    modifyIORef' ref $ \state ->
      state{fetchJapanCallCount = state.fetchJapanCallCount + 1}
    state <- readIORef ref
    pure state.fakeJapanResult
  fetchUsMarketData _ = MockM $ \ref -> do
    modifyIORef' ref $ \state ->
      state{fetchUsCallCount = state.fetchUsCallCount + 1}
    state <- readIORef ref
    pure state.fakeUsResult

instance RawMarketDataPort MockM where
  persistRawMarketData collectionIdentifier day dataset = MockM $ \ref -> do
    modifyIORef' ref $ \state ->
      state
        { persistDataCallCount = state.persistDataCallCount + 1
        , persistedDatasets = (collectionIdentifier, day, dataset) : state.persistedDatasets
        }
    state <- readIORef ref
    pure state.fakePersistResult

instance CollectionEventPublisher MockM where
  publishMarketCollected collectionIdentifier artifact traceValue = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { publishCollectedCallCount = state.publishCollectedCallCount + 1
        , publishedCollected = (collectionIdentifier, artifact, traceValue) : state.publishedCollected
        }
  publishMarketCollectFailed collectionIdentifier reasonCode detail traceValue = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { publishFailedCallCount = state.publishFailedCallCount + 1
        , publishedFailed = (collectionIdentifier, reasonCode, detail, traceValue) : state.publishedFailed
        }

instance CollectionAuditPort MockM where
  writeCollectionAudit collectionIdentifier traceValue entry = MockM $ \ref ->
    modifyIORef' ref $ \state ->
      state
        { auditEntries = (collectionIdentifier, traceValue, entry) : state.auditEntries
        }

runWithMock :: IORef MockState -> MockM a -> IO a
runWithMock ref (MockM f) = f ref

showText :: (Show a) => a -> Text
showText = Text.pack . Prelude.show

-- ---------------------------------------------------------------------
-- Test helper
-- ---------------------------------------------------------------------

runCollectMarketData :: IORef MockState -> IO CollectMarketDataResult
runCollectMarketData ref =
  runWithMock ref $
    collectMarketData
      fixedTime
      fixedIdentifier
      testApprovedSources
      testSchemaSpecification
      validRawEvent

-- | DispatchStatus.Failed を明示的に参照するヘルパー。
dispatchFailed :: DispatchStatus
dispatchFailed = DispatchStatus.Failed

dispatchPublished :: DispatchStatus
dispatchPublished = DispatchStatus.Published

-- ---------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.CollectMarketData" $ do
    -- TC-UC-001: 正常収集成功
    describe "TC-UC-001: 正常収集成功" $ do
      it "CollectionSucceeded を返す" $ do
        ref <- newMockState
        result <- runCollectMarketData ref
        result `shouldBe` CollectionSucceeded

      it "persistRawMarketData が呼ばれる" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        state <- readIORef ref
        state.persistDataCallCount `shouldBe` 1

      it "publishMarketCollected が呼ばれる" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        state <- readIORef ref
        state.publishCollectedCallCount `shouldBe` 1

      it "CollectionDispatch が Published 状態で persist される（Must-19）" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        state <- readIORef ref
        let dispatchStatus = fmap (.dispatchStatus) $ Map.lookup (showText fixedIdentifier.value) state.dispatchStore
        dispatchStatus `shouldBe` Just dispatchPublished

      it "publishMarketCollected の CollectedArtifact に persistRawMarketData の storagePath が含まれる（Must-15）" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        state <- readIORef ref
        case state.publishedCollected of
          [] -> fail "publishMarketCollected was not called"
          (_, artifact, _) : _ ->
            collectedArtifactStoragePath artifact `shouldBe` "gs://bucket/2025-06-01.parquet"

      it "fetchJapanMarketData 成功時 SourceStatus.jp = Ok（Must-11）" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        state <- readIORef ref
        case state.publishedCollected of
          [] -> fail "publishMarketCollected was not called"
          (_, artifact, _) : _ ->
            (collectedArtifactSourceStatus artifact).jp `shouldBe` Ok

      it "MarketCollection が Collected 状態で persist される（Must-17）" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        state <- readIORef ref
        let collectionStatus = fmap (.status) $ Map.lookup (showText fixedIdentifier.value) state.collectionStore
        collectionStatus `shouldBe` Just Collected

      it "trace が入力イベントから publishMarketCollected へ伝播される（TC-UC-008）" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        state <- readIORef ref
        case state.publishedCollected of
          [] -> fail "publishMarketCollected was not called"
          (_, _, traceValue) : _ ->
            traceValue `shouldBe` fixedTrace

    -- TC-UC-002: 冪等性（同一 identifier の重複受信）
    describe "TC-UC-002: 冪等性チェック — CollectionDuplicate" $ do
      it "Published 状態の Dispatch が存在するとき CollectionDuplicate を返す（Must-07）" $ do
        ref <- newMockState
        -- 1回目を実行して Published 状態にする
        _ <- runCollectMarketData ref
        -- 2回目: Published dispatch が存在する → CollectionDuplicate
        result <- runCollectMarketData ref
        result `shouldBe` CollectionDuplicate

      it "CollectionDuplicate 時は persistRawMarketData が呼ばれない（Must-07）" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        initialState <- readIORef ref
        let callCount1 = initialState.persistDataCallCount
        _ <- runCollectMarketData ref
        finalState <- readIORef ref
        finalState.persistDataCallCount `shouldBe` callCount1

      it "CollectionDuplicate 時は publishMarketCollected が呼ばれない（Must-07）" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        initialState <- readIORef ref
        let callCount1 = initialState.publishCollectedCallCount
        _ <- runCollectMarketData ref
        finalState <- readIORef ref
        finalState.publishCollectedCallCount `shouldBe` callCount1

      it "Failed 状態の Dispatch が存在するとき CollectionDuplicate を返す（Must-07）" $ do
        ref <- newMockState
        -- JP データ取得失敗で Failed dispatch を作る
        modifyIORef' ref $ \state ->
          state
            { fakeJapanResult =
                Left
                  FailureDetail
                    { reasonCode = DataSchemaInvalid
                    , detail = Nothing
                    , retryable = False
                    }
            }
        _ <- runCollectMarketData ref
        state1 <- readIORef ref
        let fetchedDispatchStatus =
              fmap (.dispatchStatus) $
                Map.lookup (showText fixedIdentifier.value) state1.dispatchStore
        fetchedDispatchStatus `shouldBe` Just dispatchFailed
        -- 2回目
        result <- runCollectMarketData ref
        result `shouldBe` CollectionDuplicate

    -- TC-UC-003: targetDate 欠損 → CollectionFailed RequestValidationFailed
    describe "TC-UC-003: targetDate 欠損 — CollectionFailed RequestValidationFailed" $ do
      it "CollectionFailed RequestValidationFailed を返す（Must-09）" $ do
        ref <- newMockState
        let eventWithoutDate = validRawEvent{targetDate = Nothing}
        result <-
          runWithMock ref $
            collectMarketData fixedTime fixedIdentifier testApprovedSources testSchemaSpecification eventWithoutDate
        result `shouldSatisfy` isCollectionFailedWith RequestValidationFailed

      it "publishMarketCollectFailed が呼ばれる" $ do
        ref <- newMockState
        let eventWithoutDate = validRawEvent{targetDate = Nothing}
        _ <-
          runWithMock ref $
            collectMarketData fixedTime fixedIdentifier testApprovedSources testSchemaSpecification eventWithoutDate
        state <- readIORef ref
        state.publishFailedCallCount `shouldBe` 1

      it "publishMarketCollectFailed の reasonCode が RequestValidationFailed" $ do
        ref <- newMockState
        let eventWithoutDate = validRawEvent{targetDate = Nothing}
        _ <-
          runWithMock ref $
            collectMarketData fixedTime fixedIdentifier testApprovedSources testSchemaSpecification eventWithoutDate
        state <- readIORef ref
        case state.publishedFailed of
          [] -> fail "publishMarketCollectFailed was not called"
          (_, reasonCode, _, _) : _ -> reasonCode `shouldBe` RequestValidationFailed

      it "fetchJapanMarketData が呼ばれない（Must-09）" $ do
        ref <- newMockState
        let eventWithoutDate = validRawEvent{targetDate = Nothing}
        _ <-
          runWithMock ref $
            collectMarketData fixedTime fixedIdentifier testApprovedSources testSchemaSpecification eventWithoutDate
        state <- readIORef ref
        state.fetchJapanCallCount `shouldBe` 0

      it "requestedBy 欠損時も CollectionFailed RequestValidationFailed を返す" $ do
        ref <- newMockState
        let eventWithoutRequester = validRawEvent{requestedBy = Nothing}
        result <-
          runWithMock ref $
            collectMarketData fixedTime fixedIdentifier testApprovedSources testSchemaSpecification eventWithoutRequester
        result `shouldSatisfy` isCollectionFailedWith RequestValidationFailed

    -- TC-UC-004: 未承認ソース → CollectionFailed ComplianceSourceUnapproved
    describe "TC-UC-004: 未承認ソース — CollectionFailed ComplianceSourceUnapproved" $ do
      it "CollectionFailed ComplianceSourceUnapproved を返す（Must-10）" $ do
        ref <- newMockState
        let eventWithUnapprovedSource =
              validRawEvent{requestedSources = [DataSourceName "unapproved-source"]}
        result <-
          runWithMock ref $
            collectMarketData fixedTime fixedIdentifier testApprovedSources testSchemaSpecification eventWithUnapprovedSource
        result `shouldSatisfy` isCollectionFailedWith ComplianceSourceUnapproved

      it "publishMarketCollectFailed が呼ばれる" $ do
        ref <- newMockState
        let eventWithUnapprovedSource =
              validRawEvent{requestedSources = [DataSourceName "unapproved-source"]}
        _ <-
          runWithMock ref $
            collectMarketData fixedTime fixedIdentifier testApprovedSources testSchemaSpecification eventWithUnapprovedSource
        state <- readIORef ref
        state.publishFailedCallCount `shouldBe` 1

      it "fetchJapanMarketData が呼ばれない（Must-10）" $ do
        ref <- newMockState
        let eventWithUnapprovedSource =
              validRawEvent{requestedSources = [DataSourceName "unapproved-source"]}
        _ <-
          runWithMock ref $
            collectMarketData fixedTime fixedIdentifier testApprovedSources testSchemaSpecification eventWithUnapprovedSource
        state <- readIORef ref
        state.fetchJapanCallCount `shouldBe` 0

    -- TC-UC-005: JP タイムアウト → CollectionFailed DataSourceTimeout / retryable=true
    describe "TC-UC-005: JP タイムアウト — CollectionFailed DataSourceTimeout / retryable=true" $ do
      it "CollectionFailed DataSourceTimeout を返す（Must-13）" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state
            { fakeJapanResult =
                Left
                  FailureDetail
                    { reasonCode = DataSourceTimeout
                    , detail = Just "connection timeout"
                    , retryable = True
                    }
            }
        result <- runCollectMarketData ref
        result `shouldSatisfy` isCollectionFailedWith DataSourceTimeout

      it "retryable=True が伝播される（Must-13）" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state
            { fakeJapanResult =
                Left
                  FailureDetail
                    { reasonCode = DataSourceTimeout
                    , detail = Just "connection timeout"
                    , retryable = True
                    }
            }
        result <- runCollectMarketData ref
        case result of
          CollectionFailed _ isRetryable -> isRetryable `shouldBe` True
          _ -> fail $ "Expected CollectionFailed, got: " ++ show result

      it "DataSourceUnavailable も retryable=True で伝播される" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state
            { fakeJapanResult =
                Left
                  FailureDetail
                    { reasonCode = DataSourceUnavailable
                    , detail = Nothing
                    , retryable = True
                    }
            }
        result <- runCollectMarketData ref
        case result of
          CollectionFailed _ isRetryable -> isRetryable `shouldBe` True
          _ -> fail $ "Expected CollectionFailed, got: " ++ show result

      it "retryable=False のエラーは isRetryable=False" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state
            { fakeJapanResult =
                Left
                  FailureDetail
                    { reasonCode = DataSchemaInvalid
                    , detail = Nothing
                    , retryable = False
                    }
            }
        result <- runCollectMarketData ref
        case result of
          CollectionFailed _ isRetryable -> isRetryable `shouldBe` False
          _ -> fail $ "Expected CollectionFailed, got: " ++ show result

    -- TC-UC-006: スキーマ検証失敗 → CollectionFailed DataSchemaInvalid / 再試行なし
    describe "TC-UC-006: スキーマ検証失敗 — CollectionFailed DataSchemaInvalid" $ do
      it "CollectionFailed DataSchemaInvalid を返す（Must-12）" $ do
        ref <- newMockState
        let invalidRecord = RawMarketRecord{fields = [("wrong-field", FieldText "x")]}
        modifyIORef' ref $ \state ->
          state{fakeJapanResult = Right [invalidRecord]}
        result <- runCollectMarketData ref
        result `shouldSatisfy` isCollectionFailedWith DataSchemaInvalid

      it "persistRawMarketData が呼ばれない（Must-12）" $ do
        ref <- newMockState
        let invalidRecord = RawMarketRecord{fields = [("wrong-field", FieldText "x")]}
        modifyIORef' ref $ \state ->
          state{fakeJapanResult = Right [invalidRecord]}
        _ <- runCollectMarketData ref
        state <- readIORef ref
        state.persistDataCallCount `shouldBe` 0

      it "publishMarketCollected が呼ばれない（Must-12）" $ do
        ref <- newMockState
        let invalidRecord = RawMarketRecord{fields = [("wrong-field", FieldText "x")]}
        modifyIORef' ref $ \state ->
          state{fakeJapanResult = Right [invalidRecord]}
        _ <- runCollectMarketData ref
        state <- readIORef ref
        state.publishCollectedCallCount `shouldBe` 0

      it "publishMarketCollectFailed が呼ばれる" $ do
        ref <- newMockState
        let invalidRecord = RawMarketRecord{fields = [("wrong-field", FieldText "x")]}
        modifyIORef' ref $ \state ->
          state{fakeJapanResult = Right [invalidRecord]}
        _ <- runCollectMarketData ref
        state <- readIORef ref
        state.publishFailedCallCount `shouldBe` 1

      it "retryable=False（再試行なし）（Must-12）" $ do
        ref <- newMockState
        let invalidRecord = RawMarketRecord{fields = [("wrong-field", FieldText "x")]}
        modifyIORef' ref $ \state ->
          state{fakeJapanResult = Right [invalidRecord]}
        result <- runCollectMarketData ref
        case result of
          CollectionFailed _ isRetryable -> isRetryable `shouldBe` False
          _ -> fail $ "Expected CollectionFailed, got: " ++ show result

    -- TC-UC-007: 保存成功後のみ publishMarketCollected（Must-14）
    describe "TC-UC-007: 保存失敗時は publishMarketCollected を呼ばない（Must-14）" $ do
      it "persistRawMarketData 失敗時は publishMarketCollected が呼ばれない" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakePersistResult = Left "storage error"}
        _ <- runCollectMarketData ref
        state <- readIORef ref
        state.publishCollectedCallCount `shouldBe` 0

      it "persistRawMarketData 失敗時は publishMarketCollectFailed が呼ばれる" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakePersistResult = Left "storage error"}
        _ <- runCollectMarketData ref
        state <- readIORef ref
        state.publishFailedCallCount `shouldBe` 1

      it "persistRawMarketData 失敗時は CollectionFailed DependencyTimeout retryable=True を返す（Must-14）" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakePersistResult = Left "storage error"}
        result <- runCollectMarketData ref
        result `shouldBe` CollectionFailed DependencyTimeout True

      it "persistRawMarketData 失敗時の publishMarketCollectFailed の reasonCode が DependencyTimeout（Must-14）" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state{fakePersistResult = Left "storage error"}
        _ <- runCollectMarketData ref
        state <- readIORef ref
        case state.publishedFailed of
          [] -> fail "publishMarketCollectFailed was not called"
          (_, reasonCode, _, _) : _ -> reasonCode `shouldBe` DependencyTimeout

      it "保存成功時は publishMarketCollected が呼ばれる" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        state <- readIORef ref
        state.publishCollectedCallCount `shouldBe` 1

    -- TC-UC-008: trace が入力から出力へ伝播
    describe "TC-UC-008: trace の伝播" $ do
      it "publishMarketCollected の trace が入力イベントの trace と一致する" $ do
        ref <- newMockState
        _ <- runCollectMarketData ref
        state <- readIORef ref
        case state.publishedCollected of
          [] -> fail "publishMarketCollected was not called"
          (_, _, traceValue) : _ -> traceValue `shouldBe` fixedTrace

      it "publishMarketCollectFailed の trace が入力イベントの trace と一致する（失敗ケース）" $ do
        ref <- newMockState
        let eventWithoutDate = validRawEvent{targetDate = Nothing, trace = Just fixedTrace}
        _ <-
          runWithMock ref $
            collectMarketData fixedTime fixedIdentifier testApprovedSources testSchemaSpecification eventWithoutDate
        state <- readIORef ref
        case state.publishedFailed of
          [] -> fail "publishMarketCollectFailed was not called"
          (_, _, _, traceValue) : _ -> traceValue `shouldBe` fixedTrace

    -- Must-11: fetchJapanMarketData 失敗時は全体失敗
    describe "Must-11: JP 失敗時の全体失敗" $ do
      it "fetchJapanMarketData が Left のとき CollectionFailed を返す" $ do
        ref <- newMockState
        modifyIORef' ref $ \state ->
          state
            { fakeJapanResult =
                Left
                  FailureDetail
                    { reasonCode = DataSourceTimeout
                    , detail = Nothing
                    , retryable = True
                    }
            }
        result <- runCollectMarketData ref
        result `shouldSatisfy` isCollectionFailed

    -- Must-16: 失敗時に CollectionDispatch が Failed 状態
    describe "Must-16: 失敗時の CollectionDispatch 状態" $ do
      it "失敗後 CollectionDispatch が Failed 状態で persist される" $ do
        ref <- newMockState
        let invalidRecord = RawMarketRecord{fields = [("wrong-field", FieldText "x")]}
        modifyIORef' ref $ \state ->
          state{fakeJapanResult = Right [invalidRecord]}
        _ <- runCollectMarketData ref
        state <- readIORef ref
        let fetchedStatus =
              fmap (.dispatchStatus) $
                Map.lookup (showText fixedIdentifier.value) state.dispatchStore
        fetchedStatus `shouldBe` Just dispatchFailed

    -- Must-18: 失敗時に MarketCollection が Failed 状態
    describe "Must-18: 失敗時の MarketCollection 状態" $ do
      it "失敗後 MarketCollection が Failed 状態で persist される" $ do
        ref <- newMockState
        let invalidRecord = RawMarketRecord{fields = [("wrong-field", FieldText "x")]}
        modifyIORef' ref $ \state ->
          state{fakeJapanResult = Right [invalidRecord]}
        _ <- runCollectMarketData ref
        state <- readIORef ref
        let collectionStatus =
              fmap (.status) $
                Map.lookup (showText fixedIdentifier.value) state.collectionStore
        collectionStatus `shouldBe` Just Failed

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

isCollectionFailedWith :: ReasonCode -> CollectMarketDataResult -> Bool
isCollectionFailedWith expected (CollectionFailed code _) = code == expected
isCollectionFailedWith _ _ = False

isCollectionFailed :: CollectMarketDataResult -> Bool
isCollectionFailed (CollectionFailed _ _) = True
isCollectionFailed _ = False
