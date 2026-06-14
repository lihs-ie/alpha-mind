module Domain.HypothesisOrchestration.DuplicateSuppressionPolicy (
  -- * Policy
  DuplicateSuppressionPolicy (..),
  shouldSuppress,
) where

import Domain.HypothesisOrchestration.ValueObjects (
  DuplicateAssessment,
  DuplicateAssessmentDecision (..),
  duplicateAssessmentDecision,
 )

-- ---------------------------------------------------------------------
-- Policy (Must-27)
-- ---------------------------------------------------------------------

{- | Must-27: DuplicateSuppressionPolicy — 純粋関数、IO非依存。
DuplicateAssessment を受け取って抑止判定を行う。
-}
newtype DuplicateSuppressionPolicy = DuplicateSuppressionPolicy
  { suppressOnBlock :: Bool
  }
  deriving stock (Eq, Show)

{- | Must-27: 重複アセスメント結果に基づいて提案を抑止するかを判定する純粋関数。
decision=Block かつ suppressOnBlock=True の場合に抑止（True を返す）。
-}
shouldSuppress :: DuplicateSuppressionPolicy -> DuplicateAssessment -> Bool
shouldSuppress policy assessment =
  let decision = duplicateAssessmentDecision assessment
   in policy.suppressOnBlock && decision == Block
