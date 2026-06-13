module Domain.MarketCollection (
  -- * Common identifier-like types
  Trace (..),
) where

import Data.ULID (ULID)

newtype Trace = Trace {value :: ULID}
  deriving stock (Eq, Ord, Show)
