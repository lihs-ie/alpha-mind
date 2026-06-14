module Domain.OrderProposal (
  -- * Common types
  Trace (..),
) where

import Data.ULID (ULID)

-- | Trace — ULID で表す分散トレーシング識別子。INV-PP-006 参照。
newtype Trace = Trace {value :: ULID}
  deriving stock (Eq, Ord, Show)
