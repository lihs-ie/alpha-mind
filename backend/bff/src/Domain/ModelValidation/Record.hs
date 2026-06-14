module Domain.ModelValidation.Record (
  ModelValidationStatus (..),
  DegradationFlag (..),
  ModelMetrics (..),
  ModelValidationSummary (..),
  ModelValidationDetail (..),
  modelValidationStatusToText,
  degradationFlagToText,
)
where

import Data.Text (Text)
import Data.Time (UTCTime)

-- | Lifecycle status of a model validation entry.
data ModelValidationStatus
  = ModelValidationStatusCandidate
  | ModelValidationStatusApproved
  | ModelValidationStatusRejected
  deriving stock (Show, Eq)

-- | Convert 'ModelValidationStatus' to OpenAPI string value.
modelValidationStatusToText :: ModelValidationStatus -> Text
modelValidationStatusToText ModelValidationStatusCandidate = "candidate"
modelValidationStatusToText ModelValidationStatusApproved = "approved"
modelValidationStatusToText ModelValidationStatusRejected = "rejected"

-- | Degradation signal flag for a model.
data DegradationFlag
  = DegradationFlagNormal
  | DegradationFlagWarn
  | DegradationFlagBlock
  deriving stock (Show, Eq)

-- | Convert 'DegradationFlag' to OpenAPI string value.
degradationFlagToText :: DegradationFlag -> Text
degradationFlagToText DegradationFlagNormal = "normal"
degradationFlagToText DegradationFlagWarn = "warn"
degradationFlagToText DegradationFlagBlock = "block"

-- | Evaluation metrics for a model validation entry.
data ModelMetrics = ModelMetrics
  { oosReturn :: Double
  , sharpe :: Double
  , maxDrawdown :: Double
  , turnover :: Double
  , pbo :: Double
  , dsr :: Double
  , costAdjustedReturn :: Double
  , slippageAdjustedSharpe :: Double
  }

-- | Read model for model registry list items.
data ModelValidationSummary = ModelValidationSummary
  { modelVersion :: Text
  , status :: ModelValidationStatus
  , degradationFlag :: DegradationFlag
  , createdAt :: UTCTime
  }

-- | Extended model validation detail including metrics.
data ModelValidationDetail = ModelValidationDetail
  { modelVersion :: Text
  , status :: ModelValidationStatus
  , degradationFlag :: DegradationFlag
  , createdAt :: UTCTime
  , metrics :: ModelMetrics
  , requiresComplianceReview :: Maybe Bool
  }
