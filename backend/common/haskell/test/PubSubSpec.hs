{-# LANGUAGE OverloadedStrings #-}

module PubSubSpec (spec) where

import Data.Aeson (Value, eitherDecode, encode, object, (.=))
import Data.Base64.Types (extractBase64)
import Data.ByteString.Base64 (encodeBase64)
import Data.ByteString.Lazy (toStrict)
import Data.Text qualified as Text
import Messaging.CloudEvent (CloudEvent (..), encodeCloudEvent)
import Messaging.PubSub (
  PubSubError (..),
  PubSubPushEnvelope (..),
  decodeBase64Data,
  decodePubSubPush,
  decodePushEnvelope,
  mkPublishRequestBody,
  mkTopicPath,
 )
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe)
import TestFixtures (sampleIdentifier, sampleTime, sampleTrace)

spec :: Spec
spec =
  describe "Messaging.PubSub" $ do
    it "builds Pub/Sub topic paths" $
      mkTopicPath "project-alpha" "topic-a"
        `shouldBe` "projects/project-alpha/topics/topic-a"

    it "decodes push envelopes" $
      case decodePushEnvelope (encode sampleEnvelope) of
        Left err -> err `shouldBe` PubSubErrorJsonInvalid "unexpected failure"
        Right envelope -> do
          messageId envelope `shouldBe` "message-1"
          dataBase64 envelope `shouldBe` encodedEvent

    it "rejects invalid push envelope JSON" $
      shouldDecodePushEnvelopeJsonInvalid (decodePushEnvelope "{")

    it "decodes base64 push data" $
      decodeBase64Data sampleEnvelope `shouldBe` Right (encodeCloudEvent sampleEvent)

    it "rejects invalid base64 push data" $
      shouldDecodeBase64Invalid
        (decodeBase64Data sampleEnvelope{dataBase64 = "!"})

    it "decodes push data into a CloudEvent" $
      case decodePubSubPush @Value (encode sampleEnvelope) of
        Left err -> err `shouldBe` PubSubErrorPayloadInvalid "unexpected failure"
        Right event -> do
          identifier event `shouldBe` sampleIdentifier
          payload event `shouldBe` samplePayload

    it "encodes publish request bodies" $
      eitherDecode (mkPublishRequestBody sampleEvent)
        `shouldBe` Right expectedPublishBody

sampleEnvelope :: PubSubPushEnvelope
sampleEnvelope =
  PubSubPushEnvelope
    { dataBase64 = encodedEvent
    , messageId = "message-1"
    , publishTime = sampleTime
    }

encodedEvent :: Text.Text
encodedEvent =
  extractBase64 (encodeBase64 (toStrict (encodeCloudEvent sampleEvent)))

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

expectedPublishBody :: Value
expectedPublishBody =
  object ["messages" .= [object ["data" .= encodedEvent]]]

shouldDecodePushEnvelopeJsonInvalid :: Either PubSubError PubSubPushEnvelope -> IO ()
shouldDecodePushEnvelopeJsonInvalid actual =
  case actual of
    Left (PubSubErrorJsonInvalid _) -> pure ()
    Left err -> expectationFailure ("expected PubSubErrorJsonInvalid, got: " <> show err)
    Right _ -> expectationFailure "expected PubSub push envelope decoding to fail"

shouldDecodeBase64Invalid :: Either PubSubError a -> IO ()
shouldDecodeBase64Invalid actual =
  case actual of
    Left (PubSubErrorBase64Invalid _) -> pure ()
    Left err -> expectationFailure ("expected PubSubErrorBase64Invalid, got: " <> show err)
    Right _ -> expectationFailure "expected base64 decoding to fail"
