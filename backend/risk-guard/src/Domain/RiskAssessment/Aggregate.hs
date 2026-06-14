{-# LANGUAGE NoFieldSelectors #-}

{- | OrderRiskAssessment aggregate root, domain events,
repository and publisher PORT type classes.
-}
module Domain.RiskAssessment.Aggregate (
  -- * Re-exports from ValueObjects (for convenient single-import)
  module Domain.RiskAssessment.ValueObjects,

  -- * Status enumeration
  OrderStatus (..),

  -- * Additional value objects
  DecisionRecord (..),

  -- * Aggregate root (construct via 'acceptOrderProposal' only)
  OrderRiskAssessment,

  -- * Smart constructor / factory (Must-20)
  acceptOrderProposal,

  -- * Commands
  evaluateOrderRisk,
  syncKillSwitchState,

  -- * Domain Events (Must-14, Must-15)
  OrderRiskAssessmentEvent (..),

  -- * Integration Event payloads (Must-16, Must-17)
  OrdersApprovedPayload (..),
  OrdersRejectedPayload (..),

  -- * Repository search criteria
  RiskAssessmentSearchCriteria (..),
  emptyRiskAssessmentSearchCriteria,

  -- * Repository PORT (Must-18)
  OrderRiskAssessmentRepository (..),

  -- * Publisher PORT
  RiskEventPublisher (..),
) where

import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.RiskAssessment (Trace)
import Domain.RiskAssessment.Error (DomainError (..))
import Domain.RiskAssessment.ReasonCode (OperatorActionReasonCode, ReasonCode)
import Domain.RiskAssessment.Service.RiskScreeningPolicy (screenOrder)
import Domain.RiskAssessment.ValueObjects
import GHC.Records (HasField (..))

-- ---------------------------------------------------------------------
-- Status
-- ---------------------------------------------------------------------

-- | Order lifecycle status (Must-11, RULE-RG-001).
data OrderStatus
  = Proposed
  | Approved
  | Rejected
  deriving stock (Eq, Ord, Show)

-- ---------------------------------------------------------------------
-- Additional Value Objects
-- ---------------------------------------------------------------------

-- | Must-07: Record of a screening decision (immutable).
data DecisionRecord = DecisionRecord
  { decision :: Decision
  , reasonCode :: Maybe ReasonCode
  , actionReasonCode :: Maybe OperatorActionReasonCode
  , evaluatedAt :: UTCTime
  , trace :: Trace
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Domain Events
-- ---------------------------------------------------------------------

-- | Must-14/15: Domain events emitted by the aggregate.
data OrderRiskAssessmentEvent
  = -- | Must-14: order.risk.evaluated
    OrderRiskEvaluated
      { identifier :: OrderRiskAssessmentIdentifier
      , decision :: Decision
      , reasonCode :: Maybe ReasonCode
      , actionReasonCode :: Maybe OperatorActionReasonCode
      , trace :: Trace
      , evaluatedAt :: UTCTime
      }
  | -- | Must-15: order.risk.rejected (reasonCode is always present; typed Maybe for field-name unification)
    OrderRiskRejected
      { identifier :: OrderRiskAssessmentIdentifier
      , reasonCode :: Maybe ReasonCode
      , trace :: Trace
      }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Integration Event Payloads
-- ---------------------------------------------------------------------

-- | Must-16: orders.approved integration event payload.
data OrdersApprovedPayload = OrdersApprovedPayload
  { identifier :: OrderRiskAssessmentIdentifier
  , trace :: Trace
  , reasonCode :: Maybe ReasonCode
  , actionReasonCode :: Maybe OperatorActionReasonCode
  , evaluatedAt :: UTCTime
  }
  deriving stock (Eq, Show)

-- | Must-17: orders.rejected integration event payload.
data OrdersRejectedPayload = OrdersRejectedPayload
  { identifier :: OrderRiskAssessmentIdentifier
  , reasonCode :: ReasonCode
  , trace :: Trace
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Aggregate Root
--
-- Constructor hidden. Use 'acceptOrderProposal' + command functions.
-- Fields use 'ora' prefix to avoid HasField name collisions.
-- ---------------------------------------------------------------------

-- | Must-01: OrderRiskAssessment aggregate root.
data OrderRiskAssessment = OrderRiskAssessment
  { oraIdentifier :: OrderRiskAssessmentIdentifier
  , oraProposal :: OrderProposal
  , oraOrderStatus :: OrderStatus
  , oraDecision :: Maybe Decision
  , oraReasonCode :: Maybe ReasonCode
  , oraActionReasonCode :: Maybe OperatorActionReasonCode
  , oraTrace :: Trace
  , oraEvaluatedAt :: Maybe UTCTime
  , oraKillSwitchEnabled :: Bool
  , oraSettingsVersion :: Int
  , oraComplianceUpdatedAt :: Maybe UTCTime
  , oraRiskLimits :: RiskLimits
  , oraCompliancePolicy :: CompliancePolicy
  , oraRiskExposure :: RiskExposure
  , oraDecisionRecord :: Maybe DecisionRecord
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Smart Constructor / Factory (Must-20)
-- ---------------------------------------------------------------------

{- | Accept an order proposal and initialise a screening aggregate.

Must-20: Factory entry point; produces a PROPOSED aggregate with no decision.
-}
acceptOrderProposal ::
  OrderRiskAssessmentIdentifier ->
  OrderProposal ->
  Trace ->
  Bool ->
  RiskLimits ->
  CompliancePolicy ->
  RiskExposure ->
  UTCTime ->
  OrderRiskAssessment
acceptOrderProposal assessmentIdentifier proposal traceValue killSwitchEnabled limits policy exposure createdAt =
  OrderRiskAssessment
    { oraIdentifier = assessmentIdentifier
    , oraProposal = proposal
    , oraOrderStatus = Proposed
    , oraDecision = Nothing
    , oraReasonCode = Nothing
    , oraActionReasonCode = Nothing
    , oraTrace = traceValue
    , oraEvaluatedAt = Nothing
    , oraKillSwitchEnabled = killSwitchEnabled
    , oraSettingsVersion = 1
    , oraComplianceUpdatedAt = Just createdAt
    , oraRiskLimits = limits
    , oraCompliancePolicy = policy
    , oraRiskExposure = exposure
    , oraDecisionRecord = Nothing
    }

-- ---------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------

{- | Evaluate the order risk.

Returns 'DomainError' when:

* The aggregate is not in PROPOSED status (Must-11, RULE-RG-001).

Returns the unchanged aggregate and empty event list when:

* A decision has already been recorded (Must-12, INV-RG-002: idempotent).
-}
evaluateOrderRisk ::
  UTCTime ->
  OrderRiskAssessment ->
  Either DomainError (OrderRiskAssessment, [OrderRiskAssessmentEvent])
evaluateOrderRisk evaluationTime assessment
  | assessment.orderStatus /= Proposed =
      Left
        ( InvalidStateTransition
            (orderStatusLabel assessment)
            "evaluateOrderRisk"
        )
  | isJust assessment.decisionRecord =
      Right (assessment, [])
  | otherwise =
      let screeningResult =
            screenOrder
              True
              assessment.killSwitchEnabled
              assessment.riskLimits
              assessment.riskExposure
              assessment.compliancePolicy
              assessment.proposal
              evaluationTime
       in case screeningResult of
            Left rejectionReasonCode ->
              let record =
                    DecisionRecord
                      { decision = Rejected'
                      , reasonCode = Just rejectionReasonCode
                      , actionReasonCode = Nothing
                      , evaluatedAt = evaluationTime
                      , trace = assessment.trace
                      }
                  updated =
                    assessment
                      { oraOrderStatus = Rejected
                      , oraDecision = Just Rejected'
                      , oraReasonCode = Just rejectionReasonCode
                      , oraEvaluatedAt = Just evaluationTime
                      , oraDecisionRecord = Just record
                      }
                  events =
                    [ OrderRiskEvaluated
                        { identifier = assessment.identifier
                        , decision = Rejected'
                        , reasonCode = Just rejectionReasonCode
                        , actionReasonCode = Nothing
                        , trace = assessment.trace
                        , evaluatedAt = evaluationTime
                        }
                    , OrderRiskRejected
                        { identifier = assessment.identifier
                        , reasonCode = Just rejectionReasonCode
                        , trace = assessment.trace
                        }
                    ]
               in Right (updated, events)
            Right Approved' ->
              let record =
                    DecisionRecord
                      { decision = Approved'
                      , reasonCode = Nothing
                      , actionReasonCode = Nothing
                      , evaluatedAt = evaluationTime
                      , trace = assessment.trace
                      }
                  updated =
                    assessment
                      { oraOrderStatus = Approved
                      , oraDecision = Just Approved'
                      , oraEvaluatedAt = Just evaluationTime
                      , oraDecisionRecord = Just record
                      }
                  events =
                    [ OrderRiskEvaluated
                        { identifier = assessment.identifier
                        , decision = Approved'
                        , reasonCode = Nothing
                        , actionReasonCode = Nothing
                        , trace = assessment.trace
                        , evaluatedAt = evaluationTime
                        }
                    ]
               in Right (updated, events)
            Right Rejected' ->
              -- screenOrder returns either Left ReasonCode or Right Approved'.
              -- Right Rejected' is structurally impossible but required for exhaustiveness.
              Left (InvariantViolation "evaluateOrderRisk" "unexpected Rejected' from screenOrder")

-- | Sync the kill-switch state from an external control-plane event.
syncKillSwitchState :: Bool -> OrderRiskAssessment -> OrderRiskAssessment
syncKillSwitchState newState assessment = assessment{oraKillSwitchEnabled = newState}

-- ---------------------------------------------------------------------
-- Repository Search Criteria
-- ---------------------------------------------------------------------

-- | Search criteria for querying risk assessments.
data RiskAssessmentSearchCriteria = RiskAssessmentSearchCriteria
  { statusFilter :: Maybe OrderStatus
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

-- | Default empty search criteria (matches all assessments).
emptyRiskAssessmentSearchCriteria :: RiskAssessmentSearchCriteria
emptyRiskAssessmentSearchCriteria =
  RiskAssessmentSearchCriteria
    { statusFilter = Nothing
    , limitCount = Nothing
    }

-- ---------------------------------------------------------------------
-- Repository PORT (Must-18, Must-19)
-- ---------------------------------------------------------------------

{- | Must-18: Port interface for persisting and querying OrderRiskAssessment aggregates.
No infrastructure dependencies — implementations live in the infra layer.
-}
class (Monad m) => OrderRiskAssessmentRepository m where
  find :: OrderRiskAssessmentIdentifier -> m (Maybe OrderRiskAssessment)
  findByStatus :: OrderStatus -> m [OrderRiskAssessment]
  search :: RiskAssessmentSearchCriteria -> m [OrderRiskAssessment]
  persist :: OrderRiskAssessment -> m ()
  terminate :: OrderRiskAssessmentIdentifier -> m ()

-- ---------------------------------------------------------------------
-- Publisher PORT
-- ---------------------------------------------------------------------

-- | Port interface for publishing integration events.
class (Monad m) => RiskEventPublisher m where
  publishOrdersApproved :: OrdersApprovedPayload -> m ()
  publishOrdersRejected :: OrdersRejectedPayload -> m ()

-- ---------------------------------------------------------------------
-- Internal Helpers
-- ---------------------------------------------------------------------

orderStatusLabel :: OrderRiskAssessment -> Text
orderStatusLabel assessment = case assessment.orderStatus of
  Proposed -> "proposed"
  Approved -> "approved"
  Rejected -> "rejected"

-- ---------------------------------------------------------------------
-- HasField instances (read-only access via OverloadedRecordDot)
-- ---------------------------------------------------------------------

instance HasField "identifier" OrderRiskAssessment OrderRiskAssessmentIdentifier where
  getField OrderRiskAssessment{oraIdentifier = x} = x

instance HasField "proposal" OrderRiskAssessment OrderProposal where
  getField OrderRiskAssessment{oraProposal = x} = x

instance HasField "orderStatus" OrderRiskAssessment OrderStatus where
  getField OrderRiskAssessment{oraOrderStatus = x} = x

instance HasField "decision" OrderRiskAssessment (Maybe Decision) where
  getField OrderRiskAssessment{oraDecision = x} = x

instance HasField "reasonCode" OrderRiskAssessment (Maybe ReasonCode) where
  getField OrderRiskAssessment{oraReasonCode = x} = x

instance HasField "actionReasonCode" OrderRiskAssessment (Maybe OperatorActionReasonCode) where
  getField OrderRiskAssessment{oraActionReasonCode = x} = x

instance HasField "trace" OrderRiskAssessment Trace where
  getField OrderRiskAssessment{oraTrace = x} = x

instance HasField "evaluatedAt" OrderRiskAssessment (Maybe UTCTime) where
  getField OrderRiskAssessment{oraEvaluatedAt = x} = x

instance HasField "killSwitchEnabled" OrderRiskAssessment Bool where
  getField OrderRiskAssessment{oraKillSwitchEnabled = x} = x

instance HasField "settingsVersion" OrderRiskAssessment Int where
  getField OrderRiskAssessment{oraSettingsVersion = x} = x

instance HasField "complianceUpdatedAt" OrderRiskAssessment (Maybe UTCTime) where
  getField OrderRiskAssessment{oraComplianceUpdatedAt = x} = x

instance HasField "riskLimits" OrderRiskAssessment RiskLimits where
  getField OrderRiskAssessment{oraRiskLimits = x} = x

instance HasField "compliancePolicy" OrderRiskAssessment CompliancePolicy where
  getField OrderRiskAssessment{oraCompliancePolicy = x} = x

instance HasField "riskExposure" OrderRiskAssessment RiskExposure where
  getField OrderRiskAssessment{oraRiskExposure = x} = x

instance HasField "decisionRecord" OrderRiskAssessment (Maybe DecisionRecord) where
  getField OrderRiskAssessment{oraDecisionRecord = x} = x
