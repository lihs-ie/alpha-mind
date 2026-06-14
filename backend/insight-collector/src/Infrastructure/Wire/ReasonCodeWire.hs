-- | Wire encoding for ReasonCode — Firestore / Pub/Sub text representation.
module Infrastructure.Wire.ReasonCodeWire (
  reasonCodeToWire,
  reasonCodeFromWire,
) where

import Data.Text (Text)
import Domain.InsightCollection.ReasonCode (ReasonCode (..))

-- | Convert ReasonCode to its Firestore/Pub/Sub string representation.
reasonCodeToWire :: ReasonCode -> Text
reasonCodeToWire RequestValidationFailed = "REQUEST_VALIDATION_FAILED"
reasonCodeToWire ComplianceSourceUnapproved = "COMPLIANCE_SOURCE_UNAPPROVED"
reasonCodeToWire DependencyTimeout = "DEPENDENCY_TIMEOUT"
reasonCodeToWire DependencyUnavailable = "DEPENDENCY_UNAVAILABLE"
reasonCodeToWire DataSchemaInvalid = "DATA_SCHEMA_INVALID"
reasonCodeToWire StateConflict = "STATE_CONFLICT"
reasonCodeToWire IdempotencyDuplicateEvent = "IDEMPOTENCY_DUPLICATE_EVENT"

-- | Parse ReasonCode from Firestore/Pub/Sub string representation.
reasonCodeFromWire :: Text -> Either Text ReasonCode
reasonCodeFromWire "REQUEST_VALIDATION_FAILED" = Right RequestValidationFailed
reasonCodeFromWire "COMPLIANCE_SOURCE_UNAPPROVED" = Right ComplianceSourceUnapproved
reasonCodeFromWire "DEPENDENCY_TIMEOUT" = Right DependencyTimeout
reasonCodeFromWire "DEPENDENCY_UNAVAILABLE" = Right DependencyUnavailable
reasonCodeFromWire "DATA_SCHEMA_INVALID" = Right DataSchemaInvalid
reasonCodeFromWire "STATE_CONFLICT" = Right StateConflict
reasonCodeFromWire "IDEMPOTENCY_DUPLICATE_EVENT" = Right IdempotencyDuplicateEvent
reasonCodeFromWire other = Left ("unknown ReasonCode: " <> other)
