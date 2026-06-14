module UseCase.HypothesisOrchestration.DispatchService (
  -- * Use case function
  checkIdempotency,
) where

import Data.Time (UTCTime)
import Domain.HypothesisOrchestration (Trace)
import Domain.HypothesisOrchestration.DispatchFactory (fromSourceEvent)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  OrchestrationDispatch,
  OrchestrationDispatchIdentifier,
  OrchestrationDispatchRepository (..),
  markDuplicate,
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (SourceEventSnapshot)

{- | UC-AO: 冪等性チェックと OrchestrationDispatch の生成・永続化。

* 既に同一識別子の OrchestrationDispatch が存在する場合は @markDuplicate@ を実行して
  永続化し（監査証跡）、@Left (AlreadyProcessed IdempotencyDuplicateEvent)@ を返す。
* 存在しない場合は @DispatchFactory.fromSourceEvent@ で生成して永続化し、
  @Right dispatch@ を返す。
-}
checkIdempotency ::
  (OrchestrationDispatchRepository m) =>
  OrchestrationDispatchIdentifier ->
  SourceEventSnapshot ->
  Trace ->
  UTCTime ->
  m (Either DomainError OrchestrationDispatch)
checkIdempotency dispatchIdentifier snapshot traceValue now = do
  existing <- find dispatchIdentifier
  case existing of
    Just existingDispatch -> do
      case markDuplicate now existingDispatch of
        Right updatedDispatch -> persist updatedDispatch
        Left _ -> pure ()
      pure (Left (AlreadyProcessed IdempotencyDuplicateEvent))
    Nothing -> do
      let newDispatch = fromSourceEvent dispatchIdentifier snapshot traceValue
      persist newDispatch
      pure (Right newDispatch)
