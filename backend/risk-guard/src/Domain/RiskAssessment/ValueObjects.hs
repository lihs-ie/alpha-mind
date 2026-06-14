{- | Shared value objects for the RiskAssessment domain.

Separated from 'Domain.RiskAssessment.Aggregate' to break the cyclic dependency
with 'Domain.RiskAssessment.Service.RiskScreeningPolicy'.
-}
module Domain.RiskAssessment.ValueObjects (
  -- * Trade side
  Side (..),

  -- * Decision
  Decision (..),

  -- * Risk limits / exposure
  RiskLimits (..),
  RiskExposure (..),

  -- * Compliance
  BlackoutWindow (..),
  CompliancePolicy (..),

  -- * Proposal entity
  OrderProposal (..),

  -- * Identifiers
  OrderRiskAssessmentIdentifier (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.RiskAssessment.ReasonCode (OperatorActionReasonCode)

-- | Identifier for OrderRiskAssessment aggregate. Must-03.
newtype OrderRiskAssessmentIdentifier = OrderRiskAssessmentIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- | Trade side.
data Side
  = Buy
  | Sell
  deriving stock (Eq, Ord, Show)

-- | Screening decision emitted by the domain service.
data Decision
  = Approved'
  | Rejected'
  deriving stock (Eq, Ord, Show)

-- | Must-04: Risk limit thresholds (immutable).
data RiskLimits = RiskLimits
  { dailyLossLimit :: Double
  , positionConcentrationLimit :: Double
  , dailyOrderLimit :: Int
  }
  deriving stock (Eq, Show)

-- | Must-06: Current risk exposure snapshot (immutable).
data RiskExposure = RiskExposure
  { dailyLossRate :: Double
  , positionConcentrationRate :: Double
  , dailyOrderCount :: Int
  }
  deriving stock (Eq, Show)

-- | Must-08: Blackout window for a specific symbol (immutable).
data BlackoutWindow = BlackoutWindow
  { symbol :: Text
  , startAt :: UTCTime
  , endAt :: UTCTime
  , actionReasonCode :: OperatorActionReasonCode
  }
  deriving stock (Eq, Show)

-- | Must-05: Compliance policy containing restricted symbols and blackout windows (immutable).
data CompliancePolicy = CompliancePolicy
  { restrictedSymbols :: [Text]
  , partnerRestrictedSymbols :: [Text]
  , blackoutWindows :: [BlackoutWindow]
  }
  deriving stock (Eq, Show)

-- | Must-02: Order proposal submitted for risk screening.
data OrderProposal = OrderProposal
  { identifier :: OrderRiskAssessmentIdentifier
  , symbol :: Text
  , side :: Side
  , qty :: Double
  }
  deriving stock (Eq, Show)
