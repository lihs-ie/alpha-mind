module Domain.MarketCollection.Error (
  DomainError (..),
)
where

import Data.Text (Text)

data DomainError
  = InvalidStateTransition Text Text
  | MissingRequiredFields [Text]
  | InvariantViolation Text Text
  | AlreadyProcessed
  deriving stock (Eq, Show)
