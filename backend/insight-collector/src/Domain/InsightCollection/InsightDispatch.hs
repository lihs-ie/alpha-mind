{-# LANGUAGE NoFieldSelectors #-}

module Domain.InsightCollection.InsightDispatch (
  -- * Type alias
  InsightDispatchIdentifier,

  -- * Status enum
  DispatchStatus (..),

  -- * Value Objects
  PublishedEventType (..),
  DispatchDecision (..),

  -- * Aggregate (construct via 'startDispatch' only; constructor intentionally hidden)
  InsightDispatch,

  -- * Smart constructor
  startDispatch,

  -- * Commands
  markDispatched,
  markDispatchFailed,
  terminateDispatch,

  -- * Repository Port
  InsightDispatchRepository (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.InsightCollection (Trace)
import Domain.InsightCollection.Aggregate (InsightCollectionIdentifier)
import Domain.InsightCollection.Error (DomainError (..))
import Domain.InsightCollection.ReasonCode (ReasonCode)
import GHC.Records (HasField (..))

-- | InsightDispatch は InsightCollection と同一識別子を使用する。
type InsightDispatchIdentifier = InsightCollectionIdentifier

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------

-- | Must-2: 3値のみ (pending/published/failed)。
data DispatchStatus
  = Pending
  | Published
  | Failed
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

-- | Must-2: 発行されるイベント種別。
data PublishedEventType
  = InsightCollected
  | InsightCollectFailed
  deriving stock (Eq, Ord, Show)

-- | Must-9: DispatchDecision。
data DispatchDecision = DispatchDecision
  { dispatchStatus :: DispatchStatus
  , publishedEvent :: Maybe PublishedEventType
  , reasonCode :: Maybe ReasonCode
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。フィールドは id プレフィックスで HasField 衝突を回避。
-- Must-2: フィールド identifier/dispatchStatus/dispatchDecision/trace/processedAt。
-- ---------------------------------------------------------------------

data InsightDispatch = InsightDispatch
  { idIdentifier :: InsightCollectionIdentifier
  , idDispatchStatus :: DispatchStatus
  , idDispatchDecision :: DispatchDecision
  , idTrace :: Trace
  , idProcessedAt :: Maybe UTCTime
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor — startDispatch
-- ---------------------------------------------------------------------

startDispatch ::
  InsightCollectionIdentifier ->
  Trace ->
  InsightDispatch
startDispatch dispatchIdentifier traceValue =
  InsightDispatch
    { idIdentifier = dispatchIdentifier
    , idDispatchStatus = Pending
    , idDispatchDecision =
        DispatchDecision
          { dispatchStatus = Pending
          , publishedEvent = Nothing
          , reasonCode = Nothing
          }
    , idTrace = traceValue
    , idProcessedAt = Nothing
    }

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | Must-25 INV-IC-004: Pending → Published の一方向遷移のみ許可。
すでに Published の場合は冪等扱い（Right dispatch 返却、副作用なし）。
Failed 状態からの遷移は Left DomainError を返す。
-}
markDispatched ::
  PublishedEventType ->
  UTCTime ->
  InsightDispatch ->
  Either DomainError InsightDispatch
markDispatched _ _ dispatch
  | dispatch.dispatchStatus == Published = Right dispatch
markDispatched eventType timestamp dispatch
  | dispatch.dispatchStatus /= Pending =
      Left (InvalidStateTransition (dispatchStatusLabel dispatch) "MarkDispatched")
  | otherwise =
      let decision =
            DispatchDecision
              { dispatchStatus = Published
              , publishedEvent = Just eventType
              , reasonCode = Nothing
              }
       in Right
            dispatch
              { idDispatchStatus = Published
              , idDispatchDecision = decision
              , idProcessedAt = Just timestamp
              }

{- | Must-25 INV-IC-004: Pending → Failed の一方向遷移のみ許可。
Published / Failed 状態からの遷移は Left DomainError を返す。
-}
markDispatchFailed ::
  ReasonCode ->
  UTCTime ->
  InsightDispatch ->
  Either DomainError InsightDispatch
markDispatchFailed code timestamp dispatch
  | dispatch.dispatchStatus /= Pending =
      Left (InvalidStateTransition (dispatchStatusLabel dispatch) "MarkDispatchFailed")
  | otherwise =
      let decision =
            DispatchDecision
              { dispatchStatus = Failed
              , publishedEvent = Nothing
              , reasonCode = Just code
              }
       in Right
            dispatch
              { idDispatchStatus = Failed
              , idDispatchDecision = decision
              , idProcessedAt = Just timestamp
              }

-- | TerminateDispatch — 管理コマンド（純粋）。
terminateDispatch :: InsightDispatch -> InsightDispatch
terminateDispatch = id

-- ---------------------------------------------------------------------
-- Repository Port (Must-12)
-- ---------------------------------------------------------------------

-- | Must-12: InsightDispatchRepository 型クラス Port（実装は infra 層）。
class (Monad m) => InsightDispatchRepository m where
  findDispatch :: InsightCollectionIdentifier -> m (Maybe InsightDispatch)
  persistDispatch :: InsightDispatch -> m ()
  terminateDispatch' :: InsightCollectionIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

dispatchStatusLabel :: InsightDispatch -> Text
dispatchStatusLabel dispatch = case dispatch.dispatchStatus of
  Pending -> "pending"
  Published -> "published"
  Failed -> "failed"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- ---------------------------------------------------------------------

instance HasField "identifier" InsightDispatch InsightCollectionIdentifier where
  getField InsightDispatch{idIdentifier = x} = x

instance HasField "dispatchStatus" InsightDispatch DispatchStatus where
  getField InsightDispatch{idDispatchStatus = x} = x

instance HasField "dispatchDecision" InsightDispatch DispatchDecision where
  getField InsightDispatch{idDispatchDecision = x} = x

instance HasField "trace" InsightDispatch Trace where
  getField InsightDispatch{idTrace = x} = x

instance HasField "processedAt" InsightDispatch (Maybe UTCTime) where
  getField InsightDispatch{idProcessedAt = x} = x

instance HasField "publishedEvent" InsightDispatch (Maybe PublishedEventType) where
  getField InsightDispatch{idDispatchDecision = d} = d.publishedEvent

instance HasField "reasonCode" InsightDispatch (Maybe ReasonCode) where
  getField InsightDispatch{idDispatchDecision = d} = d.reasonCode
