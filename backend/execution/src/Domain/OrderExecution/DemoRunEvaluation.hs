{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE NoFieldSelectors #-}

module Domain.OrderExecution.DemoRunEvaluation (
  -- * Identifiers
  DemoRunEvaluationIdentifier (..),

  -- * Status enum
  DemoEvaluationStatus (..),

  -- * Value Objects
  DemoPerformance (..),
  PromotionGate (..),

  -- * Aggregate (construct via 'startDemoRun' only; constructor intentionally hidden)
  DemoRunEvaluation,

  -- * Smart constructor
  startDemoRun,

  -- * Commands
  completeDemoRun,
  markPublished,
  shutdownDemoRunEvaluation,

  -- * Domain Events
  DemoRunEvaluationEvent (..),

  -- * Repository Port
  DemoRunEvaluationRepository (..),

  -- * Specification
  DemoRunCompletedSpecification (..),
  module Domain.OrderExecution.Specification,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.OrderExecution (Trace)
import Domain.OrderExecution.Error (ExecutionError (..))
import Domain.OrderExecution.Specification (Specification (..))
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------

newtype DemoRunEvaluationIdentifier = DemoRunEvaluationIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Status enum
-- ---------------------------------------------------------------------

data DemoEvaluationStatus
  = Active
  | Completed
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

-- | DemoPerformance records quantitative evaluation metrics.
data DemoPerformance = DemoPerformance
  { costAdjustedReturn :: Double
  , dsr :: Maybe Double
  , pbo :: Maybe Double
  , demoPeriodDays :: Int
  }
  deriving stock (Eq, Show)

-- | PromotionGate records compliance and risk gate results.
data PromotionGate = PromotionGate
  { instrumentType :: Text
  , insiderRisk :: Bool
  , mnpiSelfDeclared :: Bool
  , requiresComplianceReview :: Bool
  , promotable :: Bool
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Domain Events
-- ---------------------------------------------------------------------

-- | DemoRunCompleted event payload (Must-22).
data DemoRunEvaluationEvent
  = DemoRunCompleted
  { identifier :: DemoRunEvaluationIdentifier
  , demoRun :: Text
  , metrics :: Maybe DemoPerformance
  , trace :: Trace
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate
--
-- Constructor hidden. Access via startDemoRun + command functions.
-- Fields prefixed with dre to avoid HasField conflicts.
-- ---------------------------------------------------------------------

data DemoRunEvaluation = DemoRunEvaluation
  { dreIdentifier :: DemoRunEvaluationIdentifier
  , dreDemoRun :: Text
  , dreStatus :: DemoEvaluationStatus
  , dreStartedAt :: UTCTime
  , dreEndedAt :: Maybe UTCTime
  , drePublished :: Bool
  , dreTrace :: Trace
  , drePerformance :: Maybe DemoPerformance
  , drePromotionGate :: Maybe PromotionGate
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor
-- ---------------------------------------------------------------------

-- | Start a new demo run evaluation in Active status.
startDemoRun ::
  DemoRunEvaluationIdentifier ->
  Text ->
  UTCTime ->
  Trace ->
  (DemoRunEvaluation, [DemoRunEvaluationEvent])
startDemoRun evaluationIdentifier demoRunIdentifier startTime traceValue =
  let evaluation =
        DemoRunEvaluation
          { dreIdentifier = evaluationIdentifier
          , dreDemoRun = demoRunIdentifier
          , dreStatus = Active
          , dreStartedAt = startTime
          , dreEndedAt = Nothing
          , drePublished = False
          , dreTrace = traceValue
          , drePerformance = Nothing
          , drePromotionGate = Nothing
          }
   in (evaluation, [])

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | CompleteDemoRun — transitions to Completed status.
Rejected if already Completed (Must-17).
-}
completeDemoRun ::
  UTCTime ->
  Maybe DemoPerformance ->
  Maybe PromotionGate ->
  DemoRunEvaluation ->
  Either ExecutionError (DemoRunEvaluation, [DemoRunEvaluationEvent])
completeDemoRun endTime maybePerformance maybeGate evaluation =
  case evaluation.status of
    Completed ->
      Left (InvalidStateTransition "completed" "CompleteDemoRun")
    Active ->
      let updated =
            evaluation
              { dreStatus = Completed
              , dreEndedAt = Just endTime
              , drePerformance = maybePerformance
              , drePromotionGate = maybeGate
              }
          event =
            DemoRunCompleted
              { identifier = evaluation.identifier
              , demoRun = evaluation.demoRun
              , metrics = maybePerformance
              , trace = evaluation.trace
              }
       in Right (updated, [event])

{- | MarkPublished — sets published = True on a Completed evaluation.
Rejected if already published (Must-17).
-}
markPublished ::
  DemoRunEvaluation ->
  Either ExecutionError DemoRunEvaluation
markPublished evaluation =
  case evaluation.status of
    Active ->
      Left (InvalidStateTransition "active" "MarkPublished")
    Completed ->
      if evaluation.published
        then Left (InvalidStateTransition "published" "MarkPublished")
        else Right evaluation{drePublished = True}

-- | ShutdownDemoRunEvaluation — administrative command, pure.
shutdownDemoRunEvaluation :: DemoRunEvaluation -> DemoRunEvaluation
shutdownDemoRunEvaluation = id

-- ---------------------------------------------------------------------
-- Repository Port
-- ---------------------------------------------------------------------

class (Monad m) => DemoRunEvaluationRepository m where
  findDemoRunEvaluation :: DemoRunEvaluationIdentifier -> m (Maybe DemoRunEvaluation)
  persistDemoRunEvaluation :: DemoRunEvaluation -> m ()
  terminateDemoRunEvaluation :: DemoRunEvaluationIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Specification
-- ---------------------------------------------------------------------

-- | DemoRunCompletedSpecification: satisfied when status=Completed and published=False (Must-31).
newtype DemoRunCompletedSpecification = DemoRunCompletedSpecification ()
  deriving stock (Eq, Show)

instance Specification DemoRunCompletedSpecification DemoRunEvaluation where
  isSatisfiedBy _ evaluation =
    evaluation.status == Completed && not evaluation.published

-- ---------------------------------------------------------------------
-- Read-only field access via HasField
-- ---------------------------------------------------------------------

instance HasField "identifier" DemoRunEvaluation DemoRunEvaluationIdentifier where
  getField DemoRunEvaluation{dreIdentifier = x} = x

instance HasField "demoRun" DemoRunEvaluation Text where
  getField DemoRunEvaluation{dreDemoRun = x} = x

instance HasField "status" DemoRunEvaluation DemoEvaluationStatus where
  getField DemoRunEvaluation{dreStatus = x} = x

instance HasField "startedAt" DemoRunEvaluation UTCTime where
  getField DemoRunEvaluation{dreStartedAt = x} = x

instance HasField "endedAt" DemoRunEvaluation (Maybe UTCTime) where
  getField DemoRunEvaluation{dreEndedAt = x} = x

instance HasField "published" DemoRunEvaluation Bool where
  getField DemoRunEvaluation{drePublished = x} = x

instance HasField "trace" DemoRunEvaluation Trace where
  getField DemoRunEvaluation{dreTrace = x} = x

instance HasField "performance" DemoRunEvaluation (Maybe DemoPerformance) where
  getField DemoRunEvaluation{drePerformance = x} = x

instance HasField "promotionGate" DemoRunEvaluation (Maybe PromotionGate) where
  getField DemoRunEvaluation{drePromotionGate = x} = x
