-- | Must-10: RiskScreeningPolicy — pure composite screening function (no IO).
module Domain.RiskAssessment.Service.RiskScreeningPolicy (
  -- * Screening entry point
  screenOrder,

  -- * Specification types (Should: decomposed for unit testability)
  RiskLimitSpecification (..),
  isSatisfiedByRiskLimits,
  ComplianceSpecification (..),
  isSatisfiedByCompliance,
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.RiskAssessment.ReasonCode (ReasonCode (..))
import Domain.RiskAssessment.Service.KillSwitchPolicy (evaluateKillSwitch)
import Domain.RiskAssessment.ValueObjects (
  BlackoutWindow (..),
  CompliancePolicy (..),
  Decision (..),
  OrderProposal (..),
  RiskExposure (..),
  RiskLimits (..),
 )

-- ---------------------------------------------------------------------
-- Specification types
-- ---------------------------------------------------------------------

-- | Specification for checking whether current risk exposure is within allowed limits.
newtype RiskLimitSpecification = RiskLimitSpecification
  { limits :: RiskLimits
  }
  deriving stock (Eq, Show)

{- | Returns 'True' when the exposure is within all risk limits.

Must-10 rule 2: reject if any limit is breached.
-}
isSatisfiedByRiskLimits :: RiskLimitSpecification -> RiskExposure -> Bool
isSatisfiedByRiskLimits specification exposure =
  let l = specification.limits
   in exposure.dailyLossRate < l.dailyLossLimit
        && exposure.positionConcentrationRate < l.positionConcentrationLimit
        && exposure.dailyOrderCount < l.dailyOrderLimit

-- | Specification for checking whether an order proposal complies with the policy.
newtype ComplianceSpecification = ComplianceSpecification
  { policy :: CompliancePolicy
  }
  deriving stock (Eq, Show)

{- | Returns 'True' when the proposal is not restricted by any compliance rule.

Must-10 rules 3 and 4: reject on restricted symbol or active blackout window.
-}
isSatisfiedByCompliance :: ComplianceSpecification -> OrderProposal -> UTCTime -> Bool
isSatisfiedByCompliance specification proposal evaluationTime =
  let p = specification.policy
   in not (isRestrictedSymbol p proposal.symbol)
        && not (isBlackoutActive p proposal.symbol evaluationTime)

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

isRestrictedSymbol :: CompliancePolicy -> Text -> Bool
isRestrictedSymbol policy symbol =
  symbol `elem` policy.restrictedSymbols
    || symbol `elem` policy.partnerRestrictedSymbols

isBlackoutActive :: CompliancePolicy -> Text -> UTCTime -> Bool
isBlackoutActive policy symbol evaluationTime =
  any (windowCoversSymbolAt symbol evaluationTime) policy.blackoutWindows

windowCoversSymbolAt :: Text -> UTCTime -> BlackoutWindow -> Bool
windowCoversSymbolAt symbol evaluationTime window =
  window.symbol == symbol
    && evaluationTime >= window.startAt
    && evaluationTime <= window.endAt

-- ---------------------------------------------------------------------
-- Composite screening function (Must-10)
-- ---------------------------------------------------------------------

{- | Screen an order proposal against all risk and compliance rules in priority order.

Must-10 evaluation sequence:

0. Context unavailable → 'RiskEvaluationUnavailable' (fail-closed)
1. Kill switch → 'KillSwitchEnabled'
2. Risk limits  → 'RiskLimitExceeded'
3. Restricted symbols → 'ComplianceRestrictedSymbol'
4. Blackout windows   → 'ComplianceBlackoutActive'
5. All clear          → @Right 'Approved''@

When 'contextAvailable' is 'False', the function immediately returns
@Left 'RiskEvaluationUnavailable'@ (fail-closed behaviour, TST-RG-008).

Pure function — no IO.
-}
screenOrder ::
  -- | Whether the evaluation context is available (fail-closed when 'False').
  Bool ->
  -- | Kill switch state.
  Bool ->
  -- | Applicable risk limits.
  RiskLimits ->
  -- | Current risk exposure.
  RiskExposure ->
  -- | Active compliance policy.
  CompliancePolicy ->
  -- | The order proposal to screen.
  OrderProposal ->
  -- | Point in time for blackout window evaluation.
  UTCTime ->
  Either ReasonCode Decision
screenOrder contextAvailable killSwitchEnabled limits exposure policy proposal evaluationTime
  | not contextAvailable =
      Left RiskEvaluationUnavailable
  | evaluateKillSwitch killSwitchEnabled =
      Left KillSwitchEnabled
  | not (isSatisfiedByRiskLimits (RiskLimitSpecification limits) exposure) =
      Left RiskLimitExceeded
  | isRestrictedSymbol policy proposal.symbol =
      Left ComplianceRestrictedSymbol
  | isBlackoutActive policy proposal.symbol evaluationTime =
      Left ComplianceBlackoutActive
  | otherwise =
      Right Approved'
