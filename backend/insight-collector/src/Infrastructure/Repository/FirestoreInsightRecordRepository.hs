{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'InsightRecordRepository'.

Must-INFRA-001: FirestoreInsightRecordRepositoryT newtype wrapping ReaderT.
Must-INFRA-002: persistRecord upserts to insight_records collection; documentId = identifier.value (ULID string).
Must-INFRA-003: searchRecords queries by sourceType filter.
Must-INFRA-004: findByTargetDate returns all records for a given date (via collectedAtDate indexed field).
Must-INFRA-005: TTL expiresAt = collectedAt + 365 days (Firestore TTL field).
Must-INFRA-006: isRetryableForPersist — FirestoreErrorTransport and 429/5xx are retryable.
-}
module Infrastructure.Repository.FirestoreInsightRecordRepository (
  -- * Environment
  FirestoreInsightRecordEnv (..),

  -- * Monad transformer
  FirestoreInsightRecordRepositoryT (..),
  runFirestoreInsightRecordRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Codec (exported for pure round-trip tests)
  InsightRecordDocument (..),
  toDocument,
  documentToRecord,

  -- * Accessors (exported for tests to avoid DuplicateRecordFields ambiguity)
  insightRecordDocumentExpiresAt,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict qualified as HashMap
import Data.Int (Int64)
import Data.Maybe (mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, addUTCTime, nominalDay)
import Data.Time.Format (defaultTimeLocale, formatTime)
import Data.ULID (ULID)
import Domain.InsightCollection.Aggregate (
  InsightRecord (..),
  InsightRecordIdentifier (..),
  InsightRecordRepository (..),
  SignalClass (..),
  SourceType (..),
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FirestoreError (..),
  FromFirestore (..),
  QueryFilter (..),
  QueryOrder (..),
  SortDirection (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  requireField,
  runQuery,
  upsertDocument,
 )
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreInsightRecordEnv = FirestoreInsightRecordEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreInsightRecordRepositoryT m a = FirestoreInsightRecordRepositoryT
  { unFirestoreInsightRecordRepositoryT :: ReaderT FirestoreInsightRecordEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runFirestoreInsightRecordRepositoryT ::
  FirestoreInsightRecordEnv ->
  FirestoreInsightRecordRepositoryT m a ->
  m a
runFirestoreInsightRecordRepositoryT environment action =
  runReaderT (unFirestoreInsightRecordRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

insightRecordsCollection :: CollectionName
insightRecordsCollection = CollectionName "insight_records"

-- ---------------------------------------------------------------------------
-- Retry predicate
-- ---------------------------------------------------------------------------

-- | Must-INFRA-006: Transport errors and HTTP 429/5xx are retryable.
isRetryableForPersist :: FirestoreError -> Bool
isRetryableForPersist (FirestoreErrorTransport _) = True
isRetryableForPersist (FirestoreErrorUnexpected statusCode _) = statusCode == 429 || statusCode >= 500
isRetryableForPersist _ = False

-- ---------------------------------------------------------------------------
-- Firestore document codec
-- ---------------------------------------------------------------------------

data InsightRecordDocument = InsightRecordDocument
  { identifier :: ULID
  , sourceType :: Text
  , sourceUrl :: Text
  , evidenceSnippet :: Text
  , collectedAt :: UTCTime
  , collectedAtDate :: Text
  , summary :: Text
  , signalClass :: Text
  , soWhatScore :: Int64
  , skillVersion :: Text
  , expiresAt :: UTCTime
  }

instance ToFirestore InsightRecordDocument where
  toFirestoreFields document =
    HashMap.fromList
      [ ("identifier", toValue document.identifier)
      , ("sourceType", toValue document.sourceType)
      , ("sourceUrl", toValue document.sourceUrl)
      , ("evidenceSnippet", toValue document.evidenceSnippet)
      , ("collectedAt", toValue document.collectedAt)
      , ("collectedAtDate", toValue document.collectedAtDate)
      , ("summary", toValue document.summary)
      , ("signalClass", toValue document.signalClass)
      , ("soWhatScore", toValue document.soWhatScore)
      , ("skillVersion", toValue document.skillVersion)
      , ("expiresAt", toValue document.expiresAt)
      ]

instance FromFirestore InsightRecordDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    sourceTypeValue <- requireField "sourceType" fields
    sourceUrlValue <- requireField "sourceUrl" fields
    evidenceSnippetValue <- requireField "evidenceSnippet" fields
    collectedAtValue <- requireField "collectedAt" fields
    collectedAtDateValue <- requireField "collectedAtDate" fields
    summaryValue <- requireField "summary" fields
    signalClassValue <- requireField "signalClass" fields
    soWhatScoreRaw <- requireField "soWhatScore" fields
    skillVersionValue <- requireField "skillVersion" fields
    expiresAtValue <- requireField "expiresAt" fields
    Right
      InsightRecordDocument
        { identifier = identifierValue
        , sourceType = sourceTypeValue
        , sourceUrl = sourceUrlValue
        , evidenceSnippet = evidenceSnippetValue
        , collectedAt = collectedAtValue
        , collectedAtDate = collectedAtDateValue
        , summary = summaryValue
        , signalClass = signalClassValue
        , soWhatScore = soWhatScoreRaw
        , skillVersion = skillVersionValue
        , expiresAt = expiresAtValue
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

signalClassToText :: SignalClass -> Text
signalClassToText StructuralAnomaly = "structural_anomaly"
signalClassToText EventNoise = "event_noise"

signalClassFromText :: Text -> Either Text SignalClass
signalClassFromText "structural_anomaly" = Right StructuralAnomaly
signalClassFromText "event_noise" = Right EventNoise
signalClassFromText other = Left ("unknown signalClass: " <> other)

-- | Must-INFRA-005: expiresAt = collectedAt + 365 days. collectedAtDate for indexed date queries.
toDocument :: InsightRecord -> InsightRecordDocument
toDocument record =
  InsightRecordDocument
    { identifier = record.identifier.value
    , sourceType = sourceTypeToText record.sourceType
    , sourceUrl = record.sourceUrl
    , evidenceSnippet = record.evidenceSnippet
    , collectedAt = record.collectedAt
    , collectedAtDate = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" record.collectedAt)
    , summary = record.summary
    , signalClass = signalClassToText record.signalClass
    , soWhatScore = round (record.soWhatScore * 10000)
    , skillVersion = record.skillVersion
    , expiresAt = addUTCTime (365 * nominalDay) record.collectedAt
    }

documentToRecord :: InsightRecordDocument -> Either Text InsightRecord
documentToRecord document = do
  sourceTypeValue <- sourceTypeFromText document.sourceType
  signalClassValue <- signalClassFromText document.signalClass
  Right
    InsightRecord
      { identifier = InsightRecordIdentifier{value = document.identifier}
      , sourceType = sourceTypeValue
      , sourceUrl = document.sourceUrl
      , evidenceSnippet = document.evidenceSnippet
      , collectedAt = document.collectedAt
      , summary = document.summary
      , signalClass = signalClassValue
      , soWhatScore = fromIntegral document.soWhatScore / 10000.0
      , skillVersion = document.skillVersion
      }

-- | Unambiguous accessor for 'expiresAt' field (for tests with DuplicateRecordFields).
insightRecordDocumentExpiresAt :: InsightRecordDocument -> UTCTime
insightRecordDocumentExpiresAt document = document.expiresAt

-- ---------------------------------------------------------------------------
-- Port implementation
-- ---------------------------------------------------------------------------

instance InsightRecordRepository (FirestoreInsightRecordRepositoryT IO) where
  persistRecord record = FirestoreInsightRecordRepositoryT $ do
    environment <- ask
    liftIO $ do
      let document = toDocument record
          documentIdentifier = DocumentId (Text.pack (show record.identifier.value))
      result <-
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext insightRecordsCollection documentIdentifier document
      case result of
        Left firestoreError -> fail ("persistRecord failed: " <> show firestoreError)
        Right () -> pure ()

  searchRecords targetDate sourceTypes = FirestoreInsightRecordRepositoryT $ do
    environment <- ask
    let dateText = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" targetDate)
        sourceTypeFilters =
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
          QueryFilterEqual{filterField = "collectedAtDate", filterValue = toValue dateText}
            : sourceTypeFilters
        orders = [QueryOrder{orderField = "collectedAt", orderDirection = Descending}]
    result <-
      liftIO $
        runQuery @InsightRecordDocument
          environment.firestoreContext
          insightRecordsCollection
          filters
          orders
          200
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (mapMaybe (either (const Nothing) Just . documentToRecord) documents)

  findByTargetDate targetDate = FirestoreInsightRecordRepositoryT $ do
    environment <- ask
    let dateText = Text.pack (formatTime defaultTimeLocale "%Y-%m-%d" targetDate)
        filters = [QueryFilterEqual{filterField = "collectedAtDate", filterValue = toValue dateText}]
        orders = [QueryOrder{orderField = "collectedAt", orderDirection = Descending}]
    result <-
      liftIO $
        runQuery @InsightRecordDocument
          environment.firestoreContext
          insightRecordsCollection
          filters
          orders
          200
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (mapMaybe (either (const Nothing) Just . documentToRecord) documents)
