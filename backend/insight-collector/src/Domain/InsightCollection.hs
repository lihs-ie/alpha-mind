module Domain.InsightCollection (
  -- * Common types
  Trace (..),
) where

import Data.ULID (ULID)

-- | Distributed trace identifier (ULID).
newtype Trace = Trace {value :: ULID}
  deriving stock (Eq, Ord, Show)
