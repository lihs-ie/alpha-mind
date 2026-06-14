module Domain.OrderExecution.OrderExecutionFactory (
  fromApprovedOrder,
) where

import Domain.OrderExecution (Trace)
import Domain.OrderExecution.Aggregate (
  ExecutionRequest,
  OrderExecution,
  OrderExecutionEvent,
  OrderExecutionIdentifier,
  acceptApprovedOrder,
 )

{- | Factory: create an OrderExecution from an approved order input.
Delegates to the aggregate smart constructor. (Must-27)
-}
fromApprovedOrder ::
  OrderExecutionIdentifier ->
  ExecutionRequest ->
  Trace ->
  (OrderExecution, [OrderExecutionEvent])
fromApprovedOrder = acceptApprovedOrder
