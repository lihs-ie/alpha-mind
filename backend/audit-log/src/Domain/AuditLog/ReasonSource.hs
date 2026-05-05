module Domain.AuditLog.ReasonSource
  ( ReasonSource (..)
  ) where

data ReasonSource
  = FromReasonCode
  | FromActionReasonCode
  | FromReason
  | FromNone
  deriving stock (Eq, Ord, Show)
