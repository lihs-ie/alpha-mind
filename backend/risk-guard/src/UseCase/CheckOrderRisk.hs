{- | Use case: Check order risk.

Orchestrates idempotency guard, domain factory, risk evaluation,
persistence and integration event publishing.

Design reference: §4.4 risk-guard domain model design.
-}
module UseCase.CheckOrderRisk (
  -- * Result
  CheckOrderRiskResult (..),

  -- * Use case
  checkOrderRisk,

  -- * Port re-exports (for caller convenience)
  OrderRiskAssessmentRepository,
  IdempotencyKeyRepository,
  RiskEventPublisher,

  -- * Payload and settings re-exports (for presentation layer)
  OrdersProposedPayload (..),
  RiskLimits,
  CompliancePolicy,
  RiskExposure,
) where

import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Domain.RiskAssessment.Aggregate (
  Decision (..),
  OrderRiskAssessment,
  OrderRiskAssessmentRepository (..),
  OrdersApprovedPayload (..),
  OrdersRejectedPayload (..),
  RiskEventPublisher (..),
  evaluateOrderRisk,
 )
import Domain.RiskAssessment.Aggregate qualified as AssessmentRepository
import Domain.RiskAssessment.Error (DomainError (..))
import Domain.RiskAssessment.Factory (OrdersProposedPayload (..), fromOrdersProposed)
import Domain.RiskAssessment.Port.IdempotencyKeyRepository (IdempotencyKeyRepository (..))
import Domain.RiskAssessment.Port.IdempotencyKeyRepository qualified as IdempotencyRepository
import Domain.RiskAssessment.ReasonCode (ReasonCode)
import Domain.RiskAssessment.ValueObjects (
  CompliancePolicy,
  RiskExposure,
  RiskLimits,
 )

-- | Service identifier used for idempotency key namespacing.
serviceIdentifier :: Text
serviceIdentifier = "risk-guard"

-- ---------------------------------------------------------------------
-- Result type (Must-10, Must-11)
-- ---------------------------------------------------------------------

{- | Result of the 'checkOrderRisk' use case.

Must-10: distinguishes retryable vs non-retryable failures.
-}
data CheckOrderRiskResult
  = -- | Order approved — risk screening passed.
    CheckOrderRiskApproved
  | -- | Order rejected — risk screening found a violation.
    CheckOrderRiskRejected ReasonCode
  | -- | Duplicate event — already processed; no side effects.
    CheckOrderRiskDuplicate
  | -- | Processing failed. Bool = retryable.
    CheckOrderRiskFailed Text Bool
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case (Must-03, Must-05, Must-06, Must-08)
-- ---------------------------------------------------------------------

{- | UC-RG-01: Evaluate order risk for an @orders.proposed@ event.

Processing order (§4.4 Must-08):
1. Idempotency check (Must-05): duplicate → 'CheckOrderRiskDuplicate'
2. Construct 'OrderRiskAssessment' via 'fromOrdersProposed' factory
3. Load existing assessment via 'OrderRiskAssessmentRepository.find'
4. Call 'evaluateOrderRisk' domain command
5. Persist assessment via 'OrderRiskAssessmentRepository.persist'
6. Publish integration event via 'RiskEventPublisher'
7. Record idempotency key (Must-06)

Must-03: uses type class constraints only — no 'IO' in this function.
Must-12: no infrastructure imports.
-}
checkOrderRisk ::
  ( Monad m
  , OrderRiskAssessmentRepository m
  , IdempotencyKeyRepository m
  , RiskEventPublisher m
  ) =>
  -- | Wall-clock time (injected by caller).
  UTCTime ->
  -- | Whether the kill switch is currently enabled.
  Bool ->
  -- | Risk limits from settings.
  RiskLimits ->
  -- | Compliance policy from settings.
  CompliancePolicy ->
  -- | Current risk exposure snapshot.
  RiskExposure ->
  -- | Incoming @orders.proposed@ event payload.
  OrdersProposedPayload ->
  m CheckOrderRiskResult
checkOrderRisk currentTime killSwitchEnabled riskLimits compliancePolicy riskExposure payload = do
  -- Step 1 (Must-05): idempotency check
  let eventKey = Text.pack (show payload.identifier)
  alreadyProcessed <- IdempotencyRepository.find serviceIdentifier eventKey
  if alreadyProcessed
    then pure CheckOrderRiskDuplicate
    else processOrderRisk currentTime killSwitchEnabled riskLimits compliancePolicy riskExposure payload eventKey

-- | Processing body after idempotency check passes.
processOrderRisk ::
  ( Monad m
  , OrderRiskAssessmentRepository m
  , IdempotencyKeyRepository m
  , RiskEventPublisher m
  ) =>
  UTCTime ->
  Bool ->
  RiskLimits ->
  CompliancePolicy ->
  RiskExposure ->
  OrdersProposedPayload ->
  Text ->
  m CheckOrderRiskResult
processOrderRisk currentTime killSwitchEnabled riskLimits compliancePolicy riskExposure payload eventKey = do
  -- Step 2 (Must-08): construct assessment via factory
  case fromOrdersProposed payload killSwitchEnabled riskLimits compliancePolicy riskExposure currentTime of
    Left domainError ->
      -- Must-11: validation error → retryable = False
      pure (CheckOrderRiskFailed (domainErrorMessage domainError) (isRetryableDomainError domainError))
    Right initialAssessment -> do
      -- Step 3 (Must-08): load existing assessment from repository
      let assessmentIdentifier = initialAssessment.identifier
      existingAssessment <- AssessmentRepository.find assessmentIdentifier
      let assessment = resolveAssessment existingAssessment initialAssessment

      -- Step 4 (Must-08): run domain evaluation command
      case evaluateOrderRisk currentTime assessment of
        Left (AlreadyProcessed _) ->
          -- Must-11: AlreadyProcessed is idempotent success — return duplicate, not failure.
          pure CheckOrderRiskDuplicate
        Left domainError ->
          pure (CheckOrderRiskFailed (domainErrorMessage domainError) (isRetryableDomainError domainError))
        Right (evaluatedAssessment, _events) -> do
          -- Step 5 (Must-08): persist updated assessment
          AssessmentRepository.persist evaluatedAssessment

          -- Step 6 (Must-08): publish integration event
          publishResult <- publishDecision evaluatedAssessment

          -- Step 7 (Must-06): record idempotency key after side effects succeed
          IdempotencyRepository.persist serviceIdentifier eventKey

          pure publishResult

-- | Select existing assessment from repository, or use the freshly constructed one.
resolveAssessment :: Maybe OrderRiskAssessment -> OrderRiskAssessment -> OrderRiskAssessment
resolveAssessment (Just existing) _ = existing
resolveAssessment Nothing fresh = fresh

-- | Publish the appropriate integration event based on the evaluation decision.
publishDecision ::
  (Monad m, RiskEventPublisher m) =>
  OrderRiskAssessment ->
  m CheckOrderRiskResult
publishDecision assessment =
  case assessment.decision of
    Just Approved' -> do
      let evaluationTime = case assessment.evaluatedAt of
            Just t -> t
            Nothing -> error "publishDecision: Approved assessment must have evaluatedAt"
      let approvedPayload =
            OrdersApprovedPayload
              { identifier = assessment.identifier
              , trace = assessment.trace
              , reasonCode = assessment.reasonCode
              , actionReasonCode = assessment.actionReasonCode
              , evaluatedAt = evaluationTime
              }
      publishOrdersApproved approvedPayload
      pure CheckOrderRiskApproved
    Just Rejected' ->
      case assessment.reasonCode of
        Just code -> do
          let rejectedPayload =
                OrdersRejectedPayload
                  { identifier = assessment.identifier
                  , reasonCode = code
                  , trace = assessment.trace
                  }
          publishOrdersRejected rejectedPayload
          pure (CheckOrderRiskRejected code)
        Nothing ->
          pure
            ( CheckOrderRiskFailed
                "Rejected assessment is missing reasonCode"
                False
            )
    Nothing ->
      pure (CheckOrderRiskFailed "Assessment has no decision after evaluation" False)

-- ---------------------------------------------------------------------
-- Internal helpers (Must-10, Must-11)
-- ---------------------------------------------------------------------

{- | Must-11: classify 'DomainError' as retryable or non-retryable.
Note: 'AlreadyProcessed' is handled separately as 'CheckOrderRiskDuplicate' before this is called.
-}
isRetryableDomainError :: DomainError -> Bool
isRetryableDomainError (AlreadyProcessed _) = False
isRetryableDomainError (InvalidStateTransition _ _) = False
isRetryableDomainError (MissingRequiredFields _) = False
isRetryableDomainError (InvariantViolation _ _) = False

-- | Extract a human-readable message from a 'DomainError'.
domainErrorMessage :: DomainError -> Text
domainErrorMessage (AlreadyProcessed context) = "already processed: " <> context
domainErrorMessage (InvalidStateTransition from action) =
  "invalid state transition from " <> from <> " for " <> action
domainErrorMessage (MissingRequiredFields context) = "missing required fields: " <> context
domainErrorMessage (InvariantViolation location context) =
  "invariant violation at " <> location <> ": " <> context
