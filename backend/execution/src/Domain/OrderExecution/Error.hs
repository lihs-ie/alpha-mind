module Domain.OrderExecution.Error (
  ExecutionError (..),
) where

import Data.Text (Text)

data ExecutionError
  = InvalidStateTransition Text Text
  | MissingRequiredFields [Text]
  | InvariantViolation Text Text
  | AlreadyProcessed
  | DuplicateDispatch Text
  deriving stock (Eq, Show)
