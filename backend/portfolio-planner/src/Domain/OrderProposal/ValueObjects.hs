{- | Value objects shared across the portfolio-planner domain.
MUST-04 through MUST-07.
DispatchDecision is defined in ProposalDispatch module to avoid circular imports.
-}
module Domain.OrderProposal.ValueObjects (
  -- * SignalSnapshot (MUST-04)
  SignalSnapshot (..),
  DegradationFlag (..),

  -- * PositionSnapshot (MUST-05)
  PositionSnapshot (..),

  -- * StrategySnapshot (MUST-06)
  StrategySnapshot (..),

  -- * AccountSnapshot (MUST-07)
  AccountSnapshot (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)

-- ---------------------------------------------------------------------
-- MUST-04: SignalSnapshot
-- ---------------------------------------------------------------------

-- | DegradationFlag — モデル品質劣化フラグ。Normal | Warn | Block の 3 値。
data DegradationFlag
  = Normal
  | Warn
  | Block
  deriving stock (Eq, Ord, Show)

-- | SignalSnapshot — シグナル生成メタデータのスナップショット。immutable。
data SignalSnapshot = SignalSnapshot
  { signalVersion :: Text
  , modelVersion :: Text
  , featureVersion :: Text
  , storagePath :: Text
  , degradationFlag :: DegradationFlag
  , requiresComplianceReview :: Bool
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- MUST-05: PositionSnapshot
-- ---------------------------------------------------------------------

-- | PositionSnapshot — 保有ポジションのスナップショット。immutable。
data PositionSnapshot = PositionSnapshot
  { symbol :: Text
  , holdingQty :: Rational
  , asOf :: UTCTime
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- MUST-06: StrategySnapshot
-- ---------------------------------------------------------------------

-- | StrategySnapshot — 戦略パラメータのスナップショット。immutable。
data StrategySnapshot = StrategySnapshot
  { maxOrderCount :: Int
  , maxSingleOrderQty :: Rational
  , rebalanceThreshold :: Rational
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- MUST-07: AccountSnapshot
-- ---------------------------------------------------------------------

-- | AccountSnapshot — 口座残高スナップショット。immutable。
data AccountSnapshot = AccountSnapshot
  { availableCash :: Rational
  , asOf :: UTCTime
  }
  deriving stock (Eq, Show)
