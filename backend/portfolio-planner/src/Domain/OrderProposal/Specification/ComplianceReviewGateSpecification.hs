{- | ComplianceReviewGateSpecification — MUST-18.
純粋関数。requiresComplianceReview == True のとき False を返す。
-}
module Domain.OrderProposal.Specification.ComplianceReviewGateSpecification (
  isSatisfiedBy,
) where

import Domain.OrderProposal.ValueObjects (SignalSnapshot (..))

{- | MUST-18: requiresComplianceReview == True のとき False を返す。
コンプライアンスレビューが不要（False）のときのみ True を返す。
純粋関数、外部 IO 非依存。
-}
isSatisfiedBy :: SignalSnapshot -> Bool
isSatisfiedBy snapshot = not snapshot.requiresComplianceReview
