-- | Must-09: KillSwitchPolicy — pure function, no IO.
module Domain.RiskAssessment.Service.KillSwitchPolicy (
  evaluateKillSwitch,
) where

{- | Returns 'True' when the kill switch is enabled, indicating the order should be rejected.

Must-09: Pure function with no IO or external dependencies.
-}
evaluateKillSwitch ::
  -- | Whether the kill switch is currently enabled.
  Bool ->
  -- | @True@ means the order must be rejected.
  Bool
evaluateKillSwitch = id
