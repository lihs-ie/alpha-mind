module Messaging.CloudEvent (
  CloudEvent (..),
  CloudEventError (..),
  decodeCloudEvent,
  encodeCloudEvent,
  validateEventType,
)
where

import Control.Monad
import Data.Aeson (
  FromJSON (parseJSON),
  Result (..),
  ToJSON (toJSON),
  Value,
  eitherDecode,
  encode,
  fromJSON,
  object,
  withObject,
  (.:),
  (.=),
 )
import Data.ByteString.Lazy (ByteString)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.Time.Format.ISO8601 (iso8601ParseM)
import Data.ULID (ULID)
import Text.Read (readMaybe)

data CloudEvent payload = CloudEvent
  { identifier :: ULID
  , eventType :: Text.Text
  , occurredAt :: UTCTime
  , trace :: ULID
  , schemaVersion :: Text.Text
  , payload :: payload
  }
  deriving (Show)

instance (ToJSON payload) => ToJSON (CloudEvent payload) where
  toJSON event =
    object
      [ "identifier" .= show (identifier event)
      , "eventType" .= eventType event
      , "occurredAt" .= occurredAt event
      , "trace" .= show (trace event)
      , "schemaVersion" .= schemaVersion event
      , "payload" .= payload event
      ]

data RawCloudEvent = RawCloudEvent
  { rawIdentifier :: Text.Text
  , rawEventType :: Text.Text
  , rawOccurredAt :: Text.Text
  , rawTrace :: Text.Text
  , rawSchemaVersion :: Text.Text
  , rawPayload :: Value
  }

instance FromJSON RawCloudEvent where
  parseJSON =
    withObject "RawCloudEvent" $ \value ->
      RawCloudEvent
        <$> value .: "identifier"
        <*> value .: "eventType"
        <*> value .: "occurredAt"
        <*> value .: "trace"
        <*> value .: "schemaVersion"
        <*> value .: "payload"

data CloudEventError
  = CloudEventErrorJsonInvalid Text.Text
  | CloudEventErrorIdentifierInvalid Text.Text
  | CloudEventErrorTraceInvalid Text.Text
  | CloudEventErrorOccurredAtInvalid Text.Text
  | CloudEventErrorSchemaVersionEmpty
  | CloudEventErrorEventTypeMismatch Text.Text Text.Text
  | CloudEventErrorPayloadInvalid Text.Text
  deriving (Show, Eq)

parseULIDText :: (Text.Text -> CloudEventError) -> Text.Text -> Either CloudEventError ULID
parseULIDText err value = case (readMaybe (Text.unpack value) :: Maybe ULID) of
  Nothing -> Left (err value)
  Just ulid -> Right ulid

parseOccurredAt :: Text.Text -> Either CloudEventError UTCTime
parseOccurredAt value =
  if hasTimeZoneMarker value
    then maybe (Left (CloudEventErrorOccurredAtInvalid value)) Right (iso8601ParseM (Text.unpack value))
    else Left (CloudEventErrorOccurredAtInvalid value)

hasTimeZoneMarker :: Text.Text -> Bool
hasTimeZoneMarker value =
  "Z" `Text.isSuffixOf` value
    || maybe False (Text.isInfixOf "+") (timePart value)
    || maybe False (Text.isInfixOf "-") (timePart value)
 where
  timePart = fmap snd . Text.uncons . Text.dropWhile (/= 'T')

type ExpectedEventType = Text.Text

validateEventType :: ExpectedEventType -> CloudEvent payload -> Either CloudEventError (CloudEvent payload)
validateEventType expected event =
  if expected == eventType event
    then Right event
    else Left (CloudEventErrorEventTypeMismatch expected (eventType event))

decodeRawCloudEvent :: ByteString -> Either CloudEventError RawCloudEvent
decodeRawCloudEvent raw = case eitherDecode raw of
  Left message -> Left (CloudEventErrorJsonInvalid (Text.pack message))
  Right value -> Right value

toCloudEvent :: (FromJSON a) => RawCloudEvent -> Either CloudEventError (CloudEvent a)
toCloudEvent raw = do
  identifier <- parseULIDText CloudEventErrorIdentifierInvalid (rawIdentifier raw)
  occurredAt <- parseOccurredAt (rawOccurredAt raw)
  trace <- parseULIDText CloudEventErrorTraceInvalid (rawTrace raw)
  when (Text.null (rawSchemaVersion raw)) (Left CloudEventErrorSchemaVersionEmpty)
  payload <- decodePayload (rawPayload raw)
  pure
    ( CloudEvent
        { identifier = identifier
        , eventType = rawEventType raw
        , occurredAt = occurredAt
        , trace = trace
        , schemaVersion = rawSchemaVersion raw
        , payload = payload
        }
    )

decodePayload :: (FromJSON a) => Value -> Either CloudEventError a
decodePayload value =
  case fromJSON value of
    Error message -> Left (CloudEventErrorPayloadInvalid (Text.pack message))
    Success payload -> Right payload

decodeCloudEvent :: (FromJSON a) => ByteString -> Either CloudEventError (CloudEvent a)
decodeCloudEvent = decodeRawCloudEvent >=> toCloudEvent

encodeCloudEvent :: (ToJSON payload) => CloudEvent payload -> ByteString
encodeCloudEvent = encode
