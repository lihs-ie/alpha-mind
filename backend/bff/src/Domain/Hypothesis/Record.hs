module Domain.Hypothesis.Record (
  HypothesisStatus (..),
  HypothesisInstrumentType (..),
  HypothesisInsiderRisk (..),
  HypothesisPromotionMode (..),
  HypothesisSummary (..),
  HypothesisDetail (..),
  hypothesisStatusToText,
  hypothesisInstrumentTypeToText,
  hypothesisInsiderRiskToText,
  hypothesisPromotionModeToText,
)
where

import Data.Text (Text)
import Data.Time (UTCTime)

-- | Lifecycle status of a hypothesis.
data HypothesisStatus
  = HypothesisStatusDraft
  | HypothesisStatusBacktested
  | HypothesisStatusDemo
  | HypothesisStatusLive
  | HypothesisStatusRejected
  deriving stock (Show, Eq)

-- | Convert 'HypothesisStatus' to OpenAPI string value.
hypothesisStatusToText :: HypothesisStatus -> Text
hypothesisStatusToText HypothesisStatusDraft = "draft"
hypothesisStatusToText HypothesisStatusBacktested = "backtested"
hypothesisStatusToText HypothesisStatusDemo = "demo"
hypothesisStatusToText HypothesisStatusLive = "live"
hypothesisStatusToText HypothesisStatusRejected = "rejected"

-- | Instrument type targeted by a hypothesis.
data HypothesisInstrumentType
  = HypothesisInstrumentTypeETF
  | HypothesisInstrumentTypeStock
  deriving stock (Show, Eq)

-- | Convert 'HypothesisInstrumentType' to OpenAPI string value.
hypothesisInstrumentTypeToText :: HypothesisInstrumentType -> Text
hypothesisInstrumentTypeToText HypothesisInstrumentTypeETF = "ETF"
hypothesisInstrumentTypeToText HypothesisInstrumentTypeStock = "STOCK"

-- | Insider risk level associated with a hypothesis.
data HypothesisInsiderRisk
  = HypothesisInsiderRiskLow
  | HypothesisInsiderRiskMedium
  | HypothesisInsiderRiskHigh
  deriving stock (Show, Eq)

-- | Convert 'HypothesisInsiderRisk' to OpenAPI string value.
hypothesisInsiderRiskToText :: HypothesisInsiderRisk -> Text
hypothesisInsiderRiskToText HypothesisInsiderRiskLow = "low"
hypothesisInsiderRiskToText HypothesisInsiderRiskMedium = "medium"
hypothesisInsiderRiskToText HypothesisInsiderRiskHigh = "high"

-- | Promotion mode for a hypothesis.
data HypothesisPromotionMode
  = HypothesisPromotionModeManual
  | HypothesisPromotionModeAuto
  deriving stock (Show, Eq)

-- | Convert 'HypothesisPromotionMode' to OpenAPI string value.
hypothesisPromotionModeToText :: HypothesisPromotionMode -> Text
hypothesisPromotionModeToText HypothesisPromotionModeManual = "manual"
hypothesisPromotionModeToText HypothesisPromotionModeAuto = "auto"

-- | Read model for hypothesis registry list items.
data HypothesisSummary = HypothesisSummary
  { identifier :: Text
  , symbol :: Text
  , instrumentType :: HypothesisInstrumentType
  , status :: HypothesisStatus
  , title :: Text
  , updatedAt :: UTCTime
  }

-- | Extended hypothesis detail including evidence and evaluation metrics.
data HypothesisDetail = HypothesisDetail
  { identifier :: Text
  , symbol :: Text
  , instrumentType :: HypothesisInstrumentType
  , status :: HypothesisStatus
  , title :: Text
  , updatedAt :: UTCTime
  , sourceEvidence :: [Text]
  , skillVersion :: Text
  , instructionProfileVersion :: Text
  , costAdjustedReturn :: Maybe Double
  , dsr :: Maybe Double
  , pbo :: Maybe Double
  , demoPeriod :: Maybe Text
  , insiderRisk :: Maybe HypothesisInsiderRisk
  , requiresComplianceReview :: Maybe Bool
  , mnpiSelfDeclared :: Maybe Bool
  , autoPromotionEligible :: Maybe Bool
  , promotionMode :: Maybe HypothesisPromotionMode
  , latestFailureSummary :: Maybe Text
  }
