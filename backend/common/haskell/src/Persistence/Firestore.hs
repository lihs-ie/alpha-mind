{-# LANGUAGE OverloadedRecordDot #-}
{-# OPTIONS_GHC -fno-hpc #-}

module Persistence.Firestore (
  FirestoreContext (..),
  CollectionName (..),
  DocumentId (..),
  FirestoreError (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  FromFirestore (..),
  FromFirestoreValue (..),
  QueryFilter (..),
  QueryOrder (..),
  SortDirection (..),
  QueryCursor (..),
  createDocument,
  getDocument,
  upsertDocument,
  deleteDocument,
  runQuery,
  requireField,
  toMapValue,
  isRetryableFirestoreError,
) where

import Data.Aeson (eitherDecode, encode)
import Data.HashMap.Internal.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Int (Int64)
import Data.Text (Text, pack, unpack)
import Data.Text qualified as Text
import Data.Text.Encoding (encodeUtf8)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Gogol (AccessToken (..), DateTime (..), newEnv, runResourceT, sendEither)
import Gogol qualified
import Gogol.Auth (OAuthToken (..), retrieveTokenFromStore)
import Gogol.Env (Env (..))
import Gogol.FireStore (
  CollectionSelector (..),
  CompositeFilter (..),
  CompositeFilter_Op (..),
  Cursor (..),
  Datastore'FullControl,
  FieldFilter (..),
  FieldFilter_Op (..),
  FieldReference (..),
  Filter (..),
  MapValue (..),
  Order (..),
  Order_Direction (..),
  RunQueryRequest (..),
  RunQueryResponse (..),
  StructuredQuery (..),
  Value (..),
  Value_NullValue (..),
  newCollectionSelector,
  newCompositeFilter,
  newCursor,
  newFieldFilter,
  newFieldReference,
  newFilter,
  newFireStoreProjectsDatabasesDocumentsDelete,
  newMapValue,
  newMapValue_Fields,
  newOrder,
  newRunQueryRequest,
  newStructuredQuery,
  newValue,
 )
import Gogol.FireStore qualified as Document
import Network.HTTP.Client (
  Request (..),
  RequestBody (..),
  Response (..),
  httpLbs,
  parseRequest,
 )
import Network.HTTP.Types (Status (statusCode))
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)
import System.Environment (lookupEnv)
import Text.Read (readMaybe)

data FirestoreContext = FirestoreContext
  { projectId :: Text
  , databaseId :: Text
  }

newtype CollectionName = CollectionName Text
newtype DocumentId = DocumentId Text

data FirestoreError
  = FirestoreErrorDecode Text
  | FirestoreErrorPermissionDenied Text
  | FirestoreErrorTransport Text
  | FirestoreErrorUnexpected Int Text
  deriving (Show, Eq)

class ToFirestore a where
  toFirestoreFields :: a -> HashMap Text Value

class ToFirestoreValue a where
  toValue :: a -> Value

instance ToFirestoreValue Text where
  toValue text = newValue{stringValue = Just text}

instance ToFirestoreValue UTCTime where
  toValue time = newValue{timestampValue = Just (DateTime time)}

instance ToFirestoreValue ULID where
  toValue ulid = newValue{stringValue = Just (pack (show ulid))}

instance ToFirestoreValue Bool where
  toValue boolean = newValue{booleanValue = Just boolean}

instance ToFirestoreValue Int64 where
  toValue integer = newValue{integerValue = Just integer}

instance (ToFirestoreValue a) => ToFirestoreValue (Maybe a) where
  toValue Nothing = newValue{nullValue = Just Value_NullValue_NULLVALUE}
  toValue (Just x) = toValue x

{- | Convert a 'HashMap' of 'Text' keys to a Firestore map 'Value'.
Useful for storing @payloadSummary@ and similar nested map fields.
-}
toMapValue :: HashMap Text Value -> Value
toMapValue fieldMap =
  newValue
    { mapValue =
        Just
          newMapValue
            { fields = Just (newMapValue_Fields fieldMap)
            }
    }

class FromFirestore a where
  fromFirestoreFields :: HashMap Text Value -> Either Text a

class FromFirestoreValue a where
  extractValue :: Text -> Value -> Either Text a

instance FromFirestoreValue Text where
  extractValue name value = case value.stringValue of
    Nothing -> Left ("field " <> name <> "is not a string")
    Just target -> Right target

instance FromFirestoreValue UTCTime where
  extractValue name value = case value.timestampValue of
    Nothing -> Left ("field" <> name <> "is not timestamp")
    Just target -> Right (unDateTime target)

instance FromFirestoreValue ULID where
  extractValue name value = case value.stringValue of
    Nothing -> Left ("field" <> name <> "is not a string")
    Just text -> case readMaybe (unpack text) of
      Nothing -> Left ("field" <> name <> "is not a valid ULID")
      Just ulid -> Right ulid

instance FromFirestoreValue Bool where
  extractValue name value = case value.booleanValue of
    Nothing -> Left ("field " <> name <> " is not a boolean")
    Just boolean -> Right boolean

instance FromFirestoreValue Int64 where
  extractValue name value = case value.integerValue of
    Nothing -> Left ("field " <> name <> " is not an integer")
    Just integer -> Right integer

instance (FromFirestoreValue a) => FromFirestoreValue (Maybe a) where
  extractValue name value = case value.nullValue of
    Just _ -> Right Nothing
    Nothing -> Just <$> extractValue name value

requireField :: (FromFirestoreValue a) => Text -> HashMap Text Value -> Either Text a
requireField key fields = case HashMap.lookup key fields of
  Nothing -> Left ("missing field: " <> key)
  Just value -> extractValue key value

buildDocumentPath :: FirestoreContext -> CollectionName -> DocumentId -> Text
buildDocumentPath context (CollectionName collection) (DocumentId document) =
  "projects/"
    <> projectId context
    <> "/databases/"
    <> databaseId context
    <> "/documents/"
    <> collection
    <> "/"
    <> document

getDocument ::
  (FromFirestore a) =>
  FirestoreContext ->
  CollectionName ->
  DocumentId ->
  IO (Either FirestoreError (Maybe a))
getDocument context collection document =
  withRetry defaultRetryPolicyConfig isRetryableFirestoreError $
    getDocumentOnce context collection document

getDocumentOnce ::
  (FromFirestore a) =>
  FirestoreContext ->
  CollectionName ->
  DocumentId ->
  IO (Either FirestoreError (Maybe a))
getDocumentOnce context collection document = do
  environment <- newEnv @'[Datastore'FullControl]
  runResourceT $ do
    let path = buildDocumentPath context collection document
        request = Document.newFireStoreProjectsDatabasesDocumentsGet path
    result <- sendEither environment request
    case result of
      Left firestoreError -> case firestoreError of
        Gogol.TransportError exception -> pure . Left $ FirestoreErrorTransport (pack (show exception))
        Gogol.SerializeError serializeError -> pure . Left $ FirestoreErrorDecode (pack (Gogol._serializeMessage serializeError))
        Gogol.ServiceError serviceError ->
          case statusCode (Gogol._serviceStatus serviceError) of
            403 -> pure . Left $ FirestoreErrorPermissionDenied (pack "Firebase access denied")
            404 -> pure (Right Nothing)
            other -> pure . Left $ FirestoreErrorUnexpected other (pack (show (Gogol._serviceBody serviceError)))
      Right Document.Document{Document.fields = documentFields} -> case documentFields of
        Nothing -> pure (Right Nothing)
        Just Document.Document_Fields{Document.additional = fieldMap} -> case fromFirestoreFields fieldMap of
          Left message -> pure . Left $ FirestoreErrorDecode message
          Right decoded -> pure (Right (Just decoded))

upsertDocument ::
  (ToFirestore a) =>
  FirestoreContext ->
  CollectionName ->
  DocumentId ->
  a ->
  IO (Either FirestoreError ())
upsertDocument context collection documentID value =
  withRetry defaultRetryPolicyConfig isRetryableFirestoreError $
    upsertDocumentOnce context collection documentID value

upsertDocumentOnce ::
  (ToFirestore a) =>
  FirestoreContext ->
  CollectionName ->
  DocumentId ->
  a ->
  IO (Either FirestoreError ())
upsertDocumentOnce context collection documentID value = do
  environment <- newEnv @'[Datastore'FullControl]
  runResourceT $ do
    let path = buildDocumentPath context collection documentID
        fieldMap = toFirestoreFields value
        document =
          Document.Document
            { Document.createTime = Nothing
            , Document.updateTime = Nothing
            , Document.name = Just path
            , Document.fields = Just (Document.Document_Fields{Document.additional = fieldMap})
            }
        request = Document.newFireStoreProjectsDatabasesDocumentsPatch path document
    result <- sendEither environment request
    case result of
      Left firestoreError -> case firestoreError of
        Gogol.TransportError exception -> pure . Left $ FirestoreErrorTransport (pack (show exception))
        Gogol.SerializeError serializeError -> pure . Left $ FirestoreErrorDecode (pack (Gogol._serializeMessage serializeError))
        Gogol.ServiceError serviceError -> pure . Left $ case statusCode (Gogol._serviceStatus serviceError) of
          403 -> FirestoreErrorPermissionDenied "Firestore access denied"
          other -> FirestoreErrorUnexpected other (pack (show (Gogol._serviceBody serviceError)))
      Right _ -> pure (Right ())

createDocument ::
  (ToFirestore a) =>
  FirestoreContext ->
  CollectionName ->
  DocumentId ->
  a ->
  IO (Either FirestoreError ())
createDocument context collection documentID value =
  withRetry defaultRetryPolicyConfig isRetryableFirestoreError $
    createDocumentOnce context collection documentID value

createDocumentOnce ::
  (ToFirestore a) =>
  FirestoreContext ->
  CollectionName ->
  DocumentId ->
  a ->
  IO (Either FirestoreError ())
createDocumentOnce context collection@(CollectionName collectionName) documentID@(DocumentId documentName) value = do
  environment <- newEnv @'[Datastore'FullControl]
  runResourceT $ do
    let parent =
          "projects/"
            <> projectId context
            <> "/databases/"
            <> databaseId context
            <> "/documents"
        fieldMap = toFirestoreFields value
        path = buildDocumentPath context collection documentID
        document =
          Document.Document
            { Document.createTime = Nothing
            , Document.updateTime = Nothing
            , Document.name = Just path
            , Document.fields = Just (Document.Document_Fields{Document.additional = fieldMap})
            }
        request =
          (Document.newFireStoreProjectsDatabasesDocumentsCreateDocument parent collectionName document)
            { Document.documentId = Just documentName
            }
    result <- sendEither environment request
    case result of
      Left gogolError -> pure . Left $ mapFirestoreError gogolError
      Right _ -> pure (Right ())

mapFirestoreError :: Gogol.Error -> FirestoreError
mapFirestoreError (Gogol.TransportError exception) =
  FirestoreErrorTransport (pack (show exception))
mapFirestoreError (Gogol.SerializeError serializeError) =
  FirestoreErrorDecode (pack (Gogol._serializeMessage serializeError))
mapFirestoreError (Gogol.ServiceError serviceError) =
  case statusCode (Gogol._serviceStatus serviceError) of
    403 -> FirestoreErrorPermissionDenied "Firestore access denied"
    other -> FirestoreErrorUnexpected other (pack (show (Gogol._serviceBody serviceError)))

isRetryableFirestoreError :: FirestoreError -> Bool
isRetryableFirestoreError (FirestoreErrorTransport _) = True
isRetryableFirestoreError (FirestoreErrorUnexpected status _) = status == 429 || status >= 500
isRetryableFirestoreError _ = False

-- ---------------------------------------------------------------------------
-- deleteDocument
-- ---------------------------------------------------------------------------

deleteDocument ::
  FirestoreContext ->
  CollectionName ->
  DocumentId ->
  IO (Either FirestoreError ())
deleteDocument context collection documentIdentifier =
  withRetry defaultRetryPolicyConfig isRetryableFirestoreError $
    deleteDocumentOnce context collection documentIdentifier

deleteDocumentOnce ::
  FirestoreContext ->
  CollectionName ->
  DocumentId ->
  IO (Either FirestoreError ())
deleteDocumentOnce context collection documentIdentifier = do
  environment <- newEnv @'[Datastore'FullControl]
  runResourceT $ do
    let path = buildDocumentPath context collection documentIdentifier
        request = newFireStoreProjectsDatabasesDocumentsDelete path
    result <- sendEither environment request
    case result of
      Left gogolError -> pure . Left $ mapFirestoreError gogolError
      Right _ -> pure (Right ())

-- ---------------------------------------------------------------------------
-- Query types
-- ---------------------------------------------------------------------------

-- | A single equality filter: field == value.
data QueryFilter = QueryFilterEqual
  { filterField :: Text
  , filterValue :: Value
  }

data SortDirection = Ascending | Descending

data QueryOrder = QueryOrder
  { orderField :: Text
  , orderDirection :: SortDirection
  }

{- | Opaque cursor for pagination.  Pass the 'Value' of the @occurredAt@
timestamp (or any field used as the last order key) from the last returned
document to continue from that point.
-}
newtype QueryCursor = QueryCursor {cursorValues :: [Value]}

-- ---------------------------------------------------------------------------
-- runQuery
-- ---------------------------------------------------------------------------

{- | Execute a structured Firestore query against a collection.

The query applies each 'QueryFilter' as an equality filter combined with
AND, orders results according to 'QueryOrder' entries, applies a 'limit',
and – when a 'QueryCursor' is provided – uses @startAfter@ to implement
keyset pagination.
-}
runQuery ::
  (FromFirestore a) =>
  FirestoreContext ->
  CollectionName ->
  [QueryFilter] ->
  [QueryOrder] ->
  Int ->
  Maybe QueryCursor ->
  IO (Either FirestoreError [a])
runQuery context collection filters orders limitCount maybeCursor =
  withRetry defaultRetryPolicyConfig isRetryableFirestoreError $
    runQueryOnce context collection filters orders limitCount maybeCursor

runQueryOnce ::
  (FromFirestore a) =>
  FirestoreContext ->
  CollectionName ->
  [QueryFilter] ->
  [QueryOrder] ->
  Int ->
  Maybe QueryCursor ->
  IO (Either FirestoreError [a])
runQueryOnce context (CollectionName collectionName) filters orders limitCount maybeCursor = do
  let structuredQuery = buildStructuredQuery collectionName filters orders limitCount maybeCursor
      queryRequest = newRunQueryRequest{structuredQuery = Just structuredQuery}
  result <- executeRunQueryHttp (projectId context) (databaseId context) queryRequest
  case result of
    Left errorMessage -> pure . Left $ FirestoreErrorDecode (pack errorMessage)
    Right responses -> pure $ decodeQueryResponses responses

buildStructuredQuery ::
  Text ->
  [QueryFilter] ->
  [QueryOrder] ->
  Int ->
  Maybe QueryCursor ->
  StructuredQuery
buildStructuredQuery collectionName filters orders limitCount maybeCursor =
  newStructuredQuery
    { from = Just [newCollectionSelector{collectionId = Just collectionName}]
    , where' = buildWhereClause filters
    , orderBy = Just (map toOrder orders)
    , limit = Just (fromIntegral limitCount)
    , startAt = fmap toCursor maybeCursor
    }

buildWhereClause :: [QueryFilter] -> Maybe Filter
buildWhereClause [] = Nothing
buildWhereClause [singleFilter] = Just (toFieldFilter singleFilter)
buildWhereClause multipleFilters =
  Just
    newFilter
      { compositeFilter =
          Just
            newCompositeFilter
              { filters = Just (map toFieldFilter multipleFilters)
              , op = Just CompositeFilter_Op_And
              }
      }

toFieldFilter :: QueryFilter -> Filter
toFieldFilter (QueryFilterEqual fieldName value) =
  newFilter
    { fieldFilter =
        Just
          newFieldFilter
            { field = Just newFieldReference{fieldPath = Just fieldName}
            , op = Just FieldFilter_Op_Equal
            , value = Just value
            }
    }

toOrder :: QueryOrder -> Order
toOrder (QueryOrder fieldName direction) =
  newOrder
    { field = Just newFieldReference{fieldPath = Just fieldName}
    , direction = Just (toOrderDirection direction)
    }

toOrderDirection :: SortDirection -> Order_Direction
toOrderDirection Ascending = Order_Direction_Ascending
toOrderDirection Descending = Order_Direction_Descending

toCursor :: QueryCursor -> Cursor
toCursor (QueryCursor values) =
  newCursor
    { values = Just values
    , before = Just False
    }

{- | Decode a list of 'RunQueryResponse' values returned by the Firestore
 `:runQuery` REST endpoint.

 Each element that carries a @document@ field is decoded via 'fromFirestoreFields'.
 Elements without a @document@ (e.g. the terminal @{\"done\":true}@ sentinel) are
 silently skipped.  The first decode failure short-circuits with 'Left'.
-}
decodeQueryResponses ::
  (FromFirestore a) =>
  [RunQueryResponse] ->
  Either FirestoreError [a]
decodeQueryResponses responses = go responses []
 where
  go [] accumulator = Right (reverse accumulator)
  go (response : rest) accumulator =
    case response.document of
      Nothing -> go rest accumulator
      Just Document.Document{Document.fields = documentFields} ->
        case documentFields of
          Nothing -> go rest accumulator
          Just Document.Document_Fields{Document.additional = fieldMap} ->
            case fromFirestoreFields fieldMap of
              Left message -> Left (FirestoreErrorDecode message)
              Right decoded -> go rest (decoded : accumulator)

{- | Execute a Firestore @:runQuery@ request via a direct HTTP call, returning
 the raw list of 'RunQueryResponse' values.

 gogol-firestore 1.0.0 maps @Rs FireStoreProjectsDatabasesDocumentsRunQuery@ to
 a single 'RunQueryResponse', but the Firestore REST API returns a JSON array
 @[RunQueryResponse]@.  Using gogol\'s @sendEither@ therefore produces a
 'SerializeError' when the collection contains more than zero matching
 documents.  This function works around that limitation by performing the HTTP
 request manually and decoding the response body as @[RunQueryResponse]@ with
 Aeson.

 When @FIRESTORE_EMULATOR_HOST@ is set the request is sent to the emulator
 without an OAuth bearer token; otherwise Application Default Credentials are
 used via @retrieveTokenFromStore@.
-}
executeRunQueryHttp ::
  Text ->
  Text ->
  RunQueryRequest ->
  IO (Either String [RunQueryResponse])
executeRunQueryHttp projectIdentifier databaseIdentifier queryRequest = do
  maybeEmulatorHost <- lookupEnv "FIRESTORE_EMULATOR_HOST"
  let baseUrl = case maybeEmulatorHost of
        Just emulatorHost -> "http://" <> emulatorHost
        Nothing -> "https://firestore.googleapis.com"
      fullUrl =
        baseUrl
          <> "/v1/projects/"
          <> Text.unpack projectIdentifier
          <> "/databases/"
          <> Text.unpack databaseIdentifier
          <> "/documents:runQuery"
  environment <- newEnv @'[Datastore'FullControl]
  let manager = _envManager environment
      store = _envStore environment
      logger = _envLogger environment
  requestTemplate <- parseRequest ("POST " <> fullUrl)
  let bodyBytes = encode queryRequest
      baseRequest =
        requestTemplate
          { requestBody = RequestBodyLBS bodyBytes
          , requestHeaders =
              [("Content-Type", "application/json"), ("Accept", "application/json")]
          }
  httpRequest <- case maybeEmulatorHost of
    Just _ -> return baseRequest
    Nothing -> do
      oauthToken <- retrieveTokenFromStore store logger manager
      let OAuthToken (AccessToken tokenText) _ _ = oauthToken
          authorizationHeader = encodeUtf8 ("Bearer " <> tokenText)
      return
        baseRequest
          { requestHeaders =
              requestHeaders baseRequest <> [("Authorization", authorizationHeader)]
          }
  httpResponse <- httpLbs httpRequest manager
  let responseBodyBytes = responseBody httpResponse
  case eitherDecode responseBodyBytes of
    Left parseError -> return $ Left parseError
    Right responses -> return (Right responses)
