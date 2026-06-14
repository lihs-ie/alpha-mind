{- | Wire-format serialization for 'ReasonCode' and 'OperatorActionReasonCode'.

AsyncAPI schema mandates SCREAMING_SNAKE_CASE values.
Using @show@ on the Haskell constructor produces PascalCase, which
breaks the downstream contract.  This module provides the single
authoritative mapping.

Wire mappings (AsyncAPI ReasonCode schema):
* 'KillSwitchEnabled'           → @"KILL_SWITCH_ENABLED"@
* 'RiskLimitExceeded'           → @"RISK_LIMIT_EXCEEDED"@
* 'ComplianceRestrictedSymbol'  → @"COMPLIANCE_RESTRICTED_SYMBOL"@
* 'ComplianceBlackoutActive'    → @"COMPLIANCE_BLACKOUT_ACTIVE"@
* 'RiskEvaluationUnavailable'   → @"RISK_EVALUATION_UNAVAILABLE"@
* 'IdempotencyDuplicateEvent'   → @"IDEMPOTENCY_DUPLICATE_EVENT"@

OperatorActionReasonCode wire mappings:
* 'ManualApproval'   → @"MANUAL_APPROVAL"@
* 'ManualRejection'  → @"MANUAL_REJECTION"@
* 'ComplianceOverride' → @"COMPLIANCE_OVERRIDE"@
-}
module Infrastructure.Wire.ReasonCodeWire (
  reasonCodeToWire,
  reasonCodeFromWire,
  operatorActionReasonCodeToWire,
  operatorActionReasonCodeFromWire,
) where

import Data.Text (Text)
import Domain.RiskAssessment.ReasonCode (OperatorActionReasonCode (..), ReasonCode (..))

-- | Serialize a 'ReasonCode' to the SCREAMING_SNAKE_CASE wire value.
reasonCodeToWire :: ReasonCode -> Text
reasonCodeToWire KillSwitchEnabled = "KILL_SWITCH_ENABLED"
reasonCodeToWire RiskLimitExceeded = "RISK_LIMIT_EXCEEDED"
reasonCodeToWire ComplianceRestrictedSymbol = "COMPLIANCE_RESTRICTED_SYMBOL"
reasonCodeToWire ComplianceBlackoutActive = "COMPLIANCE_BLACKOUT_ACTIVE"
reasonCodeToWire RiskEvaluationUnavailable = "RISK_EVALUATION_UNAVAILABLE"
reasonCodeToWire IdempotencyDuplicateEvent = "IDEMPOTENCY_DUPLICATE_EVENT"

-- | Deserialize a wire string back to 'ReasonCode'.
reasonCodeFromWire :: Text -> Either Text ReasonCode
reasonCodeFromWire "KILL_SWITCH_ENABLED" = Right KillSwitchEnabled
reasonCodeFromWire "RISK_LIMIT_EXCEEDED" = Right RiskLimitExceeded
reasonCodeFromWire "COMPLIANCE_RESTRICTED_SYMBOL" = Right ComplianceRestrictedSymbol
reasonCodeFromWire "COMPLIANCE_BLACKOUT_ACTIVE" = Right ComplianceBlackoutActive
reasonCodeFromWire "RISK_EVALUATION_UNAVAILABLE" = Right RiskEvaluationUnavailable
reasonCodeFromWire "IDEMPOTENCY_DUPLICATE_EVENT" = Right IdempotencyDuplicateEvent
reasonCodeFromWire other = Left ("unknown reasonCode: " <> other)

-- | Serialize an 'OperatorActionReasonCode' to wire format.
operatorActionReasonCodeToWire :: OperatorActionReasonCode -> Text
operatorActionReasonCodeToWire ManualApproval = "MANUAL_APPROVAL"
operatorActionReasonCodeToWire ManualRejection = "MANUAL_REJECTION"
operatorActionReasonCodeToWire ComplianceOverride = "COMPLIANCE_OVERRIDE"

-- | Deserialize a wire string back to 'OperatorActionReasonCode'.
operatorActionReasonCodeFromWire :: Text -> Either Text OperatorActionReasonCode
operatorActionReasonCodeFromWire "MANUAL_APPROVAL" = Right ManualApproval
operatorActionReasonCodeFromWire "MANUAL_REJECTION" = Right ManualRejection
operatorActionReasonCodeFromWire "COMPLIANCE_OVERRIDE" = Right ComplianceOverride
operatorActionReasonCodeFromWire other = Left ("unknown actionReasonCode: " <> other)
