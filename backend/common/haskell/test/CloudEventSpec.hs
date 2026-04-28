{-# LANGUAGE OverloadedStrings #-}

module CloudEventSpec (spec) where

import Data.Aeson (Value, encode, object, (.=))
import Messaging.CloudEvent (
  CloudEvent (..),
  CloudEventError (..),
  decodeCloudEvent,
  encodeCloudEvent,
  validateEventType,
 )
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)
import TestFixtures (sampleIdentifier, sampleTime, sampleTrace)

spec :: Spec
spec =
  describe "Messaging.CloudEvent" $ do
    it "encodes and decodes a CloudEvent" $
      case decodeCloudEvent (encodeCloudEvent sampleEvent) of
        Left err -> err `shouldBe` CloudEventErrorJsonInvalid "unexpected failure"
        Right actual -> do
          identifier actual `shouldBe` sampleIdentifier
          eventType actual `shouldBe` "portfolio.created"
          occurredAt actual `shouldBe` sampleTime
          trace actual `shouldBe` sampleTrace
          schemaVersion actual `shouldBe` "1"
          payload actual `shouldBe` samplePayload

    it "rejects invalid JSON" $
      shouldDecodeJsonInvalid (decodeCloudEvent @Value "{")

    it "rejects invalid identifiers" $
      shouldDecodeLeft
        (decodeCloudEvent @Value (encode (rawEvent "invalid" (show sampleTrace) "1" "2026-03-07T12:34:56Z")))
        (CloudEventErrorIdentifierInvalid "invalid")

    it "rejects invalid trace identifiers" $
      shouldDecodeLeft
        (decodeCloudEvent @Value (encode (rawEvent (show sampleIdentifier) "invalid" "1" "2026-03-07T12:34:56Z")))
        (CloudEventErrorTraceInvalid "invalid")

    it "rejects invalid occurrence timestamps" $
      shouldDecodeLeft
        (decodeCloudEvent @Value (encode (rawEvent (show sampleIdentifier) (show sampleTrace) "1" "not-time")))
        (CloudEventErrorOccurredAtInvalid "not-time")

    it "rejects occurrence timestamps without timezone" $
      shouldDecodeLeft
        (decodeCloudEvent @Value (encode (rawEvent (show sampleIdentifier) (show sampleTrace) "1" "2026-03-07T12:34:56")))
        (CloudEventErrorOccurredAtInvalid "2026-03-07T12:34:56")

    it "rejects empty schema versions" $
      shouldDecodeLeft
        (decodeCloudEvent @Value (encode (rawEvent (show sampleIdentifier) (show sampleTrace) "" "2026-03-07T12:34:56Z")))
        CloudEventErrorSchemaVersionEmpty

    it "classifies payload decode failures separately from envelope JSON failures" $
      shouldDecodeLeft
        (decodeCloudEvent @String (encode (rawEvent (show sampleIdentifier) (show sampleTrace) "1" "2026-03-07T12:34:56Z")))
        (CloudEventErrorPayloadInvalid "expected String, but encountered Object")

    it "validates event type with exact matching" $
      case validateEventType "portfolio.deleted" sampleEvent of
        Left err -> err `shouldBe` CloudEventErrorEventTypeMismatch "portfolio.deleted" "portfolio.created"
        Right _ -> expectationFailure "expected event type validation to fail"

sampleEvent :: CloudEvent Value
sampleEvent =
  CloudEvent
    { identifier = sampleIdentifier
    , eventType = "portfolio.created"
    , occurredAt = sampleTime
    , trace = sampleTrace
    , schemaVersion = "1"
    , payload = samplePayload
    }

samplePayload :: Value
samplePayload =
  object ["name" .= ("alpha" :: String)]

rawEvent :: String -> String -> String -> String -> Value
rawEvent rawIdentifier rawTrace rawSchemaVersion rawOccurredAt =
  object
    [ "identifier" .= rawIdentifier
    , "eventType" .= ("portfolio.created" :: String)
    , "occurredAt" .= rawOccurredAt
    , "trace" .= rawTrace
    , "schemaVersion" .= rawSchemaVersion
    , "payload" .= samplePayload
    ]

shouldDecodeLeft :: Either CloudEventError (CloudEvent payload) -> CloudEventError -> IO ()
shouldDecodeLeft actual expected =
  case actual of
    Left err -> err `shouldBe` expected
    Right _ -> expectationFailure "expected CloudEvent decoding to fail"

shouldDecodeJsonInvalid :: Either CloudEventError (CloudEvent Value) -> IO ()
shouldDecodeJsonInvalid actual =
  case actual of
    Left (CloudEventErrorJsonInvalid _) -> pure ()
    Left err -> expectationFailure ("expected CloudEventErrorJsonInvalid, got: " <> show err)
    Right _ -> expectationFailure "expected CloudEvent decoding to fail"
