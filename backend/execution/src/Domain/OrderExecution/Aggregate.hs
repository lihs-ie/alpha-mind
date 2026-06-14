{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoFieldSelectors #-}

module Domain.OrderExecution.Aggregate (
  -- * Identifiers
  OrderExecutionIdentifier (..),

  -- * Status enums
  ExecutionStatus (..),
  AttemptResult (..),

  -- * Value Objects
  ExecutionRequest (..),
  RetryPolicySnapshot (..),
  FailureDetail (..),
  ExecutionAttempt (..),
  ExecutionSearchCriteria (..),
  emptyExecutionSearchCriteria,

  -- * Aggregate (construct via 'acceptApprovedOrder' only; constructor intentionally hidden)
  OrderExecution,

  -- * Smart constructor
  acceptApprovedOrder,

  -- * Commands
  dispatchToBroker,
  recordBrokerSuccess,
  recordBrokerFailure,
  shutdownExecution,

  -- * Domain Events
  OrderExecutionEvent (..),

  -- * Repository Port
  OrderExecutionRepository (..),

  -- * Specifications
  ApprovedStatusSpecification (..),
  RetryableFailureSpecification (..),
  module Domain.OrderExecution.Specification,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.OrderExecution (Trace)
import Domain.OrderExecution.Error (ExecutionError (..))
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Domain.OrderExecution.Specification (Specification (..))
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------

newtype OrderExecutionIdentifier = OrderExecutionIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Status enums
-- ---------------------------------------------------------------------

data ExecutionStatus
  = Approved
  | Executed
  | Failed
  deriving stock (Eq, Ord, Show)

-- | Result of a single broker dispatch attempt.
data AttemptResult
  = AttemptSuccess
  | AttemptRetryableFailure
  | AttemptFinalFailure
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

-- | ExecutionRequest carries the order parameters. Immutable once constructed.
data ExecutionRequest = ExecutionRequest
  { symbol :: Text
  , side :: Text
  , qty :: Int
  }
  deriving stock (Eq, Show)

-- | RetryPolicySnapshot captures retry configuration at execution time.
data RetryPolicySnapshot = RetryPolicySnapshot
  { maxAttempts :: Int
  , backoff :: Text
  }
  deriving stock (Eq, Show)

-- | FailureDetail records the cause and retry eligibility of a failure.
data FailureDetail = FailureDetail
  { reasonCode :: ReasonCode
  , detail :: Maybe Text
  , retryable :: Bool
  }
  deriving stock (Eq, Show)

-- | ExecutionAttempt records a single broker dispatch attempt.
data ExecutionAttempt = ExecutionAttempt
  { eaIdentifier :: ULID
  , eaAttempt :: Int
  , eaAttemptedAt :: UTCTime
  , eaResult :: AttemptResult
  , eaReasonCode :: Maybe ReasonCode
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Domain Events
-- ---------------------------------------------------------------------

data OrderExecutionEvent
  = OrderExecutionAttempted
      { identifier :: OrderExecutionIdentifier
      , attempt :: Int
      , trace :: Trace
      }
  | OrderExecutionSucceeded
      { identifier :: OrderExecutionIdentifier
      , brokerOrder :: Text
      , executedAt :: UTCTime
      , trace :: Trace
      }
  | OrderExecutionFailed
      { identifier :: OrderExecutionIdentifier
      , reasonCode :: ReasonCode
      , attempt :: Int
      , trace :: Trace
      }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- Constructor hidden. Access via acceptApprovedOrder + command functions.
-- Fields prefixed with oe to avoid HasField conflicts.
-- ---------------------------------------------------------------------

data OrderExecution = OrderExecution
  { oeIdentifier :: OrderExecutionIdentifier
  , oeStatus :: ExecutionStatus
  , oeRequest :: ExecutionRequest
  , oeAttemptCount :: Int
  , oeMaxAttempts :: Int
  , oeBrokerOrder :: Maybe Text
  , oeReasonCode :: Maybe ReasonCode
  , oeTrace :: Trace
  , oeLastAttemptAt :: Maybe UTCTime
  , oeExecutedAt :: Maybe UTCTime
  , oeAttempts :: [ExecutionAttempt]
  , oeRetryPolicy :: RetryPolicySnapshot
  , oeFailureDetail :: Maybe FailureDetail
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor
-- ---------------------------------------------------------------------

-- | Accept an approved order and initialise the OrderExecution aggregate.
acceptApprovedOrder ::
  OrderExecutionIdentifier ->
  ExecutionRequest ->
  Trace ->
  (OrderExecution, [OrderExecutionEvent])
acceptApprovedOrder executionIdentifier executionRequest traceValue =
  let execution =
        OrderExecution
          { oeIdentifier = executionIdentifier
          , oeStatus = Approved
          , oeRequest = executionRequest
          , oeAttemptCount = 0
          , oeMaxAttempts = 3
          , oeBrokerOrder = Nothing
          , oeReasonCode = Nothing
          , oeTrace = traceValue
          , oeLastAttemptAt = Nothing
          , oeExecutedAt = Nothing
          , oeAttempts = []
          , oeRetryPolicy = RetryPolicySnapshot{maxAttempts = 3, backoff = "exponential"}
          , oeFailureDetail = Nothing
          }
   in (execution, [])

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | DispatchToBroker — validates APPROVED status via ApprovedStatusSpecification, increments attemptCount.
Returns Left if status is not APPROVED (Must-11, Must-12).
-}
dispatchToBroker ::
  UTCTime ->
  OrderExecution ->
  Either ExecutionError (OrderExecution, [OrderExecutionEvent])
dispatchToBroker timestamp execution =
  if not (isSatisfiedBy (ApprovedStatusSpecification ()) execution)
    then case execution.status of
      Executed -> Left (DuplicateDispatch "IDEMPOTENCY_DUPLICATE_EVENT: already executed")
      _ -> Left (InvalidStateTransition (executionStatusLabel execution) "DispatchToBroker")
    else
      let newAttemptCount = execution.attemptCount + 1
          updated =
            execution
              { oeAttemptCount = newAttemptCount
              , oeLastAttemptAt = Just timestamp
              }
          event =
            OrderExecutionAttempted
              { identifier = execution.identifier
              , attempt = newAttemptCount
              , trace = execution.trace
              }
       in Right (updated, [event])

{- | RecordBrokerSuccess — sets EXECUTED, brokerOrder, executedAt.
Returns Left if status is not APPROVED (Must-11).
-}
recordBrokerSuccess ::
  Text ->
  UTCTime ->
  OrderExecution ->
  Either ExecutionError (OrderExecution, [OrderExecutionEvent])
recordBrokerSuccess brokerOrderIdentifier timestamp execution =
  case execution.status of
    Approved ->
      let updated =
            execution
              { oeStatus = Executed
              , oeBrokerOrder = Just brokerOrderIdentifier
              , oeExecutedAt = Just timestamp
              }
          event =
            OrderExecutionSucceeded
              { identifier = execution.identifier
              , brokerOrder = brokerOrderIdentifier
              , executedAt = timestamp
              , trace = execution.trace
              }
       in Right (updated, [event])
    _ ->
      Left (InvalidStateTransition (executionStatusLabel execution) "RecordBrokerSuccess")

{- | RecordBrokerFailure — uses RetryableFailureSpecification to check retryability.
If retryable && attemptCount < maxAttempts: stays APPROVED;
else transitions to FAILED with reasonCode (Must-13, Must-14, Must-15, Must-16).
-}
recordBrokerFailure ::
  ReasonCode ->
  Maybe Text ->
  UTCTime ->
  OrderExecution ->
  Either ExecutionError (OrderExecution, [OrderExecutionEvent])
recordBrokerFailure code maybeDetail timestamp execution =
  case execution.status of
    Approved ->
      let failureRecord =
            FailureDetail
              { reasonCode = code
              , detail = maybeDetail
              , retryable = isRetryableReasonCode code
              }
          canRetry =
            isSatisfiedBy (RetryableFailureSpecification ()) failureRecord
              && execution.attemptCount < execution.maxAttempts
          currentAttempts = execution.attemptCount
       in if canRetry
            then
              let updated =
                    execution
                      { oeFailureDetail = Just failureRecord
                      , oeReasonCode = Just code
                      }
               in Right (updated, [])
            else
              let updated =
                    execution
                      { oeStatus = Failed
                      , oeReasonCode = Just code
                      , oeFailureDetail = Just failureRecord
                      , oeLastAttemptAt = Just timestamp
                      }
                  event =
                    OrderExecutionFailed
                      { identifier = execution.identifier
                      , reasonCode = code
                      , attempt = currentAttempts
                      , trace = execution.trace
                      }
               in Right (updated, [event])
    _ ->
      Left (InvalidStateTransition (executionStatusLabel execution) "RecordBrokerFailure")

-- | ShutdownExecution — administrative command, pure, no events.
shutdownExecution :: OrderExecution -> OrderExecution
shutdownExecution = id

-- ---------------------------------------------------------------------
-- Repository Port
-- ---------------------------------------------------------------------

data ExecutionSearchCriteria = ExecutionSearchCriteria
  { statusFilter :: Maybe ExecutionStatus
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

emptyExecutionSearchCriteria :: ExecutionSearchCriteria
emptyExecutionSearchCriteria =
  ExecutionSearchCriteria
    { statusFilter = Nothing
    , limitCount = Nothing
    }

class (Monad m) => OrderExecutionRepository m where
  findExecution :: OrderExecutionIdentifier -> m (Maybe OrderExecution)
  findExecutionsByStatus :: ExecutionStatus -> m [OrderExecution]
  searchExecutions :: ExecutionSearchCriteria -> m [OrderExecution]
  persistExecution :: OrderExecution -> m ()
  terminateExecution :: OrderExecutionIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Specifications
-- ---------------------------------------------------------------------

-- | ApprovedStatusSpecification: satisfied when status is APPROVED (Must-29).
newtype ApprovedStatusSpecification = ApprovedStatusSpecification ()
  deriving stock (Eq, Show)

instance Specification ApprovedStatusSpecification OrderExecution where
  isSatisfiedBy _ execution = execution.status == Approved

-- | RetryableFailureSpecification: satisfied when retryable is True (Must-30).
newtype RetryableFailureSpecification = RetryableFailureSpecification ()
  deriving stock (Eq, Show)

instance Specification RetryableFailureSpecification FailureDetail where
  isSatisfiedBy _ failureDetail = failureDetail.retryable

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

executionStatusLabel :: OrderExecution -> Text
executionStatusLabel execution = case execution.status of
  Approved -> "approved"
  Executed -> "executed"
  Failed -> "failed"

isRetryableReasonCode :: ReasonCode -> Bool
isRetryableReasonCode ExecutionBrokerTimeout = True
isRetryableReasonCode DependencyTimeout = True
isRetryableReasonCode InternalError = True
isRetryableReasonCode _ = False

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- ---------------------------------------------------------------------

instance HasField "identifier" OrderExecution OrderExecutionIdentifier where
  getField OrderExecution{oeIdentifier = x} = x

instance HasField "status" OrderExecution ExecutionStatus where
  getField OrderExecution{oeStatus = x} = x

instance HasField "request" OrderExecution ExecutionRequest where
  getField OrderExecution{oeRequest = x} = x

instance HasField "attemptCount" OrderExecution Int where
  getField OrderExecution{oeAttemptCount = x} = x

instance HasField "maxAttempts" OrderExecution Int where
  getField OrderExecution{oeMaxAttempts = x} = x

instance HasField "brokerOrder" OrderExecution (Maybe Text) where
  getField OrderExecution{oeBrokerOrder = x} = x

instance HasField "reasonCode" OrderExecution (Maybe ReasonCode) where
  getField OrderExecution{oeReasonCode = x} = x

instance HasField "trace" OrderExecution Trace where
  getField OrderExecution{oeTrace = x} = x

instance HasField "lastAttemptAt" OrderExecution (Maybe UTCTime) where
  getField OrderExecution{oeLastAttemptAt = x} = x

instance HasField "executedAt" OrderExecution (Maybe UTCTime) where
  getField OrderExecution{oeExecutedAt = x} = x

instance HasField "attempts" OrderExecution [ExecutionAttempt] where
  getField OrderExecution{oeAttempts = x} = x

instance HasField "retryPolicy" OrderExecution RetryPolicySnapshot where
  getField OrderExecution{oeRetryPolicy = x} = x

instance HasField "failureDetail" OrderExecution (Maybe FailureDetail) where
  getField OrderExecution{oeFailureDetail = x} = x

-- HasField for ExecutionAttempt
instance HasField "identifier" ExecutionAttempt ULID where
  getField ExecutionAttempt{eaIdentifier = x} = x

instance HasField "attempt" ExecutionAttempt Int where
  getField ExecutionAttempt{eaAttempt = x} = x

instance HasField "attemptedAt" ExecutionAttempt UTCTime where
  getField ExecutionAttempt{eaAttemptedAt = x} = x

instance HasField "result" ExecutionAttempt AttemptResult where
  getField ExecutionAttempt{eaResult = x} = x

instance HasField "reasonCode" ExecutionAttempt (Maybe ReasonCode) where
  getField ExecutionAttempt{eaReasonCode = x} = x

-- Note: FailureDetail fields (reasonCode, detail, retryable) are accessible via dot-notation
-- through GHC's automatic HasField instances because FailureDetail lacks NoFieldSelectors.
