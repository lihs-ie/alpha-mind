module Domain.Order.Order (
  OrderSide (..),
  OrderStatus (..),
  OrderSummary (..),
  OrderDetail (..),
  orderSideToText,
  orderStatusToText,
)
where

import Data.Text (Text)
import Data.Time (UTCTime)

-- ---------------------------------------------------------------------------
-- Domain types
-- ---------------------------------------------------------------------------

-- | Trade direction.
data OrderSide = Buy | Sell
  deriving stock (Show, Eq)

-- | Order lifecycle status.
data OrderStatus
  = Proposed
  | Approved
  | Rejected
  | Executed
  | Failed
  deriving stock (Show, Eq)

-- | Convert 'OrderSide' to OpenAPI string value.
orderSideToText :: OrderSide -> Text
orderSideToText Buy = "BUY"
orderSideToText Sell = "SELL"

-- | Convert 'OrderStatus' to OpenAPI string value.
orderStatusToText :: OrderStatus -> Text
orderStatusToText Proposed = "PROPOSED"
orderStatusToText Approved = "APPROVED"
orderStatusToText Rejected = "REJECTED"
orderStatusToText Executed = "EXECUTED"
orderStatusToText Failed = "FAILED"

-- | Read model for order list items (@GET \/orders@).
data OrderSummary = OrderSummary
  { identifier :: Text
  , symbol :: Text
  , side :: OrderSide
  , qty :: Double
  , status :: OrderStatus
  , createdAt :: UTCTime
  }

{- | Read model for order detail (@GET \/orders\/{identifier}@).

Extends 'OrderSummary' with optional fields from @orders@ and
@order_executions@ collections.
-}
data OrderDetail = OrderDetail
  { identifier :: Text
  , symbol :: Text
  , side :: OrderSide
  , qty :: Double
  , status :: OrderStatus
  , createdAt :: UTCTime
  , trace :: Text
  , reasonCode :: Maybe Text
  , brokerOrder :: Maybe Text
  , updatedAt :: Maybe UTCTime
  }
