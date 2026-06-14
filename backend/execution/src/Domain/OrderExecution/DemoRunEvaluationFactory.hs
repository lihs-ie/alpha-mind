module Domain.OrderExecution.DemoRunEvaluationFactory (
  fromDemoRunRecord,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.OrderExecution (Trace)
import Domain.OrderExecution.DemoRunEvaluation (
  DemoRunEvaluation,
  DemoRunEvaluationEvent,
  DemoRunEvaluationIdentifier,
  startDemoRun,
 )

{- | Factory: create a DemoRunEvaluation from a demo run record.
Delegates to the aggregate smart constructor. (Must-28)
-}
fromDemoRunRecord ::
  DemoRunEvaluationIdentifier ->
  Text ->
  UTCTime ->
  Trace ->
  (DemoRunEvaluation, [DemoRunEvaluationEvent])
fromDemoRunRecord = startDemoRun
