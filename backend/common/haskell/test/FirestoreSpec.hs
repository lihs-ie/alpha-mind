{-# LANGUAGE OverloadedStrings #-}

module FirestoreSpec (spec) where

import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.ULID (ULID)
import Gogol (DateTime (..))
import Gogol.FireStore (Value (..), Value_NullValue (..), newValue)
import Persistence.Firestore (
  FirestoreError (..),
  FromFirestore (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  requireField,
 )
import Test.Hspec (Spec, describe, it, shouldBe)
import TestFixtures (sampleIdentifier, sampleTime)

newtype ExampleDocument = ExampleDocument Text
  deriving stock (Eq, Show)

instance FromFirestore ExampleDocument where
  fromFirestoreFields fields =
    ExampleDocument <$> requireField "name" fields

instance ToFirestore ExampleDocument where
  toFirestoreFields (ExampleDocument name) =
    HashMap.fromList [("name", toValue name)]

spec :: Spec
spec =
  describe "Persistence.Firestore" $ do
    it "converts Text values" $
      getStringValue (toValue ("alice" :: Text)) `shouldBe` Just "alice"

    it "converts UTCTime values" $
      getTimestampValue (toValue sampleTime) `shouldBe` Just (DateTime sampleTime)

    it "converts ULID values" $
      getStringValue (toValue sampleIdentifier) `shouldBe` Just "01ARZ3NDEKTSV4RRFFQ69G5FAV"

    it "converts Maybe values" $ do
      getStringValue (toValue (Just ("alice" :: Text))) `shouldBe` Just "alice"
      getNullValue (toValue (Nothing :: Maybe Text)) `shouldBe` Just Value_NullValue_NULLVALUE

    it "requires present fields" $
      requireField @Text "name" (HashMap.fromList [("name", toValue ("alice" :: Text))])
        `shouldBe` Right "alice"

    it "rejects missing fields" $
      requireField @Text "name" HashMap.empty
        `shouldBe` Left "missing field: name"

    it "rejects values with unexpected types" $
      requireField @Text "name" (HashMap.fromList [("name", newValue{integerValue = Just 1})])
        `shouldBe` Left "field nameis not a string"

    it "parses ULID fields" $
      requireField @ULID "identifier" (HashMap.fromList [("identifier", toValue sampleIdentifier)])
        `shouldBe` Right sampleIdentifier

    it "rejects invalid ULID fields" $
      requireField @ULID "identifier" (HashMap.fromList [("identifier", toValue ("invalid" :: Text))])
        `shouldBe` Left "fieldidentifieris not a valid ULID"

    it "round-trips a simple Firestore document via class instances" $
      fromFirestoreFields (toFirestoreFields (ExampleDocument "alice"))
        `shouldBe` Right (ExampleDocument "alice")

    it "uses design-aligned Firestore error constructors" $ do
      FirestoreErrorDecode "decode" `shouldBe` FirestoreErrorDecode "decode"
      FirestoreErrorPermissionDenied "denied" `shouldBe` FirestoreErrorPermissionDenied "denied"
      FirestoreErrorTransport "transport" `shouldBe` FirestoreErrorTransport "transport"
      FirestoreErrorUnexpected 500 "body" `shouldBe` FirestoreErrorUnexpected 500 "body"

    it "decodes Maybe fields from null values" $
      requireField @(Maybe Text) "name" (HashMap.fromList [("name", toValue (Nothing :: Maybe Text))])
        `shouldBe` Right Nothing

    it "decodes Maybe fields from concrete values" $
      requireField @(Maybe Text) "name" (HashMap.fromList [("name", toValue ("alice" :: Text))])
        `shouldBe` Right (Just "alice")

getStringValue :: Value -> Maybe Text
getStringValue Value{stringValue = value} = value

getTimestampValue :: Value -> Maybe DateTime
getTimestampValue Value{timestampValue = value} = value

getNullValue :: Value -> Maybe Value_NullValue
getNullValue Value{nullValue = value} = value
