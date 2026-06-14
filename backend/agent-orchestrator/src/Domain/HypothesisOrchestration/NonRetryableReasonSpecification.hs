module Domain.HypothesisOrchestration.NonRetryableReasonSpecification (
  -- * Specification (Must-30)
  NonRetryableReasonSpecification (..),
  isSatisfiedBy,
) where

import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))

-- ---------------------------------------------------------------------
-- Specification (Must-30)
-- ---------------------------------------------------------------------

{- | Must-30: NonRetryableReasonSpecification — ReasonCode が非再試行かを yes/no で返す。
RULE-AO-008: RESOURCE_NOT_FOUND と REQUEST_VALIDATION_FAILED は非再試行。
他は再試行可能（DEPENDENCY_TIMEOUT, DEPENDENCY_UNAVAILABLE 等）。
-}
data NonRetryableReasonSpecification = NonRetryableReasonSpecification
  deriving stock (Eq, Show)

-- | Must-30: 非再試行の ReasonCode なら True を返す（RULE-AO-008）。
isSatisfiedBy :: NonRetryableReasonSpecification -> ReasonCode -> Bool
isSatisfiedBy _ reasonCode = case reasonCode of
  ResourceNotFound -> True
  RequestValidationFailed -> True
  StateConflict -> False
  IdempotencyDuplicateEvent -> False
  DependencyTimeout -> False
  DependencyUnavailable -> False
