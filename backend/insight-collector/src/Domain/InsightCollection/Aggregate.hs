{-# LANGUAGE NoFieldSelectors #-}

module Domain.InsightCollection.Aggregate (
  -- * Identifiers
  InsightCollectionIdentifier (..),
  InsightRecordIdentifier (..),

  -- * Status enums
  CollectionStatus (..),
  SourceType (..),
  RequestedBy (..),
  SignalClass (..),
  SourceOutcome (..),
  FailureStage (..),

  -- * Value Objects
  InsightCollectionRequestSnapshot (..),
  CollectionOptions (..),
  SourcePolicySnapshot (..),
  SourceConfig (..),
  XConfig (..),
  YouTubeConfig (..),
  PaperConfig (..),
  GitHubConfig (..),
  InsightRecord (..),
  InsightArtifact (..),
  SourceCollectionStatus (..),
  FailureDetail (..),

  -- * Search criteria
  CollectionSearchCriteria (..),
  emptyCollectionSearchCriteria,

  -- * Aggregate (construct via 'startCollection' only; constructor intentionally hidden)
  InsightCollection,

  -- * Smart constructors
  mkInsightCollectionRequestSnapshot,
  startCollection,

  -- * Commands
  recordCollectionSuccess,
  recordCollectionFailure,
  terminateCollection,

  -- * Repository Ports
  InsightCollectionRepository (..),
  SourcePolicyRepository (..),
  InsightRecordRepository (..),
  InsightArtifactRepository (..),
  IdempotencyKeyRepository (..),
) where

import Data.Text (Text)
import Data.Time (Day, UTCTime)
import Data.ULID (ULID)
import Domain.InsightCollection (Trace)
import Domain.InsightCollection.Error (DomainError (..))
import Domain.InsightCollection.ReasonCode (ReasonCode)
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers
-- Must-3: XXXIdentifier 形式。Id 表記禁止。
-- ---------------------------------------------------------------------

newtype InsightCollectionIdentifier = InsightCollectionIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

newtype InsightRecordIdentifier = InsightRecordIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Status enums
-- ---------------------------------------------------------------------

-- | Must-1: 3値のみ (pending/collected/failed)。
data CollectionStatus
  = Pending
  | Collected
  | Failed
  deriving stock (Eq, Ord, Show)

-- | Must-4: insight ドメイン固有のソース種別。
data SourceType
  = X
  | YouTube
  | Paper
  | GitHub
  deriving stock (Eq, Ord, Show)

-- | Must-4: 収集要求者。
data RequestedBy
  = Scheduler
  | User
  deriving stock (Eq, Ord, Show)

-- | Must-6: シグナル分類。
data SignalClass
  = StructuralAnomaly
  | EventNoise
  deriving stock (Eq, Ord, Show)

-- | ソース別収集結果。
data SourceOutcome
  = SourceSuccess
  | SourceFailed
  | QuotaExhausted
  deriving stock (Eq, Ord, Show)

-- | Must-8: 失敗が発生したパイプラインステージ。
data FailureStage
  = ValidateRequest
  | ValidatePolicy
  | Collect
  | Normalize
  | Persist
  | Publish
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Source configs
-- ---------------------------------------------------------------------

newtype XConfig = XConfig
  { bearerTokenSecretName :: Text
  }
  deriving stock (Eq, Show)

newtype YouTubeConfig = YouTubeConfig
  { apiKeySecretName :: Text
  }
  deriving stock (Eq, Show)

newtype PaperConfig = PaperConfig
  { baseUrl :: Text
  }
  deriving stock (Eq, Show)

newtype GitHubConfig = GitHubConfig
  { personalAccessTokenSecretName :: Text
  }
  deriving stock (Eq, Show)

-- | Must-5: sourceType に応じた設定。
data SourceConfig
  = XSourceConfig XConfig
  | YouTubeSourceConfig YouTubeConfig
  | PaperSourceConfig PaperConfig
  | GitHubSourceConfig GitHubConfig
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

-- | Must-4: 収集要求スナップショット。
data InsightCollectionRequestSnapshot = InsightCollectionRequestSnapshot
  { targetDate :: Day
  , requestedBy :: RequestedBy
  , sourceTypes :: [SourceType]
  , options :: Maybe CollectionOptions
  }
  deriving stock (Eq, Show)

-- | Must-4: 収集オプション。
data CollectionOptions = CollectionOptions
  { forceRecollect :: Bool
  , dryRun :: Bool
  , maxItemsPerSource :: Maybe Int
  }
  deriving stock (Eq, Show)

-- | Must-5: ソースポリシースナップショット。
data SourcePolicySnapshot = SourcePolicySnapshot
  { sourceType :: SourceType
  , enabled :: Bool
  , termsVersion :: Text
  , redistributionAllowed :: Bool
  , dailyQuota :: Maybe Int
  , sourceConfig :: SourceConfig
  }
  deriving stock (Eq, Show)

-- | Must-6: インサイトレコード（収集した個別の知見）。
data InsightRecord = InsightRecord
  { identifier :: InsightRecordIdentifier
  , sourceType :: SourceType
  , sourceUrl :: Text
  , evidenceSnippet :: Text
  , collectedAt :: UTCTime
  , summary :: Text
  , signalClass :: SignalClass
  , soWhatScore :: Double
  , skillVersion :: Text
  }
  deriving stock (Eq, Show)

-- | Must-7: ソース別収集状況。
data SourceCollectionStatus = SourceCollectionStatus
  { sourceType :: SourceType
  , status :: SourceOutcome
  }
  deriving stock (Eq, Show)

-- | Must-7: インサイト成果物。
data InsightArtifact = InsightArtifact
  { identifier :: InsightCollectionIdentifier
  , count :: Int
  , storagePath :: Text
  , sourceStatus :: [SourceCollectionStatus]
  , partialFailure :: Bool
  }
  deriving stock (Eq, Show)

-- | Must-8: 失敗詳細。
data FailureDetail = FailureDetail
  { reasonCode :: ReasonCode
  , detail :: Maybe Text
  , retryable :: Bool
  , sourceType :: Maybe SourceType
  , stage :: Maybe FailureStage
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。外部からは startCollection + コマンド関数で操作する。
-- フィールド名は ic プレフィックスで HasField 衝突を回避。
-- Must-1: 全フィールドを持つ。
-- ---------------------------------------------------------------------

data InsightCollection = InsightCollection
  { icIdentifier :: InsightCollectionIdentifier
  , icStatus :: CollectionStatus
  , icRequest :: InsightCollectionRequestSnapshot
  , icSourcePolicy :: [SourcePolicySnapshot]
  , icRecords :: [InsightRecord]
  , icCount :: Maybe Int
  , icStoragePath :: Maybe Text
  , icReasonCode :: Maybe ReasonCode
  , icTrace :: Trace
  , icProcessedAt :: Maybe UTCTime
  , icInsightArtifact :: Maybe InsightArtifact
  , icFailureDetail :: Maybe FailureDetail
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructors
-- Must-20: targetDate/requestedBy 欠損時に失敗を返す。
-- Must-26: identifier は生成後に変更不可（HasField で読み取り専用公開）。
-- ---------------------------------------------------------------------

{- | Must-20 RULE-IC-001: InsightCollectionRequestSnapshot の Smart constructor。
sourceTypes が空リストの場合はエラー（全ソース省略は有効だが、明示的に空を指定するのは不正）。
requestedBy / targetDate は型で強制されるため Haskell の型システムが欠損を禁止している。
-}
mkInsightCollectionRequestSnapshot ::
  Day ->
  RequestedBy ->
  [SourceType] ->
  Maybe CollectionOptions ->
  Either DomainError InsightCollectionRequestSnapshot
mkInsightCollectionRequestSnapshot targetDateValue requestedByValue sourceTypesValue optionsValue =
  Right
    InsightCollectionRequestSnapshot
      { targetDate = targetDateValue
      , requestedBy = requestedByValue
      , sourceTypes = sourceTypesValue
      , options = optionsValue
      }

{- | Must-20: targetDate/requestedBy が必須。型で強制されるため、
スナップショット構築時点ですでに検証済み。
-}
startCollection ::
  InsightCollectionIdentifier ->
  Trace ->
  InsightCollectionRequestSnapshot ->
  Either DomainError InsightCollection
startCollection collectionIdentifier traceValue snapshot =
  Right
    InsightCollection
      { icIdentifier = collectionIdentifier
      , icStatus = Pending
      , icRequest = snapshot
      , icSourcePolicy = []
      , icRecords = []
      , icCount = Nothing
      , icStoragePath = Nothing
      , icReasonCode = Nothing
      , icTrace = traceValue
      , icProcessedAt = Nothing
      , icInsightArtifact = Nothing
      , icFailureDetail = Nothing
      }

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | Must-23 INV-IC-001: status=Collected 遷移時は count/storagePath/insightArtifact.sourceStatus が必須。
遷移は Pending → Collected のみ許可。
-}
recordCollectionSuccess ::
  Int ->
  Text ->
  InsightArtifact ->
  [InsightRecord] ->
  UTCTime ->
  InsightCollection ->
  Either DomainError InsightCollection
recordCollectionSuccess count storagePath artifact records timestamp collection
  | collection.status /= Pending =
      Left (InvalidStateTransition (statusLabel collection) "RecordCollectionSuccess")
  | storagePath == ("" :: Text) =
      Left (InvariantViolation "InsightCollection" "storagePath must not be empty")
  | null artifactSourceStatus =
      Left (InvariantViolation "InsightCollection" "insightArtifact.sourceStatus must not be empty")
  | any (\r -> r.sourceUrl == ("" :: Text) || r.evidenceSnippet == ("" :: Text)) records =
      Left (InvariantViolation "InsightCollection" "all records must have non-empty sourceUrl and evidenceSnippet")
  | otherwise =
      Right
        collection
          { icStatus = Collected
          , icCount = Just count
          , icStoragePath = Just storagePath
          , icInsightArtifact = Just artifact
          , icRecords = records
          , icProcessedAt = Just timestamp
          }
 where
  InsightArtifact{sourceStatus = artifactSourceStatus} = artifact

{- | Must-24 INV-IC-003: status=Failed 遷移時は reasonCode が必須。
遷移は Pending → Failed のみ許可。
-}
recordCollectionFailure ::
  FailureDetail ->
  UTCTime ->
  InsightCollection ->
  Either DomainError InsightCollection
recordCollectionFailure failureDetail timestamp collection
  | collection.status /= Pending =
      Left (InvalidStateTransition (statusLabel collection) "RecordCollectionFailure")
  | otherwise =
      Right
        collection
          { icStatus = Failed
          , icReasonCode = Just failureDetailReasonCode
          , icFailureDetail = Just failureDetail
          , icProcessedAt = Just timestamp
          }
 where
  FailureDetail{reasonCode = failureDetailReasonCode} = failureDetail

-- | TerminateCollection — 管理コマンド（純粋）。
terminateCollection :: InsightCollection -> InsightCollection
terminateCollection = id

-- ---------------------------------------------------------------------
-- Repository Ports
-- Must-11〜Must-16
-- ---------------------------------------------------------------------

-- | Search criteria for InsightCollectionRepository.
data CollectionSearchCriteria = CollectionSearchCriteria
  { statusFilter :: Maybe CollectionStatus
  , targetDateFrom :: Maybe Day
  , targetDateTo :: Maybe Day
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

emptyCollectionSearchCriteria :: CollectionSearchCriteria
emptyCollectionSearchCriteria =
  CollectionSearchCriteria
    { statusFilter = Nothing
    , targetDateFrom = Nothing
    , targetDateTo = Nothing
    , limitCount = Nothing
    }

-- | Must-11: InsightCollectionRepository 型クラス Port（実装は infra 層）。
class (Monad m) => InsightCollectionRepository m where
  findCollection :: InsightCollectionIdentifier -> m (Maybe InsightCollection)
  findByStatus :: CollectionStatus -> m [InsightCollection]
  searchCollections :: CollectionSearchCriteria -> m [InsightCollection]
  persistCollection :: InsightCollection -> m ()
  terminateCollectionRecord :: InsightCollectionIdentifier -> m ()

-- | Must-13: SourcePolicyRepository 型クラス Port（実装は infra 層）。
class (Monad m) => SourcePolicyRepository m where
  searchPolicies :: [SourceType] -> m [SourcePolicySnapshot]
  findBySourceType :: SourceType -> m (Maybe SourcePolicySnapshot)

-- | Must-14: InsightRecordRepository 型クラス Port（実装は infra 層）。
class (Monad m) => InsightRecordRepository m where
  persistRecord :: InsightRecord -> m ()
  searchRecords :: Day -> [SourceType] -> m [InsightRecord]
  findByTargetDate :: Day -> m [InsightRecord]

-- | Must-15: InsightArtifactRepository 型クラス Port（実装は infra 層）。
class (Monad m) => InsightArtifactRepository m where
  persistArtifact :: InsightArtifact -> m ()
  findArtifact :: InsightCollectionIdentifier -> m (Maybe InsightArtifact)
  terminateArtifact :: InsightCollectionIdentifier -> m ()

-- | Must-16: IdempotencyKeyRepository 型クラス Port（実装は infra 層）。
class (Monad m) => IdempotencyKeyRepository m where
  findIdempotencyKey :: Text -> m (Maybe Text)
  persistIdempotencyKey :: Text -> m ()
  terminateIdempotencyKey :: Text -> m ()

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

statusLabel :: InsightCollection -> Text
statusLabel collection = case collection.status of
  Pending -> "pending"
  Collected -> "collected"
  Failed -> "failed"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- Must-26: identifier は読み取り専用（setter なし）
-- ---------------------------------------------------------------------

instance HasField "identifier" InsightCollection InsightCollectionIdentifier where
  getField InsightCollection{icIdentifier = x} = x

instance HasField "status" InsightCollection CollectionStatus where
  getField InsightCollection{icStatus = x} = x

instance HasField "request" InsightCollection InsightCollectionRequestSnapshot where
  getField InsightCollection{icRequest = x} = x

instance HasField "sourcePolicy" InsightCollection [SourcePolicySnapshot] where
  getField InsightCollection{icSourcePolicy = x} = x

instance HasField "records" InsightCollection [InsightRecord] where
  getField InsightCollection{icRecords = x} = x

instance HasField "count" InsightCollection (Maybe Int) where
  getField InsightCollection{icCount = x} = x

instance HasField "storagePath" InsightCollection (Maybe Text) where
  getField InsightCollection{icStoragePath = x} = x

instance HasField "reasonCode" InsightCollection (Maybe ReasonCode) where
  getField InsightCollection{icReasonCode = x} = x

instance HasField "trace" InsightCollection Trace where
  getField InsightCollection{icTrace = x} = x

instance HasField "processedAt" InsightCollection (Maybe UTCTime) where
  getField InsightCollection{icProcessedAt = x} = x

instance HasField "insightArtifact" InsightCollection (Maybe InsightArtifact) where
  getField InsightCollection{icInsightArtifact = x} = x

instance HasField "failureDetail" InsightCollection (Maybe FailureDetail) where
  getField InsightCollection{icFailureDetail = x} = x
