-- | Domain error types for the RiskAssessment domain.
module Domain.RiskAssessment.Error (
  DomainError (..),
) where

import Data.Text (Text)

-- | Errors that can occur during domain command processing.
data DomainError
  = -- | State machine transition not allowed from the current status.
    InvalidStateTransition Text Text
  | -- | One or more required fields are absent.
    MissingRequiredFields Text
  | -- | An invariant was violated with context.
    InvariantViolation Text Text
  | -- | The event has already been processed (idempotency guard).
    AlreadyProcessed Text
  deriving stock (Eq, Show)
