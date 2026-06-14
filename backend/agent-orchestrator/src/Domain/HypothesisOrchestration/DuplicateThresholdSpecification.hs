module Domain.HypothesisOrchestration.DuplicateThresholdSpecification (
  -- * Specification (Must-29)
  DuplicateThresholdSpecification (..),
  isSatisfiedBy,
) where

import Domain.HypothesisOrchestration.ValueObjects (
  DuplicateAssessment,
  duplicateAssessmentMaxSimilarityScore,
 )

-- ---------------------------------------------------------------------
-- Specification (Must-29)
-- ---------------------------------------------------------------------

{- | Must-29: DuplicateThresholdSpecification — 類似度が閾値以上かを yes/no で返す。
isSatisfiedBy が True を返すとき、類似度が閾値以上であり重複として扱う。
-}
newtype DuplicateThresholdSpecification = DuplicateThresholdSpecification
  { threshold :: Double
  }
  deriving stock (Eq, Show)

-- | Must-29: maxSimilarityScore が threshold 以上なら True を返す。
isSatisfiedBy :: DuplicateThresholdSpecification -> DuplicateAssessment -> Bool
isSatisfiedBy specification assessment =
  let score = duplicateAssessmentMaxSimilarityScore assessment
   in score >= specification.threshold
