module Domain.OrderProposal.ReasonCode (
  ReasonCode (..),
) where

-- | ReasonCode — ドメインモデル設計 §ReasonCode に準拠。
data ReasonCode
  = RequestValidationFailed
  | ComplianceReviewRequired
  | IdempotencyDuplicateEvent
  | DependencyTimeout
  | DependencyUnavailable
  deriving stock (Eq, Ord, Show)
