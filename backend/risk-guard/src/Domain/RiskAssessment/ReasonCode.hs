{- | Reason code enumerations for the RiskAssessment domain.

Wire values match AsyncAPI schema and error-codes.json.
-}
module Domain.RiskAssessment.ReasonCode (
  ReasonCode (..),
  OperatorActionReasonCode (..),
) where

{- | Reason codes for automated risk screening decisions.

Wire mappings:

* 'KillSwitchEnabled'           → @KILL_SWITCH_ENABLED@
* 'RiskLimitExceeded'           → @RISK_LIMIT_EXCEEDED@
* 'ComplianceRestrictedSymbol'  → @COMPLIANCE_RESTRICTED_SYMBOL@
* 'ComplianceBlackoutActive'    → @COMPLIANCE_BLACKOUT_ACTIVE@
* 'RiskEvaluationUnavailable'   → @RISK_EVALUATION_UNAVAILABLE@
* 'IdempotencyDuplicateEvent'   → @IDEMPOTENCY_DUPLICATE_EVENT@
-}
data ReasonCode
  = KillSwitchEnabled
  | RiskLimitExceeded
  | ComplianceRestrictedSymbol
  | ComplianceBlackoutActive
  | RiskEvaluationUnavailable
  | IdempotencyDuplicateEvent
  deriving stock (Eq, Ord, Show)

-- | Reason codes for operator-initiated actions.
data OperatorActionReasonCode
  = ManualApproval
  | ManualRejection
  | ComplianceOverride
  deriving stock (Eq, Ord, Show)
