{-# LANGUAGE NoFieldSelectors #-}

module Domain.MarketCollection.CollectionDispatch (
  -- * Status enum
  DispatchStatus (..),

  -- * Value Objects
  PublishedEventType (..),
  DispatchDecision (..),

  -- * Aggregate (construct via 'startDispatch' only; constructor intentionally hidden)
  CollectionDispatch,

  -- * Smart constructor
  startDispatch,

  -- * Commands
  markDispatched,
  markDispatchFailed,
  terminateDispatch,

  -- * Repository Port
  CollectionDispatchRepository (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.MarketCollection (Trace)
import Domain.MarketCollection.Aggregate (MarketCollectionIdentifier)
import Domain.MarketCollection.Error (DomainError (..))
import Domain.MarketCollection.ReasonCode (ReasonCode)
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------

-- | Must-04: 3値のみ。
data DispatchStatus
  = Pending
  | Published
  | Failed
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

-- | Published イベント種別。
data PublishedEventType
  = MarketCollected
  | MarketCollectFailed
  deriving stock (Eq, Ord, Show)

-- | Must-09: DispatchDecision。
data DispatchDecision = DispatchDecision
  { dispatchStatus :: DispatchStatus
  , publishedEvent :: Maybe PublishedEventType
  , reasonCode :: Maybe ReasonCode
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。フィールドは cd プレフィックスで HasField 衝突を回避。
-- Must-02: フィールド identifier / dispatchStatus / dispatchDecision / trace / processedAt。
-- ---------------------------------------------------------------------

data CollectionDispatch = CollectionDispatch
  { cdIdentifier :: MarketCollectionIdentifier
  , cdDispatchStatus :: DispatchStatus
  , cdDispatchDecision :: DispatchDecision
  , cdTrace :: Trace
  , cdProcessedAt :: Maybe UTCTime
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor — StartDispatch コマンド
-- ---------------------------------------------------------------------

startDispatch ::
  MarketCollectionIdentifier ->
  Trace ->
  CollectionDispatch
startDispatch dispatchIdentifier traceValue =
  CollectionDispatch
    { cdIdentifier = dispatchIdentifier
    , cdDispatchStatus = Pending
    , cdDispatchDecision =
        DispatchDecision
          { dispatchStatus = Pending
          , publishedEvent = Nothing
          , reasonCode = Nothing
          }
    , cdTrace = traceValue
    , cdProcessedAt = Nothing
    }

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | Must-14 INV-DC-004: Pending → Published の一方向遷移のみ許可。
Published / Failed 状態からの遷移は Left DomainError を返す。
-}
markDispatched ::
  PublishedEventType ->
  UTCTime ->
  CollectionDispatch ->
  Either DomainError CollectionDispatch
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
              { cdDispatchStatus = Published
              , cdDispatchDecision = decision
              , cdProcessedAt = Just timestamp
              }

{- | Must-14 INV-DC-004: Pending → Failed の一方向遷移のみ許可。
Published / Failed 状態からの遷移は Left DomainError を返す。
-}
markDispatchFailed ::
  ReasonCode ->
  UTCTime ->
  CollectionDispatch ->
  Either DomainError CollectionDispatch
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
              { cdDispatchStatus = Failed
              , cdDispatchDecision = decision
              , cdProcessedAt = Just timestamp
              }

-- | TerminateDispatch — 管理コマンド（純粋）。
terminateDispatch :: CollectionDispatch -> CollectionDispatch
terminateDispatch = id

-- ---------------------------------------------------------------------
-- Repository Port (Must-20)
-- ---------------------------------------------------------------------

-- | Must-20: CollectionDispatchRepository 型クラス Port（実装は infra 層）。
class (Monad m) => CollectionDispatchRepository m where
  find :: MarketCollectionIdentifier -> m (Maybe CollectionDispatch)
  persist :: CollectionDispatch -> m ()
  terminate :: MarketCollectionIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

dispatchStatusLabel :: CollectionDispatch -> Text
dispatchStatusLabel dispatch = case dispatch.dispatchStatus of
  Pending -> "pending"
  Published -> "published"
  Failed -> "failed"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- ---------------------------------------------------------------------

instance HasField "identifier" CollectionDispatch MarketCollectionIdentifier where
  getField CollectionDispatch{cdIdentifier = x} = x

instance HasField "dispatchStatus" CollectionDispatch DispatchStatus where
  getField CollectionDispatch{cdDispatchStatus = x} = x

instance HasField "dispatchDecision" CollectionDispatch DispatchDecision where
  getField CollectionDispatch{cdDispatchDecision = x} = x

instance HasField "trace" CollectionDispatch Trace where
  getField CollectionDispatch{cdTrace = x} = x

instance HasField "processedAt" CollectionDispatch (Maybe UTCTime) where
  getField CollectionDispatch{cdProcessedAt = x} = x
