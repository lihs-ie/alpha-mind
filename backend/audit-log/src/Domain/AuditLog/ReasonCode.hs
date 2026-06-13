module Domain.AuditLog.ReasonCode (
  ReasonCode (..),
) where

data ReasonCode
  = DataSchemaInvalid
  | AuditWriteFailed
  | IdempotencyDuplicateEvent
  deriving stock (Eq, Ord, Show)
