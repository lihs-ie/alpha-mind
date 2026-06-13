module Domain.MarketCollection.ReasonCode (
  ReasonCode (..),
) where

{- | Must-10: 8値の ReasonCode 列挙型。
error-codes.json および ドメインモデル設計 §5.1 §8.7 に準拠。
-}
data ReasonCode
  = RequestValidationFailed
  | ComplianceSourceUnapproved
  | DataSourceTimeout
  | DataSourceUnavailable
  | DataSchemaInvalid
  | IdempotencyDuplicateEvent
  | StateConflict
  | DependencyTimeout
  deriving stock (Eq, Ord, Show)
