{-# LANGUAGE NoFieldSelectors #-}

module Domain.HypothesisOrchestration.OrchestrationDispatch (
  -- * Identifiers
  OrchestrationDispatchIdentifier (..),

  -- * Status enum
  DispatchStatus (..),

  -- * Aggregate (construct via 'startDispatch' only; constructor intentionally hidden)
  OrchestrationDispatch,

  -- * Smart constructor
  startDispatch,

  -- * Commands
  markPublished,
  markDuplicate,
  markFailed,
  terminateDispatch,

  -- * Repository Port
  OrchestrationDispatchRepository (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.HypothesisOrchestration (Trace)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (
  DispatchDecision,
  PublishedEventType,
  SourceEventSnapshot,
  SourceEventType,
 )
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------

-- | Must-36: 識別子型は OrchestrationDispatchIdentifier と命名。
newtype OrchestrationDispatchIdentifier = OrchestrationDispatchIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Status (Must-07)
-- ---------------------------------------------------------------------

-- | Must-07: 4状態のみ。
data DispatchStatus
  = Pending
  | Published
  | DispatchFailed
  | Duplicate
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- コンストラクタは隠蔽。フィールドは od プレフィックスで HasField 衝突を回避。
-- Must-06: identifier は不変。
-- Must-10: hypothesis フィールドで HypothesisProposal の識別子（文字列）を参照。
-- ---------------------------------------------------------------------

data OrchestrationDispatch = OrchestrationDispatch
  { odIdentifier :: OrchestrationDispatchIdentifier
  , odSourceEventType :: SourceEventType
  , odDispatchStatus :: DispatchStatus
  , odPublishedEvent :: Maybe PublishedEventType
  , odHypothesis :: Maybe Text
  -- ^ Must-10: hypothesis は HypothesisProposal 識別子の文字列参照のみ
  , odReasonCode :: Maybe ReasonCode
  , odTrace :: Trace
  , odRetryCount :: Maybe Int
  , odProcessedAt :: Maybe UTCTime
  , odSourceEventSnapshot :: SourceEventSnapshot
  , odDispatchDecision :: Maybe DispatchDecision
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor
-- ---------------------------------------------------------------------

-- | Must-06: identifier はスマートコンストラクタで1度のみ設定される。
startDispatch ::
  OrchestrationDispatchIdentifier ->
  SourceEventSnapshot ->
  SourceEventType ->
  Trace ->
  OrchestrationDispatch
startDispatch dispatchIdentifier snapshot sourceEventType traceValue =
  OrchestrationDispatch
    { odIdentifier = dispatchIdentifier
    , odSourceEventType = sourceEventType
    , odDispatchStatus = Pending
    , odPublishedEvent = Nothing
    , odHypothesis = Nothing
    , odReasonCode = Nothing
    , odTrace = traceValue
    , odRetryCount = Nothing
    , odProcessedAt = Nothing
    , odSourceEventSnapshot = snapshot
    , odDispatchDecision = Nothing
    }

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | Must-08 INV-AO-004: Pending → Published 遷移。
publishedEvent は必須（INV-AO-004）。
Must-09: identifier は不変。
-}
markPublished ::
  PublishedEventType ->
  DispatchDecision ->
  Text ->
  UTCTime ->
  OrchestrationDispatch ->
  Either DomainError OrchestrationDispatch
markPublished eventType decision hypothesisReference now dispatch
  | dispatch.dispatchStatus /= Pending =
      Left (InvalidStateTransition (dispatchStatusLabel dispatch) "MarkPublished" StateConflict)
  | otherwise =
      Right
        dispatch
          { odDispatchStatus = Published
          , odPublishedEvent = Just eventType
          , odHypothesis = Just hypothesisReference
          , odDispatchDecision = Just decision
          , odProcessedAt = Just now
          }

-- | Pending → Duplicate 遷移（重複検出時）。
markDuplicate ::
  UTCTime ->
  OrchestrationDispatch ->
  Either DomainError OrchestrationDispatch
markDuplicate now dispatch
  | dispatch.dispatchStatus /= Pending =
      Left (InvalidStateTransition (dispatchStatusLabel dispatch) "MarkDuplicate" StateConflict)
  | otherwise =
      Right
        dispatch
          { odDispatchStatus = Duplicate
          , odReasonCode = Just IdempotencyDuplicateEvent
          , odProcessedAt = Just now
          }

-- | Pending → DispatchFailed 遷移。
markFailed ::
  ReasonCode ->
  Int ->
  UTCTime ->
  OrchestrationDispatch ->
  Either DomainError OrchestrationDispatch
markFailed code retryCount now dispatch
  | dispatch.dispatchStatus /= Pending =
      Left (InvalidStateTransition (dispatchStatusLabel dispatch) "MarkFailed" StateConflict)
  | otherwise =
      Right
        dispatch
          { odDispatchStatus = DispatchFailed
          , odReasonCode = Just code
          , odRetryCount = Just retryCount
          , odProcessedAt = Just now
          }

-- | TerminateDispatch — 管理コマンド（純粋）。
terminateDispatch :: OrchestrationDispatch -> OrchestrationDispatch
terminateDispatch = id

-- ---------------------------------------------------------------------
-- Repository Port (Must-19)
-- ---------------------------------------------------------------------

-- | Must-19: OrchestrationDispatchRepository 型クラス Port（実装は infra 層）。
class (Monad m) => OrchestrationDispatchRepository m where
  find :: OrchestrationDispatchIdentifier -> m (Maybe OrchestrationDispatch)
  persist :: OrchestrationDispatch -> m ()
  terminate :: OrchestrationDispatchIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

dispatchStatusLabel :: OrchestrationDispatch -> Text
dispatchStatusLabel dispatch = case dispatch.dispatchStatus of
  Pending -> "pending"
  Published -> "published"
  DispatchFailed -> "failed"
  Duplicate -> "duplicate"

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- ---------------------------------------------------------------------

instance HasField "identifier" OrchestrationDispatch OrchestrationDispatchIdentifier where
  getField OrchestrationDispatch{odIdentifier = x} = x

instance HasField "sourceEventType" OrchestrationDispatch SourceEventType where
  getField OrchestrationDispatch{odSourceEventType = x} = x

instance HasField "dispatchStatus" OrchestrationDispatch DispatchStatus where
  getField OrchestrationDispatch{odDispatchStatus = x} = x

instance HasField "publishedEvent" OrchestrationDispatch (Maybe PublishedEventType) where
  getField OrchestrationDispatch{odPublishedEvent = x} = x

instance HasField "hypothesis" OrchestrationDispatch (Maybe Text) where
  getField OrchestrationDispatch{odHypothesis = x} = x

instance HasField "reasonCode" OrchestrationDispatch (Maybe ReasonCode) where
  getField OrchestrationDispatch{odReasonCode = x} = x

instance HasField "trace" OrchestrationDispatch Trace where
  getField OrchestrationDispatch{odTrace = x} = x

instance HasField "retryCount" OrchestrationDispatch (Maybe Int) where
  getField OrchestrationDispatch{odRetryCount = x} = x

instance HasField "processedAt" OrchestrationDispatch (Maybe UTCTime) where
  getField OrchestrationDispatch{odProcessedAt = x} = x

instance HasField "sourceEventSnapshot" OrchestrationDispatch SourceEventSnapshot where
  getField OrchestrationDispatch{odSourceEventSnapshot = x} = x

instance HasField "dispatchDecision" OrchestrationDispatch (Maybe DispatchDecision) where
  getField OrchestrationDispatch{odDispatchDecision = x} = x
