-- | Common types for the RiskAssessment domain.
module Domain.RiskAssessment (
  Trace (..),
) where

import Data.ULID (ULID)

-- | Distributed tracing identifier threaded through domain events.
newtype Trace = Trace {value :: ULID}
  deriving stock (Eq, Ord, Show)
