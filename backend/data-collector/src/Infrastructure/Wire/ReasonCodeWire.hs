{- | Wire-format serialization for 'ReasonCode'.

error-codes.json and AsyncAPI require SCREAMING_SNAKE_CASE values
(e.g. "DATA_SOURCE_UNAVAILABLE").  Using @show@ on the Haskell
constructor produces PascalCase ("DataSourceUnavailable"), which
breaks the downstream contract.  This module provides the single
authoritative mapping.
-}
module Infrastructure.Wire.ReasonCodeWire (
  reasonCodeToWire,
) where

import Data.Text (Text)
import Domain.MarketCollection.ReasonCode (ReasonCode (..))

{- | Serialize a 'ReasonCode' to the SCREAMING_SNAKE_CASE wire value
mandated by error-codes.json and the AsyncAPI schema.
-}
reasonCodeToWire :: ReasonCode -> Text
reasonCodeToWire RequestValidationFailed = "REQUEST_VALIDATION_FAILED"
reasonCodeToWire ComplianceSourceUnapproved = "COMPLIANCE_SOURCE_UNAPPROVED"
reasonCodeToWire DataSourceTimeout = "DATA_SOURCE_TIMEOUT"
reasonCodeToWire DataSourceUnavailable = "DATA_SOURCE_UNAVAILABLE"
reasonCodeToWire DataSchemaInvalid = "DATA_SCHEMA_INVALID"
reasonCodeToWire IdempotencyDuplicateEvent = "IDEMPOTENCY_DUPLICATE_EVENT"
reasonCodeToWire StateConflict = "STATE_CONFLICT"
reasonCodeToWire DependencyTimeout = "DEPENDENCY_TIMEOUT"
