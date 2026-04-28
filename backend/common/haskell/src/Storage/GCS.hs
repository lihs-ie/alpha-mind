{-# OPTIONS_GHC -fno-hpc #-}

module Storage.GCS (
  GcsContext (..),
  GcsError (..),
  GcsMetadata,
  GcsObjectRef (..),
  defaultGcsContext,
  parseGsUri,
  downloadObject,
  uploadObject,
  uploadObjectWithMetadata,
)
where

import Data.Bifunctor (first, second)
import Data.ByteString.Lazy (ByteString)
import Data.Functor (void)
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Gogol qualified
import Gogol.Storage (Devstorage'FullControl)
import Gogol.Storage qualified as GcsApi
import Network.HTTP.Client (RequestBody (RequestBodyLBS))
import Network.HTTP.Media qualified as Media
import Network.HTTP.Types (Status (statusCode))
import Resilience.Retry (RetryPolicyConfig, defaultRetryPolicyConfig, withRetry)

data GcsContext = GcsContext
  { retryPolicyConfig :: RetryPolicyConfig
  }
  deriving stock (Eq, Show)

data GcsObjectRef = GcsObjectRef
  { bucket :: Text
  , objectPath :: Text
  }
  deriving stock (Eq, Show)

type GcsMetadata = HashMap Text Text

data GcsError
  = InvalidGsUri Text
  | BucketMissing Text
  | ObjectPathMissing Text
  | InvalidContentType Text
  | PermissionDenied Text
  | NotFound Text
  | TransportError Text
  | DecodeError Text
  | UnexpectedError Int Text
  deriving stock (Eq, Show)

type GcsScopes = '[Devstorage'FullControl]

defaultGcsContext :: GcsContext
defaultGcsContext =
  GcsContext
    { retryPolicyConfig = defaultRetryPolicyConfig
    }

parseGsUri :: Text -> Either GcsError GcsObjectRef
parseGsUri uri =
  maybe
    (Left (InvalidGsUri uri))
    (uncurry (mkGcsObjectRef uri) . second normalizeObjectPath . Text.breakOn "/")
    (Text.stripPrefix "gs://" uri)

downloadObject :: GcsContext -> GcsObjectRef -> IO (Either GcsError ByteString)
downloadObject context ref =
  withRetry context.retryPolicyConfig isRetryableGcsError (downloadObjectOnce ref)

uploadObject ::
  GcsContext ->
  GcsObjectRef ->
  Text ->
  ByteString ->
  IO (Either GcsError ())
uploadObject context ref contentType =
  uploadObjectWithMetadata context ref contentType HashMap.empty

uploadObjectWithMetadata ::
  GcsContext ->
  GcsObjectRef ->
  Text ->
  GcsMetadata ->
  ByteString ->
  IO (Either GcsError ())
uploadObjectWithMetadata context ref contentType metadata body =
  withRetry context.retryPolicyConfig isRetryableGcsError (uploadObjectOnce ref contentType metadata body)

mkGcsObjectRef :: Text -> Text -> Text -> Either GcsError GcsObjectRef
mkGcsObjectRef uri bucketName path
  | Text.null bucketName = Left (BucketMissing uri)
  | Text.null path = Left (ObjectPathMissing uri)
  | otherwise = Right GcsObjectRef{bucket = bucketName, objectPath = path}

normalizeObjectPath :: Text -> Text
normalizeObjectPath =
  Text.dropWhile (== '/')

newGcsEnv :: IO (Gogol.Env GcsScopes)
newGcsEnv =
  Gogol.newEnv @GcsScopes

downloadObjectOnce :: GcsObjectRef -> IO (Either GcsError ByteString)
downloadObjectOnce ref =
  newGcsEnv
    >>= \environment ->
      first toGcsError
        <$> Gogol.runResourceT
          (Gogol.downloadEither environment (downloadRequest ref) >>= traverse Gogol.sinkLBS)

uploadObjectOnce :: GcsObjectRef -> Text -> GcsMetadata -> ByteString -> IO (Either GcsError ())
uploadObjectOnce ref contentType metadata body =
  either
    (pure . Left)
    (uploadParsedBody ref contentType metadata)
    (mkGBody contentType body)

uploadParsedBody :: GcsObjectRef -> Text -> GcsMetadata -> Gogol.GBody -> IO (Either GcsError ())
uploadParsedBody ref contentType metadata body =
  newGcsEnv
    >>= \environment ->
      (first toGcsError . void)
        <$> Gogol.runResourceT
          (Gogol.uploadEither environment (uploadRequest ref contentType metadata) body)

downloadRequest :: GcsObjectRef -> GcsApi.StorageObjectsGet
downloadRequest ref =
  GcsApi.newStorageObjectsGet ref.bucket ref.objectPath

uploadRequest :: GcsObjectRef -> Text -> GcsMetadata -> GcsApi.StorageObjectsInsert
uploadRequest ref contentType metadata =
  GcsApi.newStorageObjectsInsert ref.bucket (objectPayload ref contentType metadata)

objectPayload :: GcsObjectRef -> Text -> GcsMetadata -> GcsApi.Object
objectPayload ref contentType metadata =
  GcsApi.newObject
    { GcsApi.bucket = Just ref.bucket
    , GcsApi.contentType = Just contentType
    , GcsApi.metadata = mkObjectMetadata metadata
    , GcsApi.name = Just ref.objectPath
    }

mkObjectMetadata :: GcsMetadata -> Maybe GcsApi.Object_Metadata
mkObjectMetadata metadata
  | HashMap.null metadata = Nothing
  | otherwise = Just (GcsApi.newObject_Metadata metadata)

mkGBody :: Text -> ByteString -> Either GcsError Gogol.GBody
mkGBody contentType body =
  maybe
    (Left (InvalidContentType contentType))
    (Right . (`Gogol.GBody` RequestBodyLBS body))
    (Media.parseAccept (Text.encodeUtf8 contentType))

toGcsError :: Gogol.Error -> GcsError
toGcsError (Gogol.TransportError exception) =
  TransportError (Text.pack (show exception))
toGcsError (Gogol.SerializeError serializeError) =
  DecodeError (Text.pack (Gogol._serializeMessage serializeError))
toGcsError (Gogol.ServiceError serviceError) =
  serviceErrorToGcsError
    (statusCode (Gogol._serviceStatus serviceError))
    (Text.pack (show (Gogol._serviceBody serviceError)))

serviceErrorToGcsError :: Int -> Text -> GcsError
serviceErrorToGcsError 403 _ =
  PermissionDenied "GCS access denied"
serviceErrorToGcsError 404 body =
  NotFound body
serviceErrorToGcsError status body =
  UnexpectedError status body

isRetryableGcsError :: GcsError -> Bool
isRetryableGcsError (TransportError _) =
  True
isRetryableGcsError (UnexpectedError status _) =
  isRetryableStatus status
isRetryableGcsError _ =
  False

isRetryableStatus :: Int -> Bool
isRetryableStatus status =
  status == 408 || status == 429 || status >= 500
