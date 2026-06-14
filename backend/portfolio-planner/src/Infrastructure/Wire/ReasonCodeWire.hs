{- | Wire-format serialization for 'ReasonCode'.

error-codes.json and AsyncAPI require SCREAMING_SNAKE_CASE values.
Using @show@ on the Haskell constructor produces PascalCase, which breaks
the downstream contract.  This module provides the single authoritative mapping.

Must-01: All 5 ReasonCode variants serialized to SCREAMING_SNAKE_CASE.
-}
module Infrastructure.Wire.ReasonCodeWire (
  reasonCodeToWire,
  reasonCodeFromWire,
) where

import Data.Text (Text)
import Domain.OrderProposal.ReasonCode (ReasonCode (..))

{- | Serialize a 'ReasonCode' to the SCREAMING_SNAKE_CASE wire value
mandated by error-codes.json and the AsyncAPI schema.
-}
reasonCodeToWire :: ReasonCode -> Text
reasonCodeToWire RequestValidationFailed = "REQUEST_VALIDATION_FAILED"
reasonCodeToWire ComplianceReviewRequired = "COMPLIANCE_REVIEW_REQUIRED"
reasonCodeToWire IdempotencyDuplicateEvent = "IDEMPOTENCY_DUPLICATE_EVENT"
reasonCodeToWire DependencyTimeout = "DEPENDENCY_TIMEOUT"
reasonCodeToWire DependencyUnavailable = "DEPENDENCY_UNAVAILABLE"

{- | Deserialize a SCREAMING_SNAKE_CASE wire value back to a 'ReasonCode'.
Returns 'Left' with an error message for unknown values.
-}
reasonCodeFromWire :: Text -> Either Text ReasonCode
reasonCodeFromWire "REQUEST_VALIDATION_FAILED" = Right RequestValidationFailed
reasonCodeFromWire "COMPLIANCE_REVIEW_REQUIRED" = Right ComplianceReviewRequired
reasonCodeFromWire "IDEMPOTENCY_DUPLICATE_EVENT" = Right IdempotencyDuplicateEvent
reasonCodeFromWire "DEPENDENCY_TIMEOUT" = Right DependencyTimeout
reasonCodeFromWire "DEPENDENCY_UNAVAILABLE" = Right DependencyUnavailable
reasonCodeFromWire other = Left ("unknown reasonCode: " <> other)
