{- | Must-19: Port interface for idempotency key management.

Defined in its own module so that 'find', 'persist', 'terminate' method names
do not collide with 'OrderRiskAssessmentRepository' methods in 'Aggregate'.
Semantics: find (serviceId -> eventId -> alreadyProcessed?)
-}
module Domain.RiskAssessment.Port.IdempotencyKeyRepository (
  IdempotencyKeyRepository (..),
) where

import Data.Text (Text)

-- | Must-19: Repository port for idempotency key management.
class (Monad m) => IdempotencyKeyRepository m where
  find :: Text -> Text -> m Bool
  persist :: Text -> Text -> m ()
  terminate :: Text -> Text -> m ()
