module Domain.InsightCollection.ReasonCode (
  ReasonCode (..),
  isRetryable,
) where

{- | Must-27: 7値の ReasonCode 列挙型。
Must-28: retryable フラグを isRetryable 関数で表現。
-}
data ReasonCode
  = -- | retryable: false
    RequestValidationFailed
  | -- | retryable: false
    ComplianceSourceUnapproved
  | -- | retryable: true
    DependencyTimeout
  | -- | retryable: true
    DependencyUnavailable
  | -- | retryable: false
    DataSchemaInvalid
  | -- | retryable: false
    StateConflict
  | -- | retryable: false
    IdempotencyDuplicateEvent
  deriving stock (Eq, Ord, Show)

-- | Must-28: retryable フラグ。
isRetryable :: ReasonCode -> Bool
isRetryable DependencyTimeout = True
isRetryable DependencyUnavailable = True
isRetryable _ = False
