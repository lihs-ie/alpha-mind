module Domain.AuditLog.Status
  ( Status (..)
  ) where

data Status
  = Pending
  | Recorded
  | Failed
  deriving stock (Eq, Ord, Show)
