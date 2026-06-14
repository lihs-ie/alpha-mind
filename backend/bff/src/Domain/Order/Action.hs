{- | Domain logic for order state transitions.

Encodes the state machine from @状態遷移設計.md@:

  * PROPOSED → APPROVED  (approve; only when kill switch is disabled)
  * PROPOSED → REJECTED  (reject)
  * FAILED   → PROPOSED  (retry)

Any other transition is invalid and returns a 'OrderTransitionError'.
-}
module Domain.Order.Action (
  OrderTransitionError (..),
  validateApprove,
  validateReject,
  validateRetry,
)
where

import Domain.Order.Order (OrderStatus (..))

-- ---------------------------------------------------------------------------
-- Error type
-- ---------------------------------------------------------------------------

-- | Reason why a state transition was refused.
data OrderTransitionError
  = -- | The current state does not allow this action.
    InvalidStateTransition OrderStatus String
  | -- | Kill switch is active; approve and retry are blocked.
    KillSwitchActive
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Transition validators
-- ---------------------------------------------------------------------------

{- | Validate an approve action.

PROPOSED → APPROVED is allowed only when the kill switch is disabled.
All other states are terminal or irreversible.
-}
validateApprove :: Bool -> OrderStatus -> Either OrderTransitionError ()
validateApprove killSwitchEnabled currentStatus =
  case currentStatus of
    Proposed ->
      if killSwitchEnabled
        then Left KillSwitchActive
        else Right ()
    other -> Left (InvalidStateTransition other "approve")

{- | Validate a reject action.

PROPOSED → REJECTED is always allowed (kill switch does not block rejection).
-}
validateReject :: OrderStatus -> Either OrderTransitionError ()
validateReject currentStatus =
  case currentStatus of
    Proposed -> Right ()
    other -> Left (InvalidStateTransition other "reject")

{- | Validate a retry action.

FAILED → PROPOSED is allowed only when the kill switch is disabled.
-}
validateRetry :: Bool -> OrderStatus -> Either OrderTransitionError ()
validateRetry killSwitchEnabled currentStatus =
  case currentStatus of
    Failed ->
      if killSwitchEnabled
        then Left KillSwitchActive
        else Right ()
    other -> Left (InvalidStateTransition other "retry")
