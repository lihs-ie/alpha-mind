module UseCase.CollectMarketData (
  -- * Port
  RawMarketDataPort (..),
  CollectionEventPublisher (..),

  -- * Input type
  RawSourceEvent (..),

  -- * Intermediate type
  NormalizedMarketDataset (..),

  -- * Result
  CollectMarketDataResult (..),

  -- * Use case
  collectMarketData,
) where

import Data.Text (Text)
import Data.Time (Day, UTCTime)
import Data.ULID (ulidFromInteger)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  CollectedArtifact,
  CollectionRequestSnapshot (..),
  FailureDetail (..),
  MarketCollection,
  MarketCollectionIdentifier,
  MarketCollectionRepository,
  MarketSourceStatus (..),
  RequestedBy (..),
  SourceStatus (..),
  collectedArtifactRowCount,
  mkCollectedArtifact,
  recordCollectionFailure,
  recordCollectionSuccess,
  startCollection,
 )
import Domain.MarketCollection.Aggregate qualified as MarketCollectionRepo
import Domain.MarketCollection.CollectionDispatch (
  CollectionDispatch,
  CollectionDispatchRepository,
  DispatchStatus (..),
  PublishedEventType (..),
  markDispatchFailed,
  markDispatched,
  startDispatch,
 )
import Domain.MarketCollection.CollectionDispatch qualified as CollectionDispatchRepo
import Domain.MarketCollection.CollectionQualityPolicy (
  MarketSchemaIntegritySpecification,
  RawMarketRecord,
  validateCollectionQuality,
 )
import Domain.MarketCollection.MarketDataSource (MarketDataSource (..))
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Domain.MarketCollection.SourcePolicySpecificationService (
  ApprovedSourceSpecification,
  DataSourceName,
  validateSourcePolicy,
 )
import UseCase.RecordCollectionAudit (
  CollectionAuditEntry (..),
  CollectionAuditPort,
  recordCollectionAudit,
 )
import UseCase.RecordCollectionAudit qualified as AuditResult

-- ---------------------------------------------------------------------
-- Port: RawMarketDataPort (Must-04)
-- ---------------------------------------------------------------------

{- | RawMarketDataPort: 正規化済み市場データを永続化（Parquet/Cloud Storage）する Port。
実装は infra 層（#26）に委ねる。
戻り値: Left errMsg（保存失敗） | Right storagePath（保存成功・パス返却）
-}
class (Monad m) => RawMarketDataPort m where
  persistRawMarketData ::
    MarketCollectionIdentifier ->
    Day ->
    NormalizedMarketDataset ->
    m (Either Text Text)

-- ---------------------------------------------------------------------
-- Port: CollectionEventPublisher (Must-05)
-- ---------------------------------------------------------------------

{- | CollectionEventPublisher: Pub/Sub への市場収集イベント発行 Port。
実装は presentation 層（#28）に委ねる。
-}
class (Monad m) => CollectionEventPublisher m where
  publishMarketCollected ::
    MarketCollectionIdentifier ->
    CollectedArtifact ->
    Trace ->
    m ()
  publishMarketCollectFailed ::
    MarketCollectionIdentifier ->
    ReasonCode ->
    Maybe Text ->
    Trace ->
    m ()

-- ---------------------------------------------------------------------
-- Input type (Must-01)
-- ---------------------------------------------------------------------

{- | RawSourceEvent: Pub/Sub から受信した market.collect.requested ペイロード。
フィールドは全て Maybe — バリデーションをユースケース層で行う（Must-09）。
-}
data RawSourceEvent = RawSourceEvent
  { targetDate :: Maybe Day
  , requestedBy :: Maybe RequestedBy
  , requestedSources :: [DataSourceName]
  , trace :: Maybe Trace
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Intermediate type (Must-04, 設計判断1)
-- ---------------------------------------------------------------------

{- | NormalizedMarketDataset: 正規化された市場データセット（ユースケース層内部型）。
正規化アルゴリズムの実体は infra #26。ユースケース層は型を通過させるのみ。
-}
data NormalizedMarketDataset = NormalizedMarketDataset
  { records :: [RawMarketRecord]
  , rowCount :: Int
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Result (Must-02)
-- ---------------------------------------------------------------------

-- | 収集ユースケースの結果。
data CollectMarketDataResult
  = CollectionSucceeded
  | -- | ReasonCode と retryable フラグ（Must-13）
    CollectionFailed ReasonCode Bool
  | CollectionDuplicate
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case (Must-01)
-- ---------------------------------------------------------------------

{- | UC-DC-01: market.collect.requested イベントを受信し、市場データ収集・正規化・保存・
イベント発行をオーケストレーションする。

処理順序:
1. 冪等性チェック（Must-07）: Published/Failed の CollectionDispatch が存在する → CollectionDuplicate
2. 入力バリデーション（Must-09）: targetDate/requestedBy 欠損 → CollectionFailed RequestValidationFailed
3. ソースポリシー検証（Must-10）: 未承認ソース → CollectionFailed ComplianceSourceUnapproved
4. Dispatch 生成・永続化（Must-08）: Pending CollectionDispatch を persist
5. Collection 生成（startCollection）
6. JP データ収集（Must-11）: JP 失敗 → 全体失敗（MVP gating）
7. スキーマ検証（Must-12）: 失敗 → CollectionFailed DataSchemaInvalid
8. Parquet 保存（Must-14）: 保存後のみ publishMarketCollected
9. CollectedArtifact 構築（Must-15）
10. market.collected 発行 → MarketCollection/CollectionDispatch を Published へ更新（Must-17/19）
11. 失敗時: market.collect.failed 発行 → Failed へ更新（Must-16/18）
12. 監査記録（Must-03/06）
-}
collectMarketData ::
  ( MarketCollectionRepository m
  , CollectionDispatchRepository m
  , MarketDataSource m
  , RawMarketDataPort m
  , CollectionEventPublisher m
  , CollectionAuditPort m
  ) =>
  UTCTime ->
  MarketCollectionIdentifier ->
  ApprovedSourceSpecification ->
  MarketSchemaIntegritySpecification ->
  RawSourceEvent ->
  m CollectMarketDataResult
collectMarketData currentTime collectionIdentifier approvedSources schemaSpecification rawEvent = do
  -- Must-07: 冪等性チェック
  existingDispatch <- CollectionDispatchRepo.find collectionIdentifier
  case existingDispatch of
    Just dispatch
      | dispatch.dispatchStatus == Published || dispatch.dispatchStatus == Failed ->
          pure CollectionDuplicate
    _ -> processNewCollection currentTime collectionIdentifier approvedSources schemaSpecification rawEvent

-- | 冪等チェック通過後の収集処理本体。
processNewCollection ::
  ( MarketCollectionRepository m
  , CollectionDispatchRepository m
  , MarketDataSource m
  , RawMarketDataPort m
  , CollectionEventPublisher m
  , CollectionAuditPort m
  ) =>
  UTCTime ->
  MarketCollectionIdentifier ->
  ApprovedSourceSpecification ->
  MarketSchemaIntegritySpecification ->
  RawSourceEvent ->
  m CollectMarketDataResult
processNewCollection currentTime collectionIdentifier approvedSources schemaSpecification rawEvent = do
  -- Must-09: 入力バリデーション
  case validateRawSourceEvent rawEvent of
    Left failureReasonCode -> do
      let traceValue = resolveTrace rawEvent
      publishMarketCollectFailed collectionIdentifier failureReasonCode Nothing traceValue
      pure (CollectionFailed failureReasonCode False)
    Right snapshot -> do
      -- Must-10: ソースポリシー検証
      let traceValue = resolveTrace rawEvent
      case validateSourcePolicy approvedSources rawEvent.requestedSources of
        Left policyReasonCode -> do
          publishMarketCollectFailed collectionIdentifier policyReasonCode Nothing traceValue
          pure (CollectionFailed policyReasonCode False)
        Right () -> do
          -- Must-08: Dispatch 生成・永続化（Pending）
          let dispatch = startDispatch collectionIdentifier traceValue
          CollectionDispatchRepo.persist dispatch

          -- Collection 集約生成
          let (collection, _startEvents) = startCollection collectionIdentifier snapshot traceValue

          -- 収集・検証・保存・発行
          runCollection currentTime collectionIdentifier snapshot schemaSpecification collection dispatch

-- | ソースポリシー通過後の収集フロー本体。
runCollection ::
  ( MarketCollectionRepository m
  , CollectionDispatchRepository m
  , MarketDataSource m
  , RawMarketDataPort m
  , CollectionEventPublisher m
  , CollectionAuditPort m
  ) =>
  UTCTime ->
  MarketCollectionIdentifier ->
  CollectionRequestSnapshot ->
  MarketSchemaIntegritySpecification ->
  MarketCollection ->
  CollectionDispatch ->
  m CollectMarketDataResult
runCollection currentTime collectionIdentifier snapshot schemaSpecification collection dispatch = do
  -- Must-11: JP データ収集（MVP gating）
  jpResult <- fetchJapanMarketData snapshot.targetDate

  -- US は MVP では未収集（usCollectionEnabled=false）→ us = Ok
  let usStatus = Ok

  case jpResult of
    Left failureDetail -> do
      -- JP 失敗 → 全体失敗
      let jpStatus = SourceFailed
          sourceStatus = SourceStatus{jp = jpStatus, us = usStatus}
          failureReasonCode = failureDetail.reasonCode
          failureDetailText = failureDetail.detail
          isRetryable = failureDetail.retryable
      handleCollectionFailure
        currentTime
        collectionIdentifier
        snapshot
        sourceStatus
        failureReasonCode
        failureDetailText
        isRetryable
        collection
        dispatch
    Right jpRecords -> do
      -- Must-12: スキーマ検証
      case validateCollectionQuality schemaSpecification jpRecords of
        Left qualityReasonCode -> do
          let jpStatus = SourceFailed
              sourceStatus = SourceStatus{jp = jpStatus, us = usStatus}
          handleCollectionFailure
            currentTime
            collectionIdentifier
            snapshot
            sourceStatus
            qualityReasonCode
            Nothing
            False
            collection
            dispatch
        Right () -> do
          -- Must-14: Parquet 保存（保存成功後のみ publishMarketCollected）
          let jpStatus = Ok
              sourceStatus = SourceStatus{jp = jpStatus, us = usStatus}
              normalizedDataset =
                NormalizedMarketDataset
                  { records = jpRecords
                  , rowCount = length jpRecords
                  }
          persistResult <- persistRawMarketData collectionIdentifier snapshot.targetDate normalizedDataset
          case persistResult of
            Left storageError -> do
              -- 保存失敗 → 依存インフラの一時障害（Must-14）→ DependencyTimeout / retryable=True
              handleCollectionFailure
                currentTime
                collectionIdentifier
                snapshot
                sourceStatus
                DependencyTimeout
                (Just storageError)
                True
                collection
                dispatch
            Right storagePath -> do
              -- Must-15: CollectedArtifact 構築
              case mkCollectedArtifact snapshot.targetDate storagePath sourceStatus (length jpRecords) of
                Left _domainError -> do
                  -- mkCollectedArtifact が Left を返す（内部矛盾）→ 再試行不可（Must-14）
                  handleCollectionFailure
                    currentTime
                    collectionIdentifier
                    snapshot
                    sourceStatus
                    StateConflict
                    Nothing
                    False
                    collection
                    dispatch
                Right artifact -> do
                  handleCollectionSuccess
                    currentTime
                    collectionIdentifier
                    snapshot
                    storagePath
                    sourceStatus
                    artifact
                    collection
                    dispatch

-- | 収集成功時の後処理（Must-17, Must-19, Must-14）。
handleCollectionSuccess ::
  ( MarketCollectionRepository m
  , CollectionDispatchRepository m
  , CollectionEventPublisher m
  , CollectionAuditPort m
  ) =>
  UTCTime ->
  MarketCollectionIdentifier ->
  CollectionRequestSnapshot ->
  Text ->
  SourceStatus ->
  CollectedArtifact ->
  MarketCollection ->
  CollectionDispatch ->
  m CollectMarketDataResult
handleCollectionSuccess currentTime collectionIdentifier snapshot storagePath sourceStatus artifact collection dispatch = do
  -- Must-17: MarketCollection を Collected へ更新・永続化
  case recordCollectionSuccess storagePath sourceStatus (collectedArtifactRowCount artifact) currentTime collection of
    Left _domainError ->
      -- 状態遷移失敗（想定外）→ 失敗経路へ
      handleCollectionFailure
        currentTime
        collectionIdentifier
        snapshot
        sourceStatus
        StateConflict
        Nothing
        False
        collection
        dispatch
    Right (updatedCollection, _events) -> do
      MarketCollectionRepo.persist updatedCollection

      -- Must-14: 保存成功後のみ publishMarketCollected
      -- Must-05: trace を伝播
      publishMarketCollected collectionIdentifier artifact updatedCollection.trace

      -- Must-19: CollectionDispatch を Published へ遷移・永続化
      case markDispatched MarketCollected currentTime dispatch of
        Left _domainError ->
          -- 状態遷移失敗（想定外）→ そのまま Succeeded を返す（Dispatch の更新失敗は非致命的）
          pure CollectionSucceeded
        Right publishedDispatch -> do
          CollectionDispatchRepo.persist publishedDispatch

          -- 監査記録（Must-03）
          let auditEntry =
                CollectionAuditEntry
                  { result = AuditResult.Succeeded
                  , reasonCode = Nothing
                  , targetDate = snapshot.targetDate
                  , sourceStatus = Just sourceStatus
                  }
          recordCollectionAudit collectionIdentifier updatedCollection.trace auditEntry

          pure CollectionSucceeded

-- | 収集失敗時の後処理（Must-16, Must-18）。
handleCollectionFailure ::
  ( MarketCollectionRepository m
  , CollectionDispatchRepository m
  , CollectionEventPublisher m
  , CollectionAuditPort m
  ) =>
  UTCTime ->
  MarketCollectionIdentifier ->
  CollectionRequestSnapshot ->
  SourceStatus ->
  ReasonCode ->
  Maybe Text ->
  Bool ->
  MarketCollection ->
  CollectionDispatch ->
  m CollectMarketDataResult
handleCollectionFailure currentTime collectionIdentifier snapshot _sourceStatus failureReasonCode failureDetailText isRetryable collection dispatch = do
  -- Must-16: market.collect.failed 発行（reasonCode 必須）
  publishMarketCollectFailed collectionIdentifier failureReasonCode failureDetailText collection.trace

  -- Must-18: MarketCollection を Failed へ更新・永続化
  case recordCollectionFailure failureReasonCode failureDetailText currentTime collection of
    Left _domainError ->
      -- 状態遷移失敗（想定外）→ 継続（CollectionDispatch の更新は試みる）
      pure ()
    Right (failedCollection, _events) ->
      MarketCollectionRepo.persist failedCollection

  -- Must-16: CollectionDispatch を Failed へ遷移・永続化
  case markDispatchFailed failureReasonCode currentTime dispatch of
    Left _domainError ->
      pure ()
    Right failedDispatch ->
      CollectionDispatchRepo.persist failedDispatch

  -- 監査記録（Must-03）
  let auditEntry =
        CollectionAuditEntry
          { result = AuditResult.Failed
          , reasonCode = Just failureReasonCode
          , targetDate = snapshot.targetDate
          , sourceStatus = Nothing
          }
  recordCollectionAudit collectionIdentifier collection.trace auditEntry

  pure (CollectionFailed failureReasonCode isRetryable)

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

{- | RawSourceEvent からバリデーション済み CollectionRequestSnapshot を構築する。
targetDate または requestedBy が Nothing の場合は Left RequestValidationFailed を返す（Must-09）。
-}
validateRawSourceEvent :: RawSourceEvent -> Either ReasonCode CollectionRequestSnapshot
validateRawSourceEvent event =
  case (event.targetDate, event.requestedBy) of
    (Nothing, _) -> Left RequestValidationFailed
    (_, Nothing) -> Left RequestValidationFailed
    (Just date, Just requester) ->
      Right
        CollectionRequestSnapshot
          { targetDate = date
          , requestedBy = requester
          , mode = Nothing
          }

{- | RawSourceEvent から Trace を取り出す。trace が Nothing の場合はゼロ値 ULID でフォールバック。
バリデーション失敗時の publishMarketCollectFailed で使うため、エラーにしない。
-}
resolveTrace :: RawSourceEvent -> Trace
resolveTrace event = case event.trace of
  Just traceValue -> traceValue
  Nothing ->
    -- trace 欠損は稀な想定外ケース。ゼロ値 ULID でフォールバック。
    case ulidFromInteger 0 of
      Right zeroUlid -> Trace zeroUlid
      Left _ -> error "resolveTrace: ulidFromInteger 0 must not fail"
