module Domain.OrderExecution (
  -- * Common identifier-like types
  Trace (..),
) where

import Data.ULID (ULID)

-- | Must-22: 追跡識別子。ULID newtype。欠損状態で結果イベントを発行しない (INV-EX-005)。
newtype Trace = Trace {value :: ULID}
  deriving stock (Eq, Ord, Show)
