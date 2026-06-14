module Domain.OrderProposal.Error (
  DomainError (..),
) where

import Data.Text (Text)

-- | ドメインエラー型。呼び出し側が網羅的パターンマッチできる形で集約する。
data DomainError
  = InvalidStateTransition Text Text
  | InvariantViolation Text Text
  | MissingRequiredFields [Text]
  | ComplianceReviewRequired
  | IdempotentDuplicate
  deriving stock (Eq, Show)
