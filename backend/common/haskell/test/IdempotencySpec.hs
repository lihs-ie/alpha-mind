{-# LANGUAGE OverloadedStrings #-}

module IdempotencySpec (spec) where

import Data.HashMap.Strict qualified as HashMap
import Data.Text qualified as Text
import Gogol.FireStore (Value (..), Value_NullValue (..))
import Persistence.Firestore (FromFirestore (..), ToFirestore (..))
import Persistence.Idempotency (IdempotencyError (..), IdempotencyRecord (..), ReserveResult (..), reserveResultForExistingRecord)
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)
import TestFixtures (sampleIdentifier, sampleTime, sampleTrace)

spec :: Spec
spec =
  describe "Persistence.Idempotency" $ do
    it "encodes records to Firestore fields" $ do
      let fields = toFirestoreFields sampleRecord
      fmap getStringValue (HashMap.lookup "key" fields)
        `shouldBe` Just (Just "portfolio:01ARZ3NDEKTSV4RRFFQ69G5FAV")
      fmap getStringValue (HashMap.lookup "service" fields) `shouldBe` Just (Just "portfolio")
      fmap getNullValue (HashMap.lookup "processedAt" fields) `shouldBe` Just (Just Value_NullValue_NULLVALUE)

    it "decodes records from Firestore fields" $
      case fromFirestoreFields (toFirestoreFields sampleRecord) of
        Left err -> err `shouldBe` "unexpected failure"
        Right actual -> do
          key actual `shouldBe` key sampleRecord
          identifier actual `shouldBe` identifier sampleRecord
          trace actual `shouldBe` trace sampleRecord
          service actual `shouldBe` service sampleRecord
          processedAt actual `shouldBe` processedAt sampleRecord
          expiresAt actual `shouldBe` expiresAt sampleRecord
          updatedAt actual `shouldBe` updatedAt sampleRecord

    it "rejects records with missing fields" $
      shouldDecodeRecordLeft
        (fromFirestoreFields @IdempotencyRecord (HashMap.delete "key" (toFirestoreFields sampleRecord)))
        "missing field: key"

    it "exposes reserve results and errors with equality" $ do
      Reserved `seq` AlreadyReserved `seq` AlreadyProcessed `seq` True `shouldBe` True
      IdempotencyErrorNotReserved "key" `shouldBe` IdempotencyErrorNotReserved "key"

    it "distinguishes reserved records from completed duplicates" $ do
      reserveResultForExistingRecord sampleRecord{processedAt = Nothing}
        `shouldBe` AlreadyReserved
      reserveResultForExistingRecord sampleRecord{processedAt = Just sampleTime}
        `shouldBe` AlreadyProcessed

sampleRecord :: IdempotencyRecord
sampleRecord =
  IdempotencyRecord
    { key = "portfolio:01ARZ3NDEKTSV4RRFFQ69G5FAV"
    , identifier = sampleIdentifier
    , trace = sampleTrace
    , service = "portfolio"
    , processedAt = Nothing
    , expiresAt = sampleTime
    , updatedAt = sampleTime
    }

getStringValue :: Value -> Maybe Text.Text
getStringValue Value{stringValue = value} = value

getNullValue :: Value -> Maybe Value_NullValue
getNullValue Value{nullValue = value} = value

shouldDecodeRecordLeft :: Either Text.Text IdempotencyRecord -> Text.Text -> IO ()
shouldDecodeRecordLeft actual expected =
  case actual of
    Left err -> err `shouldBe` expected
    Right _ -> expectationFailure "expected idempotency record decoding to fail"
