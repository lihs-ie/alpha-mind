module UseCase.CompleteDemoRun (
  -- * Port
  DemoCompletionEventPublisher (..),

  -- * UseCase-layer types
  HypothesisIdentifier (..),
  DemoRunIdentifier (..),

  -- * Input type
  DemoRunCompletionTrigger (..),

  -- * Result type
  CompleteDemoRunResult (..),

  -- * Use case
  completeDemoRun,
) where

import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.DemoRunEvaluation (
  DemoPerformance (..),
  DemoRunEvaluation,
  DemoRunEvaluationIdentifier (..),
  DemoRunEvaluationRepository (..),
  PromotionGate (..),
  markPublished,
 )
import Domain.OrderExecution.DemoRunEvaluation qualified as DemoRunEvaluationDomain
import Domain.OrderExecution.DemoRunEvaluationFactory (fromDemoRunRecord)
import Domain.OrderExecution.ReasonCode (ReasonCode (..))

-- ---------------------------------------------------------------------
-- UseCase-layer types
-- ---------------------------------------------------------------------

-- | Identifier for a hypothesis (wraps ULID)
newtype HypothesisIdentifier = HypothesisIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- | Identifier for a demo run (wraps Text)
newtype DemoRunIdentifier = DemoRunIdentifier {value :: Text}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Port: DemoCompletionEventPublisher
-- ---------------------------------------------------------------------

{- | DemoCompletionEventPublisher: Pub/Sub へデモ完了イベントを発行する Port。
実装は presentation / infra 層 (Issue #49) に委ねる。
-}
class (Monad m) => DemoCompletionEventPublisher m where
  publishHypothesisDemoCompleted ::
    HypothesisIdentifier ->
    DemoRunIdentifier ->
    DemoPerformance ->
    Trace ->
    m ()

-- ---------------------------------------------------------------------
-- Input type
-- ---------------------------------------------------------------------

{- | DemoRunCompletionTrigger: デモ完了トリガーを表す UseCase 層内部型。
Presentation 層から受け取る。
-}
data DemoRunCompletionTrigger = DemoRunCompletionTrigger
  { identifier :: DemoRunEvaluationIdentifier
  , hypothesis :: HypothesisIdentifier
  , demoRun :: DemoRunIdentifier
  , startedAt :: UTCTime
  , endedAt :: UTCTime
  , trace :: Trace
  , performance :: Maybe DemoPerformance
  , promotionGate :: Maybe PromotionGate
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Result type
-- ---------------------------------------------------------------------

-- | UseCase の結果型。3 ケース。
data CompleteDemoRunResult
  = CompleteDemoRunSucceeded
  | CompleteDemoRunFailed ReasonCode
  | CompleteDemoRunDuplicate
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case
-- ---------------------------------------------------------------------

{- | UC-EX-03: デモ完了トリガーを受信し、DemoRunEvaluation の完了・発行をオーケストレーションする。

処理順序:
1. findDemoRunEvaluation identifier
   - 既存で published=True → CompleteDemoRunDuplicate (Publisher を呼ばない)
   - 既存で status=Completed → markPublished → publishHypothesisDemoCompleted →
     persistDemoRunEvaluation → CompleteDemoRunSucceeded
   - 存在しない → fromDemoRunRecord で新規作成 → completeDemoRun コマンド →
     persistDemoRunEvaluation (1回目, Completed) → publishHypothesisDemoCompleted →
     markPublished → persistDemoRunEvaluation (2回目, published=True) →
     CompleteDemoRunSucceeded
-}
completeDemoRun ::
  ( Monad m
  , DemoRunEvaluationRepository m
  , DemoCompletionEventPublisher m
  ) =>
  UTCTime ->
  DemoRunCompletionTrigger ->
  m CompleteDemoRunResult
completeDemoRun currentTime trigger = do
  existingEvaluation <- findDemoRunEvaluation trigger.identifier
  case existingEvaluation of
    Just evaluation
      | evaluation.published ->
          pure CompleteDemoRunDuplicate
    Just evaluation ->
      -- Already exists but not published (e.g., Completed but not yet published)
      publishExistingEvaluation trigger evaluation
    Nothing ->
      createAndPublishEvaluation currentTime trigger

-- | Publish an already-existing (Completed, unpublished) DemoRunEvaluation.
publishExistingEvaluation ::
  ( Monad m
  , DemoRunEvaluationRepository m
  , DemoCompletionEventPublisher m
  ) =>
  DemoRunCompletionTrigger ->
  DemoRunEvaluation ->
  m CompleteDemoRunResult
publishExistingEvaluation trigger evaluation =
  case markPublished evaluation of
    Left domainError ->
      pure (CompleteDemoRunFailed (domainErrorToReasonCode domainError))
    Right publishedEvaluation -> do
      let performanceValue = fromMaybe defaultPerformance evaluation.performance
      publishHypothesisDemoCompleted
        trigger.hypothesis
        trigger.demoRun
        performanceValue
        trigger.trace
      persistDemoRunEvaluation publishedEvaluation
      pure CompleteDemoRunSucceeded

-- | Create a new DemoRunEvaluation from a demo run record, complete it, and publish.
createAndPublishEvaluation ::
  ( Monad m
  , DemoRunEvaluationRepository m
  , DemoCompletionEventPublisher m
  ) =>
  UTCTime ->
  DemoRunCompletionTrigger ->
  m CompleteDemoRunResult
createAndPublishEvaluation _currentTime trigger = do
  let (newEvaluation, _startEvents) =
        fromDemoRunRecord trigger.identifier trigger.demoRun.value trigger.startedAt trigger.trace
  case DemoRunEvaluationDomain.completeDemoRun
    trigger.endedAt
    trigger.performance
    trigger.promotionGate
    newEvaluation of
    Left domainError ->
      pure (CompleteDemoRunFailed (domainErrorToReasonCode domainError))
    Right (completedEvaluation, _completeEvents) -> do
      -- First persist: completed state (Must-15 step 1)
      persistDemoRunEvaluation completedEvaluation
      -- Publish before persisting published state (Must-15 step 2)
      let performanceValue = fromMaybe defaultPerformance trigger.performance
      publishHypothesisDemoCompleted
        trigger.hypothesis
        trigger.demoRun
        performanceValue
        trigger.trace
      -- Mark published and persist (Must-15 step 3)
      case markPublished completedEvaluation of
        Left domainError ->
          pure (CompleteDemoRunFailed (domainErrorToReasonCode domainError))
        Right publishedEvaluation -> do
          persistDemoRunEvaluation publishedEvaluation
          pure CompleteDemoRunSucceeded

-- | Convert a domain error to a ReasonCode for the result type.
domainErrorToReasonCode :: (Show e) => e -> ReasonCode
domainErrorToReasonCode _domainError = InternalError

-- | Default performance value used when trigger.performance is Nothing.
defaultPerformance :: DemoPerformance
defaultPerformance =
  DemoPerformance
    { costAdjustedReturn = 0.0
    , dsr = Nothing
    , pbo = Nothing
    , demoPeriodDays = 0
    }
