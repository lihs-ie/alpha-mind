module Domain.HypothesisOrchestration (
  -- * Common identifier-like types
  Trace (..),
) where

import Data.ULID (ULID)

-- | 境界横断トレース識別子（ULID）。
newtype Trace = Trace {value :: ULID}
  deriving stock (Eq, Ord, Show)
