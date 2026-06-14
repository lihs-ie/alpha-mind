{- | ProposalEligibilityPolicy — MUST-14, MUST-15.
純粋関数。SignalSnapshot の整合性とコンプライアンスレビュー要否を検査する。
-}
module Domain.OrderProposal.Service.ProposalEligibilityPolicy (
  checkEligibility,
) where

import Data.Text (Text)
import Data.Text qualified as Text
import Domain.OrderProposal.Error (DomainError (..))
import Domain.OrderProposal.Specification.ComplianceReviewGateSpecification qualified as ComplianceReviewGateSpecification
import Domain.OrderProposal.Specification.SignalIntegritySpecification qualified as SignalIntegritySpecification
import Domain.OrderProposal.ValueObjects (SignalSnapshot (..))

{- | MUST-14: signalVersion / modelVersion / featureVersion / storagePath のいずれかが
空のとき Left (MissingRequiredFields) を返す (RULE-PP-001)。
MUST-15: requiresComplianceReview == True のとき Left ComplianceReviewRequired を返す
(RULE-PP-002)。
純粋関数、外部 IO 非依存。
-}
checkEligibility :: SignalSnapshot -> Either DomainError ()
checkEligibility snapshot
  | not (SignalIntegritySpecification.isSatisfiedBy snapshot) =
      Left (MissingRequiredFields (collectMissingFields snapshot))
  | not (ComplianceReviewGateSpecification.isSatisfiedBy snapshot) =
      Left ComplianceReviewRequired
  | otherwise =
      Right ()

collectMissingFields :: SignalSnapshot -> [Text]
collectMissingFields snapshot =
  [ field
  | (field, fieldValue) <-
      [ ("signalVersion", snapshot.signalVersion)
      , ("modelVersion", snapshot.modelVersion)
      , ("featureVersion", snapshot.featureVersion)
      , ("storagePath", snapshot.storagePath)
      ]
  , Text.null fieldValue
  ]
