module Domain.AuditLog.Result (
  Result (..),
) where

data Result
  = Success
  | Failed
  deriving stock (Eq, Ord, Show)
