{- | Must-18: CollectionQualityPolicy — 純粋関数、外部IO非依存。
スキーマ整合／欠損検証を行い、不正時に DataSchemaInvalid を返す。
-}
module Domain.MarketCollection.CollectionQualityPolicy (
  -- * Specification
  MarketSchemaIntegritySpecification (..),
  RawMarketRecord (..),
  RawMarketField (..),

  -- * Service
  validateCollectionQuality,
) where

import Data.Text (Text)
import Domain.MarketCollection.ReasonCode (ReasonCode (..))

-- ---------------------------------------------------------------------
-- Raw Market Record 型（ドメイン中間型）
-- ACL 層がパース結果をこの型に変換してドメイン層に渡す。
-- RULE-DC-008: スキーマ不正時に DataSchemaInvalid を返す責務はドメイン層。
-- ---------------------------------------------------------------------

-- | 市場データの個別フィールドを表す値。
data RawMarketField
  = FieldText Text
  | FieldDouble Double
  | FieldInt Int
  deriving stock (Eq, Show)

-- | 市場データの1レコード（フィールド名→値の写像リスト）。
newtype RawMarketRecord = RawMarketRecord
  { fields :: [(Text, RawMarketField)]
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Specification
-- ---------------------------------------------------------------------

-- | MarketSchemaIntegritySpecification: スキーマ検証の必須フィールドリストを保持する。
newtype MarketSchemaIntegritySpecification = MarketSchemaIntegritySpecification
  { requiredFields :: [Text]
  }
  deriving stock (Eq, Show)

-- | Specification パターンの isSatisfiedBy — 必須フィールドが全て存在するか検証。
isSatisfiedBy :: MarketSchemaIntegritySpecification -> RawMarketRecord -> Bool
isSatisfiedBy specification record =
  all (`elem` recordFieldNames record) specification.requiredFields

recordFieldNames :: RawMarketRecord -> [Text]
recordFieldNames record = map fst record.fields

-- ---------------------------------------------------------------------
-- Domain Service (Must-18, RULE-DC-008)
-- ---------------------------------------------------------------------

{- | スキーマ整合・欠損検証を行う純粋関数。
不正なレコードが1件でも存在する場合は Left DataSchemaInvalid を返す。
外部IOを含まない。
-}
validateCollectionQuality ::
  MarketSchemaIntegritySpecification ->
  [RawMarketRecord] ->
  Either ReasonCode ()
validateCollectionQuality specification records =
  let invalidRecords = filter (not . isSatisfiedBy specification) records
   in case invalidRecords of
        [] -> Right ()
        _ -> Left DataSchemaInvalid
