module Domain.AuditLog.Error (
  DomainError (..),
)
where

import Data.Text (Text)

data DomainError
  = InvalidStateTransition Text Text
  | MissingRequiredFields [Text]
  | AlreadyProcessed
  | InvariantViolation Text Text
  deriving stock (Eq, Show)
