module Domain.MarketCollection.CollectionQualityPolicySpec (spec) where

import Data.Either (isLeft, isRight)
import Domain.MarketCollection.CollectionQualityPolicy (
  MarketSchemaIntegritySpecification (..),
  RawMarketField (..),
  RawMarketRecord (..),
  validateCollectionQuality,
 )
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

validRecord :: RawMarketRecord
validRecord =
  RawMarketRecord
    { fields =
        [ ("date", FieldText "2026-01-15")
        , ("open", FieldDouble 1000.0)
        , ("high", FieldDouble 1050.0)
        , ("low", FieldDouble 990.0)
        , ("close", FieldDouble 1020.0)
        , ("volume", FieldInt 500000)
        ]
    }

invalidRecord :: RawMarketRecord
invalidRecord =
  RawMarketRecord
    { fields =
        [ ("date", FieldText "2026-01-15")
        -- missing required fields: open, high, low, close, volume
        ]
    }

ohlcvSpec :: MarketSchemaIntegritySpecification
ohlcvSpec =
  MarketSchemaIntegritySpecification
    { requiredFields = ["date", "open", "high", "low", "close", "volume"]
    }

spec :: Spec
spec =
  describe "Domain.MarketCollection.CollectionQualityPolicy" $ do
    -- Must-18, TST-DC-008: RULE-DC-008 — スキーマ不正テスト
    describe "validateCollectionQuality" $ do
      it "returns Right () when all records match the schema" $ do
        validateCollectionQuality ohlcvSpec [validRecord]
          `shouldSatisfy` isRight

      it "returns Left DataSchemaInvalid when a record is missing required fields" $ do
        -- TST-DC-008 受入条件: スキーマ不正時に DATA_SCHEMA_INVALID
        validateCollectionQuality ohlcvSpec [invalidRecord]
          `shouldBe` Left DataSchemaInvalid

      it "returns Left when any record in a batch is invalid" $ do
        validateCollectionQuality ohlcvSpec [validRecord, invalidRecord]
          `shouldSatisfy` isLeft

      it "returns Right () for empty record list" $ do
        validateCollectionQuality ohlcvSpec []
          `shouldSatisfy` isRight

      it "is pure — no IO involved" $ do
        -- 型検査がそのまま証明。validateCollectionQuality は Either ReasonCode () を返す純粋関数。
        let result = validateCollectionQuality ohlcvSpec [validRecord]
        result `shouldBe` Right ()
