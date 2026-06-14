module Domain.OrderExecution.ExecutionIdempotencyPolicy (
  isDuplicateDispatch,
) where

import Domain.OrderExecution.Aggregate (ExecutionStatus (..), OrderExecution)
import GHC.Records (HasField (..))

{- | Determine whether dispatching would be a duplicate.
Returns True if status is EXECUTED or FAILED (terminal states).
Pure function, no IO. (Must-26)
-}
isDuplicateDispatch :: OrderExecution -> Bool
isDuplicateDispatch execution =
  let currentStatus = getField @"status" execution
   in currentStatus == Executed || currentStatus == Failed
