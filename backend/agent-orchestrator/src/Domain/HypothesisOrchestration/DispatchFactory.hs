module Domain.HypothesisOrchestration.DispatchFactory (
  -- * Factory (Must-32)
  fromSourceEvent,
) where

import Domain.HypothesisOrchestration (Trace)
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  OrchestrationDispatch,
  OrchestrationDispatchIdentifier,
  startDispatch,
 )
import Domain.HypothesisOrchestration.ValueObjects (
  SourceEventSnapshot,
  sourceEventSnapshotEventType,
 )

-- ---------------------------------------------------------------------
-- Factory (Must-32)
-- ---------------------------------------------------------------------

-- | Must-32: SourceEventSnapshot から OrchestrationDispatch を生成するファクトリ。
fromSourceEvent ::
  OrchestrationDispatchIdentifier ->
  SourceEventSnapshot ->
  Trace ->
  OrchestrationDispatch
fromSourceEvent dispatchIdentifier snapshot traceValue =
  let sourceEventType = sourceEventSnapshotEventType snapshot
   in startDispatch dispatchIdentifier snapshot sourceEventType traceValue
