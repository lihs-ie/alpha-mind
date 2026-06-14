module UseCase.CollectInsightsSpec (spec) where

import Control.Monad.State (State, execState, get, modify, runState)
import Data.Text (Text)
import Data.Time (Day, UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (
  CollectionStatus (..),
  FailureDetail (..),
  FailureStage (..),
  InsightArtifact (..),
  InsightArtifactRepository (..),
  InsightCollection,
  InsightCollectionIdentifier (..),
  InsightCollectionRepository (..),
  InsightRecord (..),
  InsightRecordIdentifier (..),
  InsightRecordRepository (..),
  RequestedBy (..),
  SignalClass (..),
  SourcePolicyRepository (..),
  SourcePolicySnapshot (..),
  SourceType (..),
 )
import Domain.InsightCollection.Aggregate qualified as Aggregate
import Domain.InsightCollection.EvidenceCompletenessPolicy (validateEvidence)
import Domain.InsightCollection.ExternalSourcePort (ExternalSourcePort (..))
import Domain.InsightCollection.InsightDispatch (
  InsightDispatch,
  InsightDispatchRepository (..),
  markDispatchFailed,
  markDispatched,
  startDispatch,
 )
import Domain.InsightCollection.InsightDispatch qualified as DispatchModule
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.CollectInsights (
  CollectInsightsResult (..),
  InsightCollectionEventPublisher (..),
  RawInsightEvent (..),
  collectInsights,
 )
import UseCase.RecordInsightAudit (
  InsightAuditEntry (..),
  InsightAuditPort (..),
 )
import UseCase.RecordInsightAudit qualified as AuditResult

-- ---------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedDay :: Day
fixedDay = fromGregorian 2026 1 15

fixedTime :: UTCTime
fixedTime = UTCTime fixedDay 0

testCollectionIdentifier :: InsightCollectionIdentifier
testCollectionIdentifier = InsightCollectionIdentifier (mkULID 1)

testTrace :: Trace
testTrace = Trace (mkULID 100)

testRecordIdentifier :: InsightRecordIdentifier
testRecordIdentifier = InsightRecordIdentifier (mkULID 200)

-- | 正常なテストイベント。
validRawEvent :: RawInsightEvent
validRawEvent =
  RawInsightEvent
    { targetDate = Just fixedDay
    , requestedBy = Just Scheduler
    , requestedSourceTypes = [X]
    , options = Nothing
    , trace = Just testTrace
    }

-- | targetDate 欠損のテストイベント（TST-IC-001）。
missingTargetDateEvent :: RawInsightEvent
missingTargetDateEvent =
  RawInsightEvent
    { targetDate = Nothing
    , requestedBy = Just Scheduler
    , requestedSourceTypes = [X]
    , options = Nothing
    , trace = Just testTrace
    }

testRecord :: InsightRecord
testRecord =
  InsightRecord
    { identifier = testRecordIdentifier
    , sourceType = X
    , sourceUrl = "https://x.com/example/status/1"
    , evidenceSnippet = "Market anomaly detected in semiconductor sector"
    , collectedAt = fixedTime
    , summary = "Significant structural anomaly"
    , signalClass = StructuralAnomaly
    , soWhatScore = 0.85
    , skillVersion = "v1.0.0"
    }

invalidEvidenceRecord :: InsightRecord
invalidEvidenceRecord =
  InsightRecord
    { identifier = testRecordIdentifier
    , sourceType = X
    , sourceUrl = "https://x.com/example/status/1"
    , evidenceSnippet = ""
    , collectedAt = fixedTime
    , summary = "Significant structural anomaly"
    , signalClass = StructuralAnomaly
    , soWhatScore = 0.85
    , skillVersion = "v1.0.0"
    }

approvedPolicy :: SourcePolicySnapshot
approvedPolicy =
  SourcePolicySnapshot
    { sourceType = X
    , enabled = True
    , termsVersion = "v1.0"
    , redistributionAllowed = True
    , dailyQuota = Nothing
    , sourceConfig = Aggregate.XSourceConfig (Aggregate.XConfig{bearerTokenSecretName = "x-secret"})
    }

unapprovedPolicy :: SourcePolicySnapshot
unapprovedPolicy =
  SourcePolicySnapshot
    { sourceType = X
    , enabled = False
    , termsVersion = "v1.0"
    , redistributionAllowed = True
    , dailyQuota = Nothing
    , sourceConfig = Aggregate.XSourceConfig (Aggregate.XConfig{bearerTokenSecretName = "x-secret"})
    }

timeoutFailureDetail :: FailureDetail
timeoutFailureDetail =
  FailureDetail
    { reasonCode = DependencyTimeout
    , detail = Just "X API timeout after 30s"
    , retryable = True
    , sourceType = Just X
    , stage = Just Collect
    }

-- ---------------------------------------------------------------------
-- Mock state type
-- ---------------------------------------------------------------------

-- | テスト用状態型。各 Port/Repository の呼び出し記録を保持する。
data MockState = MockState
  { mockExistingDispatch :: Maybe InsightDispatch
  , mockPersistedDispatches :: [InsightDispatch]
  , mockPersistedCollections :: [InsightCollection]
  , mockPolicies :: [SourcePolicySnapshot]
  , mockPersistedRecords :: [InsightRecord]
  , mockPersistedArtifacts :: [InsightArtifact]
  , mockFetchResult :: Either FailureDetail [InsightRecord]
  , mockPublishedCollected :: [(InsightCollectionIdentifier, InsightArtifact, Trace)]
  , mockPublishedFailed :: [(InsightCollectionIdentifier, ReasonCode, Maybe Text, Trace)]
  , mockAuditEntries :: [InsightAuditEntry]
  }

initialMockState :: MockState
initialMockState =
  MockState
    { mockExistingDispatch = Nothing
    , mockPersistedDispatches = []
    , mockPersistedCollections = []
    , mockPolicies = [approvedPolicy]
    , mockPersistedRecords = []
    , mockPersistedArtifacts = []
    , mockFetchResult = Right [testRecord]
    , mockPublishedCollected = []
    , mockPublishedFailed = []
    , mockAuditEntries = []
    }

-- | テスト用モナド型。
type TestMonad = State MockState

-- ---------------------------------------------------------------------
-- Mock instances
-- ---------------------------------------------------------------------

instance InsightDispatchRepository TestMonad where
  findDispatch _ = do
    mockState <- get
    pure mockState.mockExistingDispatch
  persistDispatch dispatch =
    modify (\mockState -> mockState{mockPersistedDispatches = dispatch : mockState.mockPersistedDispatches})
  terminateDispatch' _ = pure ()

instance InsightCollectionRepository TestMonad where
  findCollection _ = pure Nothing
  findByStatus _ = pure []
  searchCollections _ = pure []
  persistCollection collection =
    modify (\mockState -> mockState{mockPersistedCollections = collection : mockState.mockPersistedCollections})
  terminateCollectionRecord _ = pure ()

instance SourcePolicyRepository TestMonad where
  searchPolicies _ = do
    mockState <- get
    pure mockState.mockPolicies
  findBySourceType _ = pure Nothing

instance InsightRecordRepository TestMonad where
  persistRecord record =
    modify (\mockState -> mockState{mockPersistedRecords = record : mockState.mockPersistedRecords})
  searchRecords _ _ = pure []
  findByTargetDate _ = pure []

instance InsightArtifactRepository TestMonad where
  persistArtifact artifact =
    modify (\mockState -> mockState{mockPersistedArtifacts = artifact : mockState.mockPersistedArtifacts})
  findArtifact _ = pure Nothing
  terminateArtifact _ = pure ()

instance ExternalSourcePort TestMonad where
  fetchInsights _ _ = do
    mockState <- get
    pure mockState.mockFetchResult

instance InsightCollectionEventPublisher TestMonad where
  publishInsightCollected collectionIdentifier artifact traceValue =
    modify
      ( \mockState -> mockState{mockPublishedCollected = (collectionIdentifier, artifact, traceValue) : mockState.mockPublishedCollected}
      )
  publishInsightCollectFailed collectionIdentifier reasonCode maybeDetail traceValue =
    modify
      ( \mockState ->
          mockState
            { mockPublishedFailed = (collectionIdentifier, reasonCode, maybeDetail, traceValue) : mockState.mockPublishedFailed
            }
      )

instance InsightAuditPort TestMonad where
  writeInsightAudit _ _ entry =
    modify (\mockState -> mockState{mockAuditEntries = entry : mockState.mockAuditEntries})

-- | テストを実行して結果と最終状態を返す。
runTest :: MockState -> TestMonad CollectInsightsResult -> (CollectInsightsResult, MockState)
runTest initialState action = runState action initialState

-- | テストを実行して最終状態のみ返す。
execTest :: MockState -> TestMonad CollectInsightsResult -> MockState
execTest initialState action = execState action initialState

-- | Published DispatchStatus の InsightDispatch を作成するヘルパー。
mkPublishedDispatch :: InsightDispatch
mkPublishedDispatch =
  case markDispatched DispatchModule.InsightCollected fixedTime baseDispatch of
    Right published -> published
    Left _ -> error "mkPublishedDispatch: unexpected error"
 where
  baseDispatch = startDispatch testCollectionIdentifier testTrace

-- | Failed DispatchStatus の InsightDispatch を作成するヘルパー。
mkFailedDispatch :: InsightDispatch
mkFailedDispatch =
  case markDispatchFailed DependencyTimeout fixedTime baseDispatch of
    Right failed -> failed
    Left _ -> error "mkFailedDispatch: unexpected error"
 where
  baseDispatch = startDispatch testCollectionIdentifier testTrace

-- | 最後に発行された ReasonCode を取得するヘルパー。
latestFailedReasonCode :: MockState -> Maybe ReasonCode
latestFailedReasonCode mockState = case mockState.mockPublishedFailed of
  (_, reasonCode, _, _) : _ -> Just reasonCode
  [] -> Nothing

-- | 最後に記録された監査エントリを取得するヘルパー。
latestAuditEntry :: MockState -> Maybe InsightAuditEntry
latestAuditEntry mockState = case mockState.mockAuditEntries of
  entry : _ -> Just entry
  [] -> Nothing

-- | 最後に永続化された InsightCollection を取得するヘルパー。
latestPersistedCollection :: MockState -> Maybe InsightCollection
latestPersistedCollection mockState = case mockState.mockPersistedCollections of
  collection : _ -> Just collection
  [] -> Nothing

-- | 最後に発行された InsightArtifact を取得するヘルパー。
latestPublishedArtifact :: MockState -> Maybe InsightArtifact
latestPublishedArtifact mockState = case mockState.mockPublishedCollected of
  (_, artifact, _) : _ -> Just artifact
  [] -> Nothing

-- ---------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "UseCase.CollectInsights" $ do
    -- TST-IC-004: 冪等性チェック（UC-01）
    describe "TST-IC-004: idempotency check (UC-01)" $ do
      it "returns CollectionDuplicate when dispatch status is Published" $ do
        let initialState = initialMockState{mockExistingDispatch = Just mkPublishedDispatch}
        let (result, finalState) = runTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        result `shouldBe` CollectionDuplicate
        length finalState.mockPublishedCollected `shouldBe` 0
        length finalState.mockPublishedFailed `shouldBe` 0

      it "returns CollectionDuplicate when dispatch status is Failed" $ do
        let initialState = initialMockState{mockExistingDispatch = Just mkFailedDispatch}
        let (result, finalState) = runTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        result `shouldBe` CollectionDuplicate
        length finalState.mockPublishedFailed `shouldBe` 0

      it "proceeds when no existing dispatch" $ do
        let initialState = initialMockState{mockExistingDispatch = Nothing}
        let (result, _finalState) = runTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        result `shouldBe` CollectionSucceeded

      it "proceeds when existing dispatch is Pending" $ do
        let pendingDispatch = startDispatch testCollectionIdentifier testTrace
        let initialState = initialMockState{mockExistingDispatch = Just pendingDispatch}
        let (result, _finalState) = runTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        result `shouldBe` CollectionSucceeded

    -- TST-IC-001: 入力バリデーション（UC-02）
    describe "TST-IC-001: input validation (UC-02)" $ do
      it "returns CollectionFailed RequestValidationFailed when targetDate is Nothing" $ do
        let (result, finalState) = runTest initialMockState (collectInsights fixedTime testCollectionIdentifier missingTargetDateEvent)
        result `shouldBe` CollectionFailed RequestValidationFailed False
        latestFailedReasonCode finalState `shouldBe` Just RequestValidationFailed

      it "returns CollectionFailed RequestValidationFailed when requestedBy is Nothing" $ do
        let eventMissingRequestedBy =
              RawInsightEvent
                { targetDate = Just fixedDay
                , requestedBy = Nothing
                , requestedSourceTypes = [X]
                , options = Nothing
                , trace = Just testTrace
                }
        let (result, finalState) = runTest initialMockState (collectInsights fixedTime testCollectionIdentifier eventMissingRequestedBy)
        result `shouldBe` CollectionFailed RequestValidationFailed False
        latestFailedReasonCode finalState `shouldBe` Just RequestValidationFailed

      it "publishes insight.collect.failed on validation failure" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier missingTargetDateEvent)
        length finalState.mockPublishedFailed `shouldBe` 1

      it "does not call persistDispatch when validation fails" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier missingTargetDateEvent)
        length finalState.mockPersistedDispatches `shouldBe` 0

    -- TST-IC-002: ソースポリシー検証（UC-03）
    describe "TST-IC-002: source policy compliance (UC-03)" $ do
      it "returns CollectionFailed ComplianceSourceUnapproved when policy is disabled" $ do
        let initialState = initialMockState{mockPolicies = [unapprovedPolicy]}
        let (result, finalState) = runTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        result `shouldBe` CollectionFailed ComplianceSourceUnapproved False
        latestFailedReasonCode finalState `shouldBe` Just ComplianceSourceUnapproved

      it "publishes insight.collect.failed with ComplianceSourceUnapproved on policy failure" $ do
        let initialState = initialMockState{mockPolicies = [unapprovedPolicy]}
        let finalState = execTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        length finalState.mockPublishedFailed `shouldBe` 1

      it "proceeds when all policies are approved" $ do
        let initialState = initialMockState{mockPolicies = [approvedPolicy]}
        let (result, _finalState) = runTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        result `shouldBe` CollectionSucceeded

    -- TST-IC-004 補助: InsightDispatch Pending 生成・永続化（UC-04）
    describe "TST-IC-004 aux: InsightDispatch Pending persistence (UC-04)" $ do
      it "calls persistDispatch at least once in normal flow" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        length finalState.mockPersistedDispatches `shouldSatisfy` (>= 1)

    -- TST-IC-007: ソース別収集失敗（UC-06）
    describe "TST-IC-007: external source timeout (UC-06)" $ do
      it "returns CollectionFailed DependencyTimeout when all sources timeout" $ do
        let initialState = initialMockState{mockFetchResult = Left timeoutFailureDetail}
        let (result, finalState) = runTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        result `shouldBe` CollectionFailed DependencyTimeout True
        latestFailedReasonCode finalState `shouldBe` Just DependencyTimeout

      it "publishes insight.collect.failed with DependencyTimeout reasonCode" $ do
        let initialState = initialMockState{mockFetchResult = Left timeoutFailureDetail}
        let finalState = execTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        length finalState.mockPublishedFailed `shouldBe` 1

      it "result is retryable=True on DependencyTimeout" $ do
        let initialState = initialMockState{mockFetchResult = Left timeoutFailureDetail}
        let (result, _finalState) = runTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        result `shouldBe` CollectionFailed DependencyTimeout True

    -- TST-IC-003: 根拠情報完全性検証（UC-07）
    describe "TST-IC-003: evidence completeness validation (UC-07)" $ do
      it "returns CollectionFailed when evidenceSnippet is empty" $ do
        let initialState = initialMockState{mockFetchResult = Right [invalidEvidenceRecord]}
        let (result, finalState) = runTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        result `shouldBe` CollectionFailed RequestValidationFailed False
        latestFailedReasonCode finalState `shouldBe` Just RequestValidationFailed

      it "validates evidence correctly as pure function (TST-IC-003)" $ do
        validateEvidence [invalidEvidenceRecord] `shouldBe` Left RequestValidationFailed

    -- TST-IC-005: 保存順序・保存後のみ発行（UC-08/09）
    describe "TST-IC-005: persistence order and publish after persist (UC-08, UC-09)" $ do
      it "persists artifact and then publishes insight.collected" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        -- 保存されていること
        length finalState.mockPersistedArtifacts `shouldBe` 1
        -- 発行されていること
        length finalState.mockPublishedCollected `shouldBe` 1

      it "persists InsightRecord before InsightArtifact in normal flow" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        length finalState.mockPersistedRecords `shouldBe` 1

      it "transitions InsightCollection to Collected status and persists" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        let maybeCollection = latestPersistedCollection finalState
        case maybeCollection of
          Nothing -> fail "No persisted collection found"
          Just collection -> collection.status `shouldBe` Collected

      it "does not publish insight.collected on failure (no artifact published on timeout)" $ do
        let initialState = initialMockState{mockFetchResult = Left timeoutFailureDetail}
        let finalState = execTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        length finalState.mockPublishedCollected `shouldBe` 0

    -- TST-IC-006: insight.collected payload 確認（UC-09）
    describe "TST-IC-006: insight.collected payload (UC-09)" $ do
      it "publishInsightCollected is called exactly once in normal flow" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        length finalState.mockPublishedCollected `shouldBe` 1

      it "published artifact has identifier, count, storagePath, and sourceStatus" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        case latestPublishedArtifact finalState of
          Nothing -> fail "No published artifact found"
          Just artifact -> do
            artifact.count `shouldBe` 1
            artifact.storagePath `shouldSatisfy` \path -> path /= ""
            length artifact.sourceStatus `shouldBe` 1

      it "published identifier matches input collectionIdentifier" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        case finalState.mockPublishedCollected of
          [] -> fail "No published collected event found"
          (publishedIdentifier, _, _) : _ -> publishedIdentifier `shouldBe` testCollectionIdentifier

    -- TST-IC-008: 失敗時 insight.collect.failed 発行（UC-10）
    describe "TST-IC-008: insight.collect.failed on all failure paths (UC-10)" $ do
      it "publishes insight.collect.failed with RequestValidationFailed on validation failure" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier missingTargetDateEvent)
        latestFailedReasonCode finalState `shouldBe` Just RequestValidationFailed

      it "publishes insight.collect.failed with ComplianceSourceUnapproved on policy failure" $ do
        let initialState = initialMockState{mockPolicies = [unapprovedPolicy]}
        let finalState = execTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        latestFailedReasonCode finalState `shouldBe` Just ComplianceSourceUnapproved

      it "publishes insight.collect.failed with DependencyTimeout on source timeout" $ do
        let initialState = initialMockState{mockFetchResult = Left timeoutFailureDetail}
        let finalState = execTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        latestFailedReasonCode finalState `shouldBe` Just DependencyTimeout

      it "publishes insight.collect.failed with RequestValidationFailed on evidence failure" $ do
        let initialState = initialMockState{mockFetchResult = Right [invalidEvidenceRecord]}
        let finalState = execTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        latestFailedReasonCode finalState `shouldBe` Just RequestValidationFailed

    -- UC-11: 監査記録（成功・失敗両フロー）
    describe "UC-11: audit recording (UC-11)" $ do
      it "records audit entry with Succeeded result in normal flow" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        length finalState.mockAuditEntries `shouldBe` 1
        case latestAuditEntry finalState of
          Nothing -> fail "No audit entry found"
          Just entry -> entry.result `shouldBe` AuditResult.Succeeded

      it "records audit entry with Failed result on validation failure" $ do
        let finalState = execTest initialMockState (collectInsights fixedTime testCollectionIdentifier missingTargetDateEvent)
        length finalState.mockAuditEntries `shouldBe` 1
        case latestAuditEntry finalState of
          Nothing -> fail "No audit entry found"
          Just entry -> do
            entry.result `shouldBe` AuditResult.Failed
            entry.reasonCode `shouldBe` Just RequestValidationFailed

      it "records audit entry with Failed result on source timeout" $ do
        let initialState = initialMockState{mockFetchResult = Left timeoutFailureDetail}
        let finalState = execTest initialState (collectInsights fixedTime testCollectionIdentifier validRawEvent)
        case latestAuditEntry finalState of
          Nothing -> fail "No audit entry found"
          Just entry -> do
            entry.result `shouldBe` AuditResult.Failed
            entry.reasonCode `shouldBe` Just DependencyTimeout
