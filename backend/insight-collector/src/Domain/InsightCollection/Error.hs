module Domain.InsightCollection.Error (
  DomainError (..),
) where

import Data.Text (Text)

-- | Domain-layer error type for insight-collector.
data DomainError
  = InvalidStateTransition Text Text
  | MissingRequiredFields [Text]
  | InvariantViolation Text Text
  | AlreadyProcessed
  deriving stock (Eq, Show)
