{- | Must-19: EvidenceCompletenessPolicy — 純粋関数、外部IO非依存。
EvidenceCompletenessSpecification の isSatisfiedBy を用いて根拠情報の完全性を検証し、
欠損時に RequestValidationFailed を返す。
-}
module Domain.InsightCollection.EvidenceCompletenessPolicy (
  -- * Specification
  EvidenceCompletenessSpecification (..),

  -- * Service
  validateEvidence,
) where

import Data.Text (Text)
import Domain.InsightCollection.Aggregate (InsightRecord (..))
import Domain.InsightCollection.ReasonCode (ReasonCode (..))

-- ---------------------------------------------------------------------
-- Specification
-- ---------------------------------------------------------------------

-- | EvidenceCompletenessSpecification: sourceUrl および evidenceSnippet の非空を要求する。
data EvidenceCompletenessSpecification = EvidenceCompletenessSpecification
  deriving stock (Eq, Show)

{- | Specification パターンの isSatisfiedBy。
sourceUrl または evidenceSnippet が空の場合は False を返す。
-}
isSatisfiedBy :: EvidenceCompletenessSpecification -> InsightRecord -> Bool
isSatisfiedBy _ InsightRecord{sourceUrl = url, evidenceSnippet = snippet} =
  url /= ("" :: Text) && snippet /= ("" :: Text)

-- ---------------------------------------------------------------------
-- Domain Service (Must-19, Must-22, RULE-IC-003)
-- ---------------------------------------------------------------------

{- | Must-19: 根拠情報の完全性を検証する純粋関数。
Must-22: sourceUrl または evidenceSnippet が欠損している InsightRecord は RequestValidationFailed。
外部IOを含まない。
-}
validateEvidence ::
  [InsightRecord] ->
  Either ReasonCode [InsightRecord]
validateEvidence records =
  let invalid = filter (not . isSatisfiedBy EvidenceCompletenessSpecification) records
   in case invalid of
        [] -> Right records
        _ -> Left RequestValidationFailed
