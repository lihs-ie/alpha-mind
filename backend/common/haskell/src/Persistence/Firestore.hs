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
  createDocument,
  getDocument,
  upsertDocument,
  requireField,
) where

import Data.HashMap.Internal.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text, pack, unpack)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Gogol (DateTime (..), newEnv, runResourceT, sendEither)
import Gogol qualified
import Gogol.FireStore (
  Datastore'FullControl,
  Value (..),
  Value_NullValue (..),
  newValue,
 )
import Gogol.FireStore qualified as Document
import Network.HTTP.Types (Status (statusCode))
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)
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

instance (ToFirestoreValue a) => ToFirestoreValue (Maybe a) where
  toValue Nothing = newValue{nullValue = Just Value_NullValue_NULLVALUE}
  toValue (Just x) = toValue x

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
      Left err -> case err of
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
      Left err -> case err of
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
      Left err -> pure . Left $ mapFirestoreError err
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
