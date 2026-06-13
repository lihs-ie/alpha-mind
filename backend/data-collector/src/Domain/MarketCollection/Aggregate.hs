{-# LANGUAGE NoFieldSelectors #-}

module Domain.MarketCollection.Aggregate (
  -- * Identifiers
  MarketCollectionIdentifier (..),

  -- * Status enums
  CollectionStatus (..),

  -- * Value Objects
  CollectionRequestSnapshot (..),
  RequestedBy (..),
  CollectionMode (..),
  MarketSourceStatus (..),
  SourceStatus (..),
  CollectedArtifact,
  mkCollectedArtifact,
  collectedArtifactTargetDate,
  collectedArtifactStoragePath,
  collectedArtifactSourceStatus,
  collectedArtifactRowCount,
  FailureDetail (..),

  -- * Aggregate (construct via 'startCollection' only; constructor intentionally hidden)
  MarketCollection,

  -- * Smart constructor
  startCollection,

  -- * Commands
  recordCollectionSuccess,
  recordCollectionFailure,
  terminateCollection,

  -- * Domain Events
  MarketCollectionEvent (..),

  -- * Repository Port
  CollectionSearchCriteria (..),
  emptyCollectionSearchCriteria,
  MarketCollectionRepository (..),
) where

import Data.Text (Text)
import Data.Time (Day, UTCTime)
import Data.ULID (ULID)
import Domain.MarketCollection (Trace)
import Domain.MarketCollection.Error (DomainError (..))
import Domain.MarketCollection.ReasonCode (ReasonCode)
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------

-- | Must-23: 識別子型は MarketCollectionIdentifier と命名。XXXId 形式は禁止。
newtype MarketCollectionIdentifier = MarketCollectionIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------

-- | Must-03: 3値のみ。
data CollectionStatus
  = Pending
  | Collected
  | Failed
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

-- | Must-05: RequestedBy は Scheduler | User の2値。
data RequestedBy
  = Scheduler
  | User
  deriving stock (Eq, Ord, Show)

-- | Must-05: CollectionMode は Daily | Manual の2値。
data CollectionMode
  = Daily
  | Manual
  deriving stock (Eq, Ord, Show)

-- | Must-05: CollectionRequestSnapshot。
data CollectionRequestSnapshot = CollectionRequestSnapshot
  { targetDate :: Day
  , requestedBy :: RequestedBy
  , mode :: Maybe CollectionMode
  }
  deriving stock (Eq, Show)

-- | Must-06: MarketSourceStatus は Ok | SourceFailed の2値。
data MarketSourceStatus
  = Ok
  | SourceFailed
  deriving stock (Eq, Ord, Show)

-- | Must-06: SourceStatus は jp と us フィールドを保持。
data SourceStatus = SourceStatus
  { jp :: MarketSourceStatus
  , us :: MarketSourceStatus
  }
  deriving stock (Eq, Show)

{- | Must-07: CollectedArtifact — smart constructor で rowCount >= 0 を強制。
コンストラクタを隠蔽し、外部からは mkCollectedArtifact 経由でのみ生成可能。
-}
data CollectedArtifact = CollectedArtifact
  { caTargetDate :: Day
  , caStoragePath :: Text
  , caSourceStatus :: SourceStatus
  , caRowCount :: Int
  }
  deriving stock (Eq, Show)

-- | Must-07: スマートコンストラクタ — storagePath が空文字不可、rowCount が 0 以上を強制。
mkCollectedArtifact ::
  Day ->
  Text ->
  SourceStatus ->
  Int ->
  Either DomainError CollectedArtifact
mkCollectedArtifact date path status count
  | path == "" = Left (InvariantViolation "CollectedArtifact" "storagePath must not be empty")
  | count < 0 = Left (InvariantViolation "CollectedArtifact" "rowCount must be non-negative")
  | otherwise =
      Right
        CollectedArtifact
          { caTargetDate = date
          , caStoragePath = path
          , caSourceStatus = status
          , caRowCount = count
          }

collectedArtifactTargetDate :: CollectedArtifact -> Day
collectedArtifactTargetDate CollectedArtifact{caTargetDate = x} = x

collectedArtifactStoragePath :: CollectedArtifact -> Text
collectedArtifactStoragePath CollectedArtifact{caStoragePath = x} = x

collectedArtifactSourceStatus :: CollectedArtifact -> SourceStatus
collectedArtifactSourceStatus CollectedArtifact{caSourceStatus = x} = x

collectedArtifactRowCount :: CollectedArtifact -> Int
collectedArtifactRowCount CollectedArtifact{caRowCount = x} = x

-- | Must-08: FailureDetail。
data FailureDetail = FailureDetail
  { reasonCode :: ReasonCode
  , detail :: Maybe Text
  , retryable :: Bool
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Domain Events
-- ---------------------------------------------------------------------

-- | Must-15: MarketCollectionEvent — 3バリアント。
data MarketCollectionEvent
  = MarketCollectionStarted
      { identifier :: MarketCollectionIdentifier
      , targetDate :: Day
      , trace :: Trace
      }
  | MarketCollectionCompleted
      { identifier :: MarketCollectionIdentifier
      , targetDate :: Day
      , storagePath :: Text
      , sourceStatus :: SourceStatus
      , trace :: Trace
      }
  | MarketCollectionFailed
      { identifier :: MarketCollectionIdentifier
      , reasonCode :: ReasonCode
      , detail :: Maybe Text
      , trace :: Trace
      }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。外部からは startCollection + コマンド関数で操作する。
-- フィールド名は mc プレフィックスで HasField 衝突を回避。
-- ---------------------------------------------------------------------

data MarketCollection = MarketCollection
  { mcIdentifier :: MarketCollectionIdentifier
  , mcStatus :: CollectionStatus
  , mcRequest :: CollectionRequestSnapshot
  , mcTargetDate :: Day
  , mcTrace :: Trace
  , mcStoragePath :: Maybe Text
  , mcSourceStatus :: Maybe SourceStatus
  , mcRowCount :: Maybe Int
  , mcReasonCode :: Maybe ReasonCode
  , mcProcessedAt :: Maybe UTCTime
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor — StartCollection コマンド (Must-13: identifier は不変)
-- ---------------------------------------------------------------------

-- | Must-13: identifier はスマートコンストラクタで1度のみ設定される。
startCollection ::
  MarketCollectionIdentifier ->
  CollectionRequestSnapshot ->
  Trace ->
  (MarketCollection, [MarketCollectionEvent])
startCollection collectionIdentifier snapshot traceValue =
  let collection =
        MarketCollection
          { mcIdentifier = collectionIdentifier
          , mcStatus = Pending
          , mcRequest = snapshot
          , mcTargetDate = snapshot.targetDate
          , mcTrace = traceValue
          , mcStoragePath = Nothing
          , mcSourceStatus = Nothing
          , mcRowCount = Nothing
          , mcReasonCode = Nothing
          , mcProcessedAt = Nothing
          }
      event =
        MarketCollectionStarted
          { identifier = collectionIdentifier
          , targetDate = snapshot.targetDate
          , trace = traceValue
          }
   in (collection, [event])

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | Must-11 INV-DC-001: status=Collected 遷移時は storagePath/sourceStatus 必須。
Must-16: コマンドは (MarketCollection, [MarketCollectionEvent]) を返す（副作用なし）。
-}
recordCollectionSuccess ::
  Text ->
  SourceStatus ->
  Int ->
  UTCTime ->
  MarketCollection ->
  Either DomainError (MarketCollection, [MarketCollectionEvent])
recordCollectionSuccess path status count timestamp collection
  | collection.status /= Pending =
      Left (InvalidStateTransition (statusLabel collection) "RecordCollectionSuccess")
  | path == "" =
      Left (InvariantViolation "MarketCollection" "storagePath must not be empty")
  | otherwise =
      let updated =
            collection
              { mcStatus = Collected
              , mcStoragePath = Just path
              , mcSourceStatus = Just status
              , mcRowCount = Just count
              , mcProcessedAt = Just timestamp
              }
          event =
            MarketCollectionCompleted
              { identifier = collection.identifier
              , targetDate = collection.targetDate
              , storagePath = path
              , sourceStatus = status
              , trace = collection.trace
              }
       in Right (updated, [event])

{- | Must-12 INV-DC-002: status=Failed 遷移時は reasonCode 必須。
Must-16: コマンドは (MarketCollection, [MarketCollectionEvent]) を返す（副作用なし）。
-}
recordCollectionFailure ::
  ReasonCode ->
  Maybe Text ->
  UTCTime ->
  MarketCollection ->
  Either DomainError (MarketCollection, [MarketCollectionEvent])
recordCollectionFailure code failureDetail timestamp collection
  | collection.status /= Pending =
      Left (InvalidStateTransition (statusLabel collection) "RecordCollectionFailure")
  | otherwise =
      let updated =
            collection
              { mcStatus = Failed
              , mcReasonCode = Just code
              , mcProcessedAt = Just timestamp
              }
          event =
            MarketCollectionFailed
              { identifier = collection.identifier
              , reasonCode = code
              , detail = failureDetail
              , trace = collection.trace
              }
       in Right (updated, [event])

-- | TerminateCollection — 管理コマンド（純粋、イベントなし）。
terminateCollection :: MarketCollection -> MarketCollection
terminateCollection = id

-- ---------------------------------------------------------------------
-- Repository Port (Must-19)
-- ---------------------------------------------------------------------

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

-- | Must-19: MarketCollectionRepository 型クラス Port（実装は infra 層）。
class (Monad m) => MarketCollectionRepository m where
  find :: MarketCollectionIdentifier -> m (Maybe MarketCollection)
  findByStatus :: CollectionStatus -> m [MarketCollection]
  search :: CollectionSearchCriteria -> m [MarketCollection]
  persist :: MarketCollection -> m ()
  terminate :: MarketCollectionIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

statusLabel :: MarketCollection -> Text
statusLabel collection = case collection.status of
  Pending -> "pending"
  Collected -> "collected"
  Failed -> "failed"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- ---------------------------------------------------------------------

instance HasField "identifier" MarketCollection MarketCollectionIdentifier where
  getField MarketCollection{mcIdentifier = x} = x

instance HasField "status" MarketCollection CollectionStatus where
  getField MarketCollection{mcStatus = x} = x

instance HasField "request" MarketCollection CollectionRequestSnapshot where
  getField MarketCollection{mcRequest = x} = x

instance HasField "targetDate" MarketCollection Day where
  getField MarketCollection{mcTargetDate = x} = x

instance HasField "trace" MarketCollection Trace where
  getField MarketCollection{mcTrace = x} = x

instance HasField "storagePath" MarketCollection (Maybe Text) where
  getField MarketCollection{mcStoragePath = x} = x

instance HasField "sourceStatus" MarketCollection (Maybe SourceStatus) where
  getField MarketCollection{mcSourceStatus = x} = x

instance HasField "rowCount" MarketCollection (Maybe Int) where
  getField MarketCollection{mcRowCount = x} = x

instance HasField "reasonCode" MarketCollection (Maybe ReasonCode) where
  getField MarketCollection{mcReasonCode = x} = x

instance HasField "processedAt" MarketCollection (Maybe UTCTime) where
  getField MarketCollection{mcProcessedAt = x} = x
