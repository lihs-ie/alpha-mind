{- | Must-18: SourcePolicyComplianceService — 純粋関数、外部IO非依存。
SourcePolicyApprovedSpecification の isSatisfiedBy を用いて未承認ソース判定を行い、
違反時に ComplianceSourceUnapproved を返す。
-}
module Domain.InsightCollection.SourcePolicyComplianceService (
  -- * Specification
  SourcePolicyApprovedSpecification (..),

  -- * Service
  validateSourcePolicy,
) where

import Domain.InsightCollection.Aggregate (
  SourcePolicySnapshot (..),
  SourceType,
 )
import Domain.InsightCollection.ReasonCode (ReasonCode (..))

-- ---------------------------------------------------------------------
-- Specification
-- ---------------------------------------------------------------------

{- | SourcePolicyApprovedSpecification: enabled=True AND redistributionAllowed=True が必要。
isSatisfiedBy でソースが使用許可されているかを判定する。
-}
newtype SourcePolicyApprovedSpecification = SourcePolicyApprovedSpecification
  { approvedSourceTypes :: [SourceType]
  }
  deriving stock (Eq, Show)

-- | Specification パターンの isSatisfiedBy。enabled=True AND redistributionAllowed=True が必要。
isSatisfiedBy :: SourcePolicyApprovedSpecification -> SourcePolicySnapshot -> Bool
isSatisfiedBy specification SourcePolicySnapshot{enabled = e, redistributionAllowed = r, sourceType = st} =
  e
    && r
    && st `elem` specification.approvedSourceTypes

-- ---------------------------------------------------------------------
-- Domain Service (Must-18, Must-21, RULE-IC-002)
-- ---------------------------------------------------------------------

{- | Must-18: 許可ソース/規約充足判定を行う純粋関数。
Must-21: enabled=false または redistributionAllowed=false のソースは ComplianceSourceUnapproved。
外部IOを含まない。
-}
validateSourcePolicy ::
  [SourcePolicySnapshot] ->
  [SourceType] ->
  Either ReasonCode [SourcePolicySnapshot]
validateSourcePolicy policies requestedSourceTypes =
  let approvedSpec = SourcePolicyApprovedSpecification{approvedSourceTypes = requestedSourceTypes}
      relevant = filter (\SourcePolicySnapshot{sourceType = st} -> st `elem` requestedSourceTypes) policies
      unapproved = filter (not . isSatisfiedBy approvedSpec) relevant
   in case unapproved of
        [] -> Right relevant
        _ -> Left ComplianceSourceUnapproved
