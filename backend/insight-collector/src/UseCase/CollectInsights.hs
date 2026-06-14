module UseCase.CollectInsights (
  -- * Port
  InsightCollectionEventPublisher (..),

  -- * Input type
  RawInsightEvent (..),

  -- * Result
  CollectInsightsResult (..),

  -- * Use case
  collectInsights,
) where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (Day, UTCTime)
import Data.ULID (ulidFromInteger)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (
  CollectionOptions,
  FailureDetail (..),
  FailureStage (..),
  InsightArtifact (..),
  InsightArtifactRepository (..),
  InsightCollection,
  InsightCollectionIdentifier,
  InsightCollectionRepository (..),
  InsightCollectionRequestSnapshot (..),
  InsightRecord,
  InsightRecordRepository (..),
  RequestedBy,
  SourceCollectionStatus (..),
  SourceOutcome (..),
  SourcePolicyRepository (..),
  SourcePolicySnapshot (..),
  SourceType,
  mkInsightCollectionRequestSnapshot,
  recordCollectionFailure,
  recordCollectionSuccess,
  startCollection,
 )
import Domain.InsightCollection.EvidenceCompletenessPolicy (validateEvidence)
import Domain.InsightCollection.ExternalSourcePort (ExternalSourcePort (..))
import Domain.InsightCollection.InsightDispatch (
  DispatchStatus (..),
  InsightDispatch,
  InsightDispatchRepository (..),
  PublishedEventType (..),
  markDispatchFailed,
  markDispatched,
  startDispatch,
 )
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Domain.InsightCollection.SourcePolicyComplianceService (validateSourcePolicy)
import UseCase.RecordInsightAudit (
  InsightAuditEntry (..),
  InsightAuditPort,
  InsightAuditResult,
  recordInsightAudit,
 )
import UseCase.RecordInsightAudit qualified as AuditResult

-- ---------------------------------------------------------------------
-- Port: InsightCollectionEventPublisher (UC-09, UC-10)
-- ---------------------------------------------------------------------

{- | InsightCollectionEventPublisher: Pub/Sub へのインサイト収集イベント発行 Port。
実装は presentation 層（Issue #55）に委ねる。
-}
class (Monad m) => InsightCollectionEventPublisher m where
  publishInsightCollected ::
    InsightCollectionIdentifier ->
    InsightArtifact ->
    Trace ->
    m ()
  publishInsightCollectFailed ::
    InsightCollectionIdentifier ->
    ReasonCode ->
    Maybe Text ->
    Trace ->
    m ()

-- ---------------------------------------------------------------------
-- Input type (UC-02)
-- ---------------------------------------------------------------------

{- | RawInsightEvent: Pub/Sub から受信した insight.collect.requested ペイロード。
フィールドは全て Maybe — バリデーションをユースケース層で行う（UC-02）。
-}
data RawInsightEvent = RawInsightEvent
  { targetDate :: Maybe Day
  , requestedBy :: Maybe RequestedBy
  , requestedSourceTypes :: [SourceType]
  , options :: Maybe CollectionOptions
  , trace :: Maybe Trace
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Result (UC-01)
-- ---------------------------------------------------------------------

-- | インサイト収集ユースケースの結果。
data CollectInsightsResult
  = CollectionSucceeded
  | -- | ReasonCode と retryable フラグ
    CollectionFailed ReasonCode Bool
  | CollectionDuplicate
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case entry point
-- ---------------------------------------------------------------------

{- | collectInsights: insight.collect.requested イベントを受信し、
許可ソースからインサイトを収集・正規化・保存・イベント発行をオーケストレーションする。

処理順序:
1. 冪等性チェック（UC-01）: Published/Failed の InsightDispatch が存在する → CollectionDuplicate
2. 入力バリデーション（UC-02）: targetDate/requestedBy 欠損 → CollectionFailed RequestValidationFailed
3. ソースポリシー解決（UC-03）: searchPolicies で全ポリシー取得
4. ソースポリシー検証（UC-03）: validateSourcePolicy — 未承認ソース → CollectionFailed ComplianceSourceUnapproved
5. InsightDispatch 生成・永続化（UC-04）: Pending InsightDispatch を persist
6. InsightCollection Aggregate 生成（UC-05）: startCollection
7. ソース別インサイト収集（UC-06）: ExternalSourcePort.fetchInsights per policy
8. 根拠情報完全性検証（UC-07）: validateEvidence
9. 保存（UC-08）: persistRecord / persistArtifact / persistCollection
10. insight.collected 発行（UC-09）: 保存後のみ
11. 失敗時（UC-10）: insight.collect.failed 発行
12. 監査記録（UC-11）: 成功・失敗いずれの終端でも recordInsightAudit
-}
collectInsights ::
  ( InsightDispatchRepository m
  , InsightCollectionRepository m
  , SourcePolicyRepository m
  , InsightRecordRepository m
  , InsightArtifactRepository m
  , ExternalSourcePort m
  , InsightCollectionEventPublisher m
  , InsightAuditPort m
  ) =>
  UTCTime ->
  InsightCollectionIdentifier ->
  RawInsightEvent ->
  m CollectInsightsResult
collectInsights currentTime collectionIdentifier rawEvent = do
  -- UC-01: 冪等性チェック
  existingDispatch <- findDispatch collectionIdentifier
  case existingDispatch of
    Just dispatch
      | dispatch.dispatchStatus == Published || dispatch.dispatchStatus == Failed ->
          pure CollectionDuplicate
    _ -> processNewCollection currentTime collectionIdentifier rawEvent

-- | 冪等チェック通過後の収集処理本体。
processNewCollection ::
  ( InsightDispatchRepository m
  , InsightCollectionRepository m
  , SourcePolicyRepository m
  , InsightRecordRepository m
  , InsightArtifactRepository m
  , ExternalSourcePort m
  , InsightCollectionEventPublisher m
  , InsightAuditPort m
  ) =>
  UTCTime ->
  InsightCollectionIdentifier ->
  RawInsightEvent ->
  m CollectInsightsResult
processNewCollection currentTime collectionIdentifier rawEvent = do
  let traceValue = resolveTrace rawEvent
  -- UC-02: 入力バリデーション
  case validateRawInsightEvent rawEvent of
    Left failureReasonCode -> do
      publishInsightCollectFailed collectionIdentifier failureReasonCode Nothing traceValue
      -- UC-11: 監査記録（バリデーション失敗）
      -- targetDate が欠損している可能性があるため rawEvent から抽出できた値を使用
      let RawInsightEvent{targetDate = maybeRawTargetDate} = rawEvent
      let auditTargetDate = resolveAuditTargetDate maybeRawTargetDate
      let auditEntry =
            InsightAuditEntry
              { result = AuditResult.Failed
              , reasonCode = Just failureReasonCode
              , targetDate = auditTargetDate
              , sourceStatus = Nothing
              }
      recordInsightAudit collectionIdentifier traceValue auditEntry
      pure (CollectionFailed failureReasonCode False)
    Right snapshot -> do
      let InsightCollectionRequestSnapshot{sourceTypes = snapshotSourceTypes, targetDate = snapshotTargetDate} = snapshot
      -- UC-03: ソースポリシー解決
      -- sourceTypes が空の場合は searchPolicies が enabled=true な全ソースを返す
      allPolicies <- searchPolicies snapshotSourceTypes
      case validateSourcePolicy allPolicies snapshotSourceTypes of
        Left policyReasonCode -> do
          publishInsightCollectFailed collectionIdentifier policyReasonCode Nothing traceValue
          -- UC-11: 監査記録（ポリシー検証失敗）
          let policyAuditEntry =
                InsightAuditEntry
                  { result = AuditResult.Failed
                  , reasonCode = Just policyReasonCode
                  , targetDate = snapshotTargetDate
                  , sourceStatus = Nothing
                  }
          recordInsightAudit collectionIdentifier traceValue policyAuditEntry
          pure (CollectionFailed policyReasonCode False)
        Right approvedPolicies -> do
          -- UC-04: InsightDispatch 生成・永続化（Pending）
          let dispatch = startDispatch collectionIdentifier traceValue
          persistDispatch dispatch

          -- UC-05: InsightCollection Aggregate 生成
          case startCollection collectionIdentifier traceValue snapshot of
            Left _domainError -> do
              -- startCollection が失敗する想定外ケース → StateConflict
              let failureDetail =
                    FailureDetail
                      { reasonCode = StateConflict
                      , detail = Nothing
                      , retryable = False
                      , sourceType = Nothing
                      , stage = Just ValidateRequest
                      }
              handleCollectionFailure
                currentTime
                collectionIdentifier
                snapshot
                traceValue
                failureDetail
                dispatch
            Right collection ->
              runCollection
                currentTime
                collectionIdentifier
                snapshot
                traceValue
                approvedPolicies
                collection
                dispatch

-- | ポリシー通過後の収集フロー本体。
runCollection ::
  ( InsightCollectionRepository m
  , InsightDispatchRepository m
  , InsightRecordRepository m
  , InsightArtifactRepository m
  , ExternalSourcePort m
  , InsightCollectionEventPublisher m
  , InsightAuditPort m
  ) =>
  UTCTime ->
  InsightCollectionIdentifier ->
  InsightCollectionRequestSnapshot ->
  Trace ->
  [SourcePolicySnapshot] ->
  InsightCollection ->
  InsightDispatch ->
  m CollectInsightsResult
runCollection currentTime collectionIdentifier snapshot traceValue approvedPolicies collection dispatch = do
  let InsightCollectionRequestSnapshot{targetDate = snapshotTargetDate} = snapshot
  -- UC-06: ソース別インサイト収集
  fetchResults <- mapM (\policy -> fetchInsights policy snapshotTargetDate) approvedPolicies
  let (sourceStatuses, allRecords) = aggregateFetchResults approvedPolicies fetchResults

  -- 全件失敗判定
  case classifyFetchResults sourceStatuses allRecords fetchResults of
    Left failureDetail ->
      handleCollectionFailure
        currentTime
        collectionIdentifier
        snapshot
        traceValue
        failureDetail
        dispatch
    Right (records, partialFailureFlag) -> do
      -- UC-07: 根拠情報完全性検証
      case validateEvidence records of
        Left evidenceReasonCode -> do
          let failureDetail =
                FailureDetail
                  { reasonCode = evidenceReasonCode
                  , detail = Nothing
                  , retryable = False
                  , sourceType = Nothing
                  , stage = Just Normalize
                  }
          handleCollectionFailure
            currentTime
            collectionIdentifier
            snapshot
            traceValue
            failureDetail
            dispatch
        Right validRecords -> do
          -- UC-08: 保存順序: persistRecord → persistArtifact → persistCollection
          let storagePath = buildStoragePath snapshotTargetDate
          let artifact =
                InsightArtifact
                  { identifier = collectionIdentifier
                  , count = length validRecords
                  , storagePath = storagePath
                  , sourceStatus = sourceStatuses
                  , partialFailure = partialFailureFlag
                  }
          -- 1. 各 InsightRecord を永続化
          mapM_ persistRecord validRecords
          -- 2. InsightArtifact を永続化
          persistArtifact artifact
          -- 3. InsightCollection を Collected へ更新・永続化
          case recordCollectionSuccess (length validRecords) storagePath artifact validRecords currentTime collection of
            Left _domainError -> do
              let failureDetail =
                    FailureDetail
                      { reasonCode = StateConflict
                      , detail = Nothing
                      , retryable = False
                      , sourceType = Nothing
                      , stage = Just Persist
                      }
              handleCollectionFailure
                currentTime
                collectionIdentifier
                snapshot
                traceValue
                failureDetail
                dispatch
            Right updatedCollection -> do
              persistCollection updatedCollection

              -- UC-09: insight.collected 発行（保存後のみ）
              publishInsightCollected collectionIdentifier artifact traceValue

              -- InsightDispatch を Published へ遷移・永続化
              case markDispatched InsightCollected currentTime dispatch of
                Left _domainError ->
                  -- 状態遷移失敗（想定外）→ Succeeded を返す（Dispatch の更新失敗は非致命的）
                  pure CollectionSucceeded
                Right publishedDispatch -> do
                  persistDispatch publishedDispatch

                  -- UC-11: 監査記録（成功）
                  let InsightCollectionRequestSnapshot{targetDate = auditTargetDate} = snapshot
                  let auditEntry =
                        InsightAuditEntry
                          { result = AuditResult.Succeeded
                          , reasonCode = Nothing
                          , targetDate = auditTargetDate
                          , sourceStatus = Just sourceStatuses
                          }
                  recordInsightAudit collectionIdentifier traceValue auditEntry

                  pure CollectionSucceeded

-- | 収集失敗時の後処理（UC-10）。
handleCollectionFailure ::
  ( InsightCollectionRepository m
  , InsightDispatchRepository m
  , InsightCollectionEventPublisher m
  , InsightAuditPort m
  ) =>
  UTCTime ->
  InsightCollectionIdentifier ->
  InsightCollectionRequestSnapshot ->
  Trace ->
  FailureDetail ->
  InsightDispatch ->
  m CollectInsightsResult
handleCollectionFailure currentTime collectionIdentifier snapshot traceValue failureDetail dispatch = do
  let FailureDetail{reasonCode = failureReasonCode, detail = failureDetailText, retryable = isRetryable} = failureDetail
  let InsightCollectionRequestSnapshot{targetDate = auditTargetDate} = snapshot

  -- UC-10: insight.collect.failed 発行（reasonCode 必須）
  publishInsightCollectFailed collectionIdentifier failureReasonCode failureDetailText traceValue

  -- InsightCollection を Failed へ更新・永続化
  case startCollection collectionIdentifier traceValue snapshot of
    Right pendingCollection ->
      case recordCollectionFailure failureDetail currentTime pendingCollection of
        Left _domainError -> pure ()
        Right failedCollection -> persistCollection failedCollection
    Left _ -> pure ()

  -- InsightDispatch を Failed へ遷移・永続化
  case markDispatchFailed failureReasonCode currentTime dispatch of
    Left _domainError -> pure ()
    Right failedDispatch -> persistDispatch failedDispatch

  -- UC-11: 監査記録（失敗）
  let auditEntry =
        InsightAuditEntry
          { result = AuditResult.Failed
          , reasonCode = Just failureReasonCode
          , targetDate = auditTargetDate
          , sourceStatus = Nothing
          }
  recordInsightAudit collectionIdentifier traceValue auditEntry

  pure (CollectionFailed failureReasonCode isRetryable)

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

{- | RawInsightEvent からバリデーション済み InsightCollectionRequestSnapshot を構築する。
targetDate または requestedBy が Nothing の場合は Left RequestValidationFailed を返す（UC-02）。
-}
validateRawInsightEvent :: RawInsightEvent -> Either ReasonCode InsightCollectionRequestSnapshot
validateRawInsightEvent
  RawInsightEvent
    { targetDate = maybeTargetDate
    , requestedBy = maybeRequestedBy
    , requestedSourceTypes = sourceTypesList
    , options = maybeOptions
    } =
    case (maybeTargetDate, maybeRequestedBy) of
      (Nothing, _) -> Left RequestValidationFailed
      (_, Nothing) -> Left RequestValidationFailed
      (Just date, Just requester) ->
        case mkInsightCollectionRequestSnapshot date requester sourceTypesList maybeOptions of
          Left _ -> Left RequestValidationFailed
          Right snapshot -> Right snapshot

{- | RawInsightEvent から Trace を取り出す。trace が Nothing の場合はゼロ値 ULID でフォールバック。
バリデーション失敗時の publishInsightCollectFailed で使うため、エラーにしない。
-}
resolveTrace :: RawInsightEvent -> Trace
resolveTrace RawInsightEvent{trace = maybeTrace} = case maybeTrace of
  Just traceValue -> traceValue
  Nothing ->
    -- trace 欠損は稀な想定外ケース。ゼロ値 ULID でフォールバック。
    case ulidFromInteger 0 of
      Right zeroUlid -> Trace zeroUlid
      Left _ -> error "resolveTrace: ulidFromInteger 0 must not fail"

{- | 監査エントリの targetDate を解決する。
バリデーション失敗時に targetDate が欠損している場合は epoch 日（1970-01-01）でフォールバック。
-}
resolveAuditTargetDate :: Maybe Day -> Day
resolveAuditTargetDate (Just targetDateValue) = targetDateValue
resolveAuditTargetDate Nothing =
  -- targetDate 欠損時は epoch 日でフォールバック（バリデーション失敗ログ用）
  toEnum 0

-- | ソース別収集結果を SourceCollectionStatus リストと全レコードリストに集約する。
aggregateFetchResults ::
  [SourcePolicySnapshot] ->
  [Either FailureDetail [InsightRecord]] ->
  ([SourceCollectionStatus], [InsightRecord])
aggregateFetchResults policies results =
  foldr accumulateFetchResult ([], []) (zip policies results)
 where
  accumulateFetchResult (SourcePolicySnapshot{sourceType = policySourceType}, Left _failure) (statuses, records) =
    let collectionStatus = SourceCollectionStatus{sourceType = policySourceType, status = SourceFailed}
     in (collectionStatus : statuses, records)
  accumulateFetchResult (SourcePolicySnapshot{sourceType = policySourceType}, Right fetchedRecords) (statuses, records) =
    let collectionStatus = SourceCollectionStatus{sourceType = policySourceType, status = SourceSuccess}
     in (collectionStatus : statuses, fetchedRecords ++ records)

{- | 収集結果を分類する。
- 全件失敗 → Left FailureDetail（最初の失敗詳細を使用）
- 部分失敗または全件成功 → Right (records, partialFailure)
-}
classifyFetchResults ::
  [SourceCollectionStatus] ->
  [InsightRecord] ->
  [Either FailureDetail [InsightRecord]] ->
  Either FailureDetail ([InsightRecord], Bool)
classifyFetchResults sourceStatuses records results
  | null results = Right ([], False)
  | allFailed =
      -- 全件失敗 → 最初の失敗詳細を使用
      case firstFailure of
        Just failureDetail -> Left failureDetail
        Nothing ->
          Left
            FailureDetail
              { reasonCode = DependencyUnavailable
              , detail = Nothing
              , retryable = True
              , sourceType = Nothing
              , stage = Just Collect
              }
  | otherwise = Right (records, hasPartialFailure)
 where
  failedCount = length (filter isSourceFailed sourceStatuses)
  totalCount = length sourceStatuses
  allFailed = failedCount == totalCount && totalCount > 0
  hasPartialFailure = failedCount > 0
  firstFailure = foldr findFirstFailure Nothing results
  findFirstFailure (Left failureDetail) _ = Just failureDetail
  findFirstFailure _ acc = acc
  isSourceFailed SourceCollectionStatus{status = outcomeStatus} = outcomeStatus == SourceFailed

{- | Cloud Storage のストレージパスを生成する。
形式: /insights/YYYY-MM-DD/insights.parquet
-}
buildStoragePath :: Day -> Text
buildStoragePath targetDateValue =
  Text.pack ("/insights/" ++ show targetDateValue ++ "/insights.parquet")

-- Suppress unused warning: InsightAuditResult is imported for use with AuditResult qualifier
_unusedAuditResultType :: InsightAuditResult -> InsightAuditResult
_unusedAuditResultType = id
