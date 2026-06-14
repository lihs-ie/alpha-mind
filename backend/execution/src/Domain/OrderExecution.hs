module Domain.OrderExecution (
  -- * Common trace type
  Trace (..),
) where

import Data.ULID (ULID)

newtype Trace = Trace {value :: ULID}
  deriving stock (Eq, Ord, Show)
