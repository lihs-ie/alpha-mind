{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'SourcePolicyRepository'.

Must-INFRA-007: FirestoreSourcePolicyRepositoryT newtype wrapping ReaderT.
Must-INFRA-008: searchPolicies queries source_policies by sourceType + enabled filters; up to 5 results.
Must-INFRA-009: findBySourceType returns a single SourcePolicySnapshot for the given sourceType.
Must-INFRA-010: isRetryableForRead — FirestoreErrorTransport and 429/5xx are retryable.
-}
module Infrastructure.Repository.FirestoreSourcePolicyRepository (
  -- * Environment
  FirestoreSourcePolicyEnv (..),

  -- * Monad transformer
  FirestoreSourcePolicyRepositoryT (..),
  runFirestoreSourcePolicyRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForRead,

  -- * Codec (exported for pure round-trip tests)
  SourcePolicyDocument (..),
  documentToPolicy,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as Aeson
import Data.Int (Int64)
import Data.Maybe (listToMaybe, mapMaybe)
import Data.Text (Text)
import Data.ULID (ULID)
import Domain.InsightCollection.Aggregate (
  GitHubConfig (..),
  PaperConfig (..),
  SourceConfig (..),
  SourcePolicyRepository (..),
  SourcePolicySnapshot (..),
  SourceType (..),
  XConfig (..),
  YouTubeConfig (..),
 )
import Persistence.Firestore (
  CollectionName (..),
  FirestoreContext,
  FirestoreError (..),
  FromFirestore (..),
  QueryFilter (..),
  QueryOrder (..),
  SortDirection (..),
  ToFirestoreValue (..),
  requireField,
  runQuery,
 )

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreSourcePolicyEnv = FirestoreSourcePolicyEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreSourcePolicyRepositoryT m a = FirestoreSourcePolicyRepositoryT
  { unFirestoreSourcePolicyRepositoryT :: ReaderT FirestoreSourcePolicyEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreSourcePolicyRepositoryT ::
  FirestoreSourcePolicyEnv ->
  FirestoreSourcePolicyRepositoryT m a ->
  m a
runFirestoreSourcePolicyRepositoryT environment action =
  runReaderT (unFirestoreSourcePolicyRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

sourcePoliciesCollection :: CollectionName
sourcePoliciesCollection = CollectionName "source_policies"

-- ---------------------------------------------------------------------------
-- Retry predicate
-- ---------------------------------------------------------------------------

-- | Must-INFRA-010: Transport errors and HTTP 429/5xx are retryable.
isRetryableForRead :: FirestoreError -> Bool
isRetryableForRead (FirestoreErrorTransport _) = True
isRetryableForRead (FirestoreErrorUnexpected statusCode _) = statusCode == 429 || statusCode >= 500
isRetryableForRead _ = False

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

-- | Firestore representation of a source policy document.
data SourcePolicyDocument = SourcePolicyDocument
  { identifier :: ULID
  , sourceType :: Text
  , enabled :: Bool
  , termsVersion :: Text
  , redistributionAllowed :: Bool
  , dailyQuota :: Maybe Int64
  , sourceConfigText :: Text
  }

instance FromFirestore SourcePolicyDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    sourceTypeValue <- requireField "sourceType" fields
    enabledValue <- requireField "enabled" fields
    termsVersionValue <- requireField "termsVersion" fields
    redistributionAllowedValue <- requireField "redistributionAllowed" fields
    dailyQuotaValue <- requireField "dailyQuota" fields
    sourceConfigTextValue <- requireField "sourceConfig" fields
    Right
      SourcePolicyDocument
        { identifier = identifierValue
        , sourceType = sourceTypeValue
        , enabled = enabledValue
        , termsVersion = termsVersionValue
        , redistributionAllowed = redistributionAllowedValue
        , dailyQuota = dailyQuotaValue
        , sourceConfigText = sourceConfigTextValue
        }

-- ---------------------------------------------------------------------------
-- Codec helpers
-- ---------------------------------------------------------------------------

sourceTypeToText :: SourceType -> Text
sourceTypeToText X = "x"
sourceTypeToText YouTube = "youtube"
sourceTypeToText Paper = "paper"
sourceTypeToText GitHub = "github"

sourceTypeFromText :: Text -> Either Text SourceType
sourceTypeFromText "x" = Right X
sourceTypeFromText "youtube" = Right YouTube
sourceTypeFromText "paper" = Right Paper
sourceTypeFromText "github" = Right GitHub
sourceTypeFromText other = Left ("unknown sourceType: " <> other)

{- | Parse SourceConfig from JSON text stored in Firestore.
The sourceConfig field is a JSON-encoded map keyed by source type name.
-}
parseSourceConfig :: SourceType -> Text -> Either Text SourceConfig
parseSourceConfig sourceType jsonText =
  case Aeson.decodeStrictText jsonText of
    Nothing -> Left ("failed to decode sourceConfig JSON: " <> jsonText)
    Just (Aeson.Object obj) -> parseSourceConfigObject sourceType obj
    Just _ -> Left "sourceConfig must be a JSON object"

parseSourceConfigObject :: SourceType -> Aeson.KeyMap Aeson.Value -> Either Text SourceConfig
parseSourceConfigObject X obj =
  case Aeson.lookup "x" obj of
    Nothing -> Left "missing 'x' key in sourceConfig"
    Just (Aeson.Object xObj) ->
      case Aeson.lookup "bearerTokenSecretName" xObj of
        Just (Aeson.String secretName) ->
          Right (XSourceConfig (XConfig{bearerTokenSecretName = secretName}))
        _ -> Left "missing or invalid bearerTokenSecretName in x config"
    Just _ -> Left "sourceConfig.x must be a JSON object"
parseSourceConfigObject YouTube obj =
  case Aeson.lookup "youtube" obj of
    Nothing -> Left "missing 'youtube' key in sourceConfig"
    Just (Aeson.Object youtubeObj) ->
      case Aeson.lookup "apiKeySecretName" youtubeObj of
        Just (Aeson.String secretName) ->
          Right (YouTubeSourceConfig (YouTubeConfig{apiKeySecretName = secretName}))
        _ -> Left "missing or invalid apiKeySecretName in youtube config"
    Just _ -> Left "sourceConfig.youtube must be a JSON object"
parseSourceConfigObject Paper obj =
  case Aeson.lookup "paper" obj of
    Nothing -> Left "missing 'paper' key in sourceConfig"
    Just (Aeson.Object paperObj) ->
      case Aeson.lookup "baseUrl" paperObj of
        Just (Aeson.String urlValue) ->
          Right (PaperSourceConfig (PaperConfig{baseUrl = urlValue}))
        _ -> Left "missing or invalid baseUrl in paper config"
    Just _ -> Left "sourceConfig.paper must be a JSON object"
parseSourceConfigObject GitHub obj =
  case Aeson.lookup "github" obj of
    Nothing -> Left "missing 'github' key in sourceConfig"
    Just (Aeson.Object githubObj) ->
      case Aeson.lookup "personalAccessTokenSecretName" githubObj of
        Just (Aeson.String secretName) ->
          Right (GitHubSourceConfig (GitHubConfig{personalAccessTokenSecretName = secretName}))
        _ -> Left "missing or invalid personalAccessTokenSecretName in github config"
    Just _ -> Left "sourceConfig.github must be a JSON object"

documentToPolicy :: SourcePolicyDocument -> Either Text SourcePolicySnapshot
documentToPolicy document = do
  sourceTypeValue <- sourceTypeFromText document.sourceType
  sourceConfigValue <- parseSourceConfig sourceTypeValue document.sourceConfigText
  Right
    SourcePolicySnapshot
      { sourceType = sourceTypeValue
      , enabled = document.enabled
      , termsVersion = document.termsVersion
      , redistributionAllowed = document.redistributionAllowed
      , dailyQuota = fmap fromIntegral document.dailyQuota
      , sourceConfig = sourceConfigValue
      }

-- ---------------------------------------------------------------------------
-- Port implementation
-- ---------------------------------------------------------------------------

instance SourcePolicyRepository (FirestoreSourcePolicyRepositoryT IO) where
  searchPolicies sourceTypes = FirestoreSourcePolicyRepositoryT $ do
    environment <- ask
    let sourceTypeFilters =
          mapMaybe
            ( \st ->
                Just
                  QueryFilterEqual
                    { filterField = "sourceType"
                    , filterValue = toValue (sourceTypeToText st)
                    }
            )
            (take 1 sourceTypes)
        filters =
          QueryFilterEqual{filterField = "enabled", filterValue = toValue True}
            : sourceTypeFilters
        orders = [QueryOrder{orderField = "sourceType", orderDirection = Ascending}]
    result <-
      liftIO $
        runQuery @SourcePolicyDocument
          environment.firestoreContext
          sourcePoliciesCollection
          filters
          orders
          5
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (mapMaybe (either (const Nothing) Just . documentToPolicy) documents)

  findBySourceType sourceType = FirestoreSourcePolicyRepositoryT $ do
    environment <- ask
    let filters =
          [ QueryFilterEqual{filterField = "sourceType", filterValue = toValue (sourceTypeToText sourceType)}
          , QueryFilterEqual{filterField = "enabled", filterValue = toValue True}
          ]
        orders = [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
    result <-
      liftIO $
        runQuery @SourcePolicyDocument
          environment.firestoreContext
          sourcePoliciesCollection
          filters
          orders
          1
          Nothing
    case result of
      Left _ -> pure Nothing
      Right documents ->
        pure $
          listToMaybe $
            mapMaybe (either (const Nothing) Just . documentToPolicy) documents
