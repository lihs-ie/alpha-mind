{- | Must-17: SourcePolicySpecificationService — 純粋関数、外部IO非依存。
ApprovedSourceSpecification の isSatisfiedBy を用いて未承認ソース判定を行い、
違反時に ComplianceSourceUnapproved を返す。
-}
module Domain.MarketCollection.SourcePolicySpecificationService (
  -- * Specification
  ApprovedSourceSpecification (..),
  DataSourceName (..),

  -- * Service
  validateSourcePolicy,
) where

import Data.Text (Text)
import Domain.MarketCollection.ReasonCode (ReasonCode (..))

-- ---------------------------------------------------------------------
-- Specification
-- ---------------------------------------------------------------------

-- | データソース名（J-Quants / Alpaca / Nisshokin 等を表す値）。
newtype DataSourceName = DataSourceName {value :: Text}
  deriving stock (Eq, Ord, Show)

{- | ApprovedSourceSpecification: 承認済みデータソースのリストを保持し、
isSatisfiedBy で未承認判定を行う。
-}
newtype ApprovedSourceSpecification = ApprovedSourceSpecification
  { approvedSources :: [DataSourceName]
  }
  deriving stock (Eq, Show)

-- | Specification パターンの isSatisfiedBy。承認済みなら True を返す。
isSatisfiedBy :: ApprovedSourceSpecification -> DataSourceName -> Bool
isSatisfiedBy specification source =
  source `elem` specification.approvedSources

-- ---------------------------------------------------------------------
-- Domain Service (Must-17, RULE-DC-002)
-- ---------------------------------------------------------------------

{- | 収集要求ソースが承認済みかを検証する純粋関数。
未承認ソースが含まれる場合は Left ComplianceSourceUnapproved を返す。
外部IOを含まない。
-}
validateSourcePolicy ::
  ApprovedSourceSpecification ->
  [DataSourceName] ->
  Either ReasonCode ()
validateSourcePolicy specification sources =
  case filter (not . isSatisfiedBy specification) sources of
    [] -> Right ()
    _ -> Left ComplianceSourceUnapproved
