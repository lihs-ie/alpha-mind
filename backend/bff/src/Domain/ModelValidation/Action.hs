{- | Domain logic for model validation state transitions.

Encodes the state machine from @状態遷移設計.md@ section 5:

  * candidate → approved  (approve; blocked when @requiresComplianceReview=true@)
  * candidate → rejected  (reject)

Both @approved@ and @rejected@ are terminal: no further transitions are allowed.
-}
module Domain.ModelValidation.Action (
  ModelValidationTransitionError (..),
  validateApprove,
  validateReject,
)
where

import Domain.ModelValidation.Record (ModelValidationStatus (..))

-- ---------------------------------------------------------------------------
-- Error type
-- ---------------------------------------------------------------------------

-- | Reason why a model validation state transition was refused.
data ModelValidationTransitionError
  = -- | The current state does not allow this action.
    InvalidStateTransition ModelValidationStatus String
  | -- | Model requires compliance review; approve is blocked.
    ComplianceReviewRequired
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Transition validators
-- ---------------------------------------------------------------------------

{- | Validate an approve action (candidate → approved).

Returns 'Right ()' when all of the following hold:

  * current status is @candidate@
  * @requiresComplianceReview@ is not @true@

Per 安全性・コンプライアンス: "Walk-forward/DSR/PBO 通過 + コンプライアンスレビュー済みでないと本番利用不可".
-}
validateApprove ::
  -- | Current status.
  ModelValidationStatus ->
  -- | @requiresComplianceReview@ flag from Firestore.
  Maybe Bool ->
  Either ModelValidationTransitionError ()
validateApprove currentStatus maybeRequiresComplianceReview =
  case currentStatus of
    ModelValidationStatusCandidate ->
      case maybeRequiresComplianceReview of
        Just True -> Left ComplianceReviewRequired
        _ -> Right ()
    other -> Left (InvalidStateTransition other "approve")

{- | Validate a reject action (candidate → rejected).

Only @candidate@ model validations may be rejected.
-}
validateReject ::
  -- | Current status.
  ModelValidationStatus ->
  Either ModelValidationTransitionError ()
validateReject currentStatus =
  case currentStatus of
    ModelValidationStatusCandidate -> Right ()
    other -> Left (InvalidStateTransition other "reject")
