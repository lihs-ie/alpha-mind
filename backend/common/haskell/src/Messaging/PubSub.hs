{-# LANGUAGE DeriveAnyClass #-}
{-# OPTIONS_GHC -fno-hpc #-}

module Messaging.PubSub (
  ProjectId,
  PublishResult (..),
  PubSubError (..),
  PubSubMessageError,
  PubSubPublisher (..),
  PubSubPushEnvelope (..),
  TopicName,
  decodeBase64Data,
  decodePubSubPush,
  decodePushEnvelope,
  mkPublishRequestBody,
  mkTopicPath,
  publishCloudEvent,
)
where

import Control.Exception (SomeException, try)
import Data.Aeson (FromJSON (parseJSON), ToJSON (toJSON), eitherDecode, encode, object, withObject, (.:), (.=))
import Data.Base64.Types (extractBase64)
import Data.Bifunctor (Bifunctor (first))
import Data.ByteString.Base64 (decodeBase64Untyped, encodeBase64)
import Data.ByteString.Lazy (ByteString, fromStrict, toStrict)
import Data.Text qualified as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Time (UTCTime)
import Messaging.CloudEvent (CloudEvent, CloudEventError, decodeCloudEvent, encodeCloudEvent)
import Network.HTTP.Client (
  Manager,
  Request (..),
  RequestBody (RequestBodyLBS),
  Response (responseBody, responseStatus),
  httpLbs,
  parseRequest,
 )
import Network.HTTP.Types (statusCode)
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)

data PubSubPushEnvelope = PubSubPushEnvelope
  { messageId :: Text.Text
  , publishTime :: UTCTime
  , dataBase64 :: Text.Text
  }

instance FromJSON PubSubPushEnvelope where
  parseJSON =
    withObject "PubSubPushEnvelope" $ \root ->
      root .: "message" >>= withObject "PubSubPushMessage" parseMessage
   where
    parseMessage message =
      PubSubPushEnvelope
        <$> message .: "messageId"
        <*> message .: "publishTime"
        <*> message .: "data"

instance ToJSON PubSubPushEnvelope where
  toJSON envelope =
    object
      [ "message" .= object
          [ "messageId" .= envelope.messageId
          , "publishTime" .= envelope.publishTime
          , "data" .= envelope.dataBase64
          ]
      ]

data PubSubError
  = PubSubErrorJsonInvalid Text.Text
  | PubSubErrorBase64Invalid Text.Text
  | PubSubErrorPayloadInvalid Text.Text
  | PubSubErrorPublishFailed Text.Text
  | PubSubErrorPublishRetryable Text.Text
  deriving (Show, Eq)

type PubSubMessageError = PubSubError

decodePushEnvelope :: ByteString -> Either PubSubError PubSubPushEnvelope
decodePushEnvelope body = case eitherDecode body of
  Left err -> Left (PubSubErrorJsonInvalid (Text.pack err))
  Right value -> Right value

decodeBase64Data :: PubSubPushEnvelope -> Either PubSubError ByteString
decodeBase64Data envelope = case decodeBase64Untyped (encodeUtf8 envelope.dataBase64) of
  Left err -> Left (PubSubErrorBase64Invalid (Text.pack (show err)))
  Right value -> Right (fromStrict value)

toPayloadError :: CloudEventError -> PubSubError
toPayloadError err = PubSubErrorPayloadInvalid (Text.pack (show err))

decodePubSubPush :: (FromJSON payload) => ByteString -> Either PubSubError (CloudEvent payload)
decodePubSubPush body =
  decodePushEnvelope body
    >>= decodeBase64Data
    >>= (first toPayloadError . decodeCloudEvent)

type ProjectId = Text.Text

type TopicName = Text.Text

mkTopicPath :: ProjectId -> TopicName -> Text.Text
mkTopicPath project topicName = "projects/" <> project <> "/topics/" <> topicName

mkPublishRequestBody :: (ToJSON payload) => CloudEvent payload -> ByteString
mkPublishRequestBody event =
  let eventBytes = toStrict (encodeCloudEvent event)
      base64Data = extractBase64 (encodeBase64 eventBytes)
   in encode (object ["messages" .= [object ["data" .= base64Data]]])

data PubSubPublisher = PubSubPublisher
  { manager :: Manager
  , projectId :: ProjectId
  , baseURL :: Text.Text
  , accessToken :: IO Text.Text
  }

newtype PublishResult = PublishResult
  { publishedMessageId :: Text.Text
  }

newtype PublishResponse = PublishResponse [Text.Text]

instance FromJSON PublishResponse where
  parseJSON =
    withObject "PublishResponse" $ \value ->
      PublishResponse <$> value .: "messageIds"

publishCloudEvent ::
  (ToJSON payload) =>
  PubSubPublisher ->
  TopicName ->
  CloudEvent payload ->
  IO (Either PubSubError PublishResult)
publishCloudEvent publisher topicName event =
  withRetry defaultRetryPolicyConfig isRetryablePubSubError (publishOnce publisher topicName event)

isRetryablePubSubError :: PubSubError -> Bool
isRetryablePubSubError (PubSubErrorPublishRetryable _) = True
isRetryablePubSubError _ = False

publishOnce ::
  (ToJSON payload) =>
  PubSubPublisher ->
  TopicName ->
  CloudEvent payload ->
  IO (Either PubSubError PublishResult)
publishOnce publisher topicName event = do
  let topicPath = mkTopicPath publisher.projectId topicName
      url = publisher.baseURL <> topicPath <> ":publish"
      body = mkPublishRequestBody event
  token <- publisher.accessToken
  baseRequest <- parseRequest (Text.unpack url)
  let request =
        baseRequest
          { method = "POST"
          , requestBody = RequestBodyLBS body
          , requestHeaders = [("Content-Type", "application/json"), ("Authorization", "Bearer " <> encodeUtf8 token)]
          }
  result <- try (httpLbs request publisher.manager)
  case result of
    Left (exception :: SomeException) -> pure (Left (PubSubErrorPublishRetryable (Text.pack (show exception))))
    Right response
      | isSuccess (statusCode (responseStatus response)) ->
          pure (decodePublishResponse (responseBody response))
      | isRetryableStatus (statusCode (responseStatus response)) ->
          pure (Left (PubSubErrorPublishRetryable (Text.pack (show (responseBody response)))))
      | otherwise ->
          pure (Left (PubSubErrorPublishFailed (Text.pack (show (responseBody response)))))

isSuccess :: Int -> Bool
isSuccess code = code >= 200 && code < 300

isRetryableStatus :: Int -> Bool
isRetryableStatus code = code == 429 || code >= 500

decodePublishResponse :: ByteString -> Either PubSubError PublishResult
decodePublishResponse body =
  case eitherDecode body of
    Left err -> Left (PubSubErrorPublishFailed (Text.pack err))
    Right (PublishResponse (firstId : _)) -> Right (PublishResult firstId)
    Right (PublishResponse []) -> Left (PubSubErrorPublishFailed "empty messageIds")
