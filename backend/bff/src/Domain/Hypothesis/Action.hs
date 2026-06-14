{- | Domain logic for hypothesis state transitions.

Encodes the state machine from @状態遷移設計.md@ section 6:

  * demo → live    (promote; only when transition conditions are met)
  * demo → rejected (reject)
  * various → retest requested (retest)

Valid source states per action:

  * promote: @demo@ only
  * reject:  @demo@ only
  * retest:  @demo@ or @backtested@ only

Any other transition is invalid and returns a 'HypothesisTransitionError'.
-}
module Domain.Hypothesis.Action (
  HypothesisTransitionError (..),
  validatePromote,
  validateReject,
  validateRetest,
)
where

import Domain.Hypothesis.Record (HypothesisStatus (..))

-- ---------------------------------------------------------------------------
-- Error type
-- ---------------------------------------------------------------------------

-- | Reason why a hypothesis state transition was refused.
data HypothesisTransitionError
  = -- | The current state does not allow this action.
    InvalidStateTransition HypothesisStatus String
  | -- | Hypothesis has @requiresComplianceReview=true@; live transition blocked.
    ComplianceReviewRequired
  | -- | The MNPI self-declaration is missing or false; promote is blocked.
    MnpiSelfDeclarationMissing
  | -- | Demo period has not reached the minimum 30-day requirement.
    DemoPeriodInsufficient
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------------
-- Transition validators
-- ---------------------------------------------------------------------------

{- | Validate a promote action (demo → live).

Returns 'Right ()' when all of the following hold:
  * current status is @demo@
  * @requiresComplianceReview@ is not @true@
  * @mnpiSelfDeclared@ is @true@

Callers are responsible for symbol restriction checks and demoPeriodDays
validation before calling this function.
-}
validatePromote ::
  -- | Current status.
  HypothesisStatus ->
  -- | @requiresComplianceReview@ flag from Firestore.
  Maybe Bool ->
  -- | @mnpiSelfDeclared@ flag from Firestore.
  Maybe Bool ->
  Either HypothesisTransitionError ()
validatePromote currentStatus maybeRequiresComplianceReview maybeMnpiSelfDeclared =
  case currentStatus of
    HypothesisStatusDemo -> do
      case maybeRequiresComplianceReview of
        Just True -> Left ComplianceReviewRequired
        _ -> pure ()
      case maybeMnpiSelfDeclared of
        Just True -> pure ()
        _ -> Left MnpiSelfDeclarationMissing
    other -> Left (InvalidStateTransition other "promote")

{- | Validate a reject action (demo → rejected).

Only @demo@ hypotheses may be rejected via the BFF API.
-}
validateReject ::
  HypothesisStatus ->
  Either HypothesisTransitionError ()
validateReject currentStatus =
  case currentStatus of
    HypothesisStatusDemo -> Right ()
    other -> Left (InvalidStateTransition other "reject")

{- | Validate a retest request (demo or backtested → retest requested).

Emits @hypothesis.retest.requested@ event; does not change Firestore status.
Allowed from @demo@ or @backtested@.
-}
validateRetest ::
  HypothesisStatus ->
  Either HypothesisTransitionError ()
validateRetest currentStatus =
  case currentStatus of
    HypothesisStatusDemo -> Right ()
    HypothesisStatusBacktested -> Right ()
    other -> Left (InvalidStateTransition other "retest")
