{- | Use case: Sync kill switch state.

Handles @operation.kill_switch.changed@ events.
Applies the new kill switch state to all PROPOSED assessments
and records idempotency to prevent reprocessing.

Design reference: §4.4 risk-guard domain model design.
-}
module UseCase.SyncKillSwitch (
  -- * Input type
  KillSwitchChangedPayload (..),

  -- * Result
  SyncKillSwitchResult (..),

  -- * Use case
  syncKillSwitch,

  -- * Port re-exports (for caller convenience)
  OrderRiskAssessmentRepository,
  IdempotencyKeyRepository,
) where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.ULID (ULID)
import Domain.RiskAssessment.Aggregate (
  OrderRiskAssessment,
  OrderRiskAssessmentRepository (..),
  OrderStatus (..),
  syncKillSwitchState,
 )
import Domain.RiskAssessment.Aggregate qualified as AssessmentRepository
import Domain.RiskAssessment.Port.IdempotencyKeyRepository (IdempotencyKeyRepository (..))
import Domain.RiskAssessment.Port.IdempotencyKeyRepository qualified as IdempotencyRepository

-- | Service identifier used for idempotency key namespacing.
serviceIdentifier :: Text
serviceIdentifier = "risk-guard"

-- ---------------------------------------------------------------------
-- Input type
-- ---------------------------------------------------------------------

-- | Payload from an @operation.kill_switch.changed@ integration event.
data KillSwitchChangedPayload = KillSwitchChangedPayload
  { identifier :: ULID
  -- ^ Event identifier used as idempotency key.
  , enabled :: Bool
  -- ^ New kill switch state.
  , trace :: ULID
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Result type (Must-10)
-- ---------------------------------------------------------------------

{- | Result of the 'syncKillSwitch' use case.

Must-10: distinguishes retryable vs non-retryable failures.
-}
data SyncKillSwitchResult
  = -- | Kill switch state applied successfully.
    SyncKillSwitchApplied
  | -- | Duplicate event — already processed; no side effects.
    SyncKillSwitchDuplicate
  | -- | Processing failed. Bool = retryable.
    SyncKillSwitchFailed Text Bool
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case (Must-04, Must-07, Must-09)
-- ---------------------------------------------------------------------

{- | UC-RG-02: Apply a kill switch state change to all PROPOSED assessments.

Processing order (§4.4 Must-09):
1. Idempotency check (Must-07): duplicate → 'SyncKillSwitchDuplicate'
2. Fetch all PROPOSED assessments via 'OrderRiskAssessmentRepository.findByStatus'
3. Apply 'syncKillSwitchState' domain command to each assessment
4. Persist each updated assessment via 'OrderRiskAssessmentRepository.persist'
5. Record idempotency key (Must-07)

Must-04: uses type class constraints only — no 'IO' in this function.
Must-12: no infrastructure imports.
-}
syncKillSwitch ::
  ( Monad m
  , OrderRiskAssessmentRepository m
  , IdempotencyKeyRepository m
  ) =>
  -- | Incoming @operation.kill_switch.changed@ event payload.
  KillSwitchChangedPayload ->
  m SyncKillSwitchResult
syncKillSwitch payload = do
  -- Step 1 (Must-07): idempotency check
  let eventKey = Text.pack (show payload.identifier)
  alreadyProcessed <- IdempotencyRepository.find serviceIdentifier eventKey
  if alreadyProcessed
    then pure SyncKillSwitchDuplicate
    else applyKillSwitchChange payload eventKey

-- | Processing body after idempotency check passes.
applyKillSwitchChange ::
  ( Monad m
  , OrderRiskAssessmentRepository m
  , IdempotencyKeyRepository m
  ) =>
  KillSwitchChangedPayload ->
  Text ->
  m SyncKillSwitchResult
applyKillSwitchChange payload eventKey = do
  -- Step 2 (Must-09): fetch all PROPOSED assessments
  proposedAssessments <- AssessmentRepository.findByStatus Proposed

  -- Step 3 & 4 (Must-09): apply domain command and persist each assessment
  mapM_ (persistUpdatedAssessment payload.enabled) proposedAssessments

  -- Step 5 (Must-07): record idempotency key
  IdempotencyRepository.persist serviceIdentifier eventKey

  pure SyncKillSwitchApplied

-- | Apply kill switch state update and persist a single assessment.
persistUpdatedAssessment ::
  (Monad m, OrderRiskAssessmentRepository m) =>
  Bool ->
  OrderRiskAssessment ->
  m ()
persistUpdatedAssessment newState assessment = do
  let updatedAssessment = syncKillSwitchState newState assessment
  AssessmentRepository.persist updatedAssessment
