module Infrastructure.Repository.FirestoreInsightRepository (
  FirestoreInsightRepositoryEnv (..),
  InsightQueryFilter (..),
  InsightStatusUpdate (..),
  listInsightRecords,
  getInsightRecordByIdentifier,
  updateInsightStatus,
)
where

import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.Insight.Record (
  InsightDetail (..),
  InsightSentiment (..),
  InsightSignalClass (..),
  InsightSourceType (..),
  InsightSummary (..),
 )
import Gogol.FireStore qualified as GogolFireStore
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext (..),
  FirestoreError,
  FromFirestore (..),
  QueryOrder (..),
  SortDirection (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  requireField,
 )
import Persistence.Firestore qualified as Firestore

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- | Environment for reading the @insight_records@ Firestore collection.
newtype FirestoreInsightRepositoryEnv = FirestoreInsightRepositoryEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Query filter
-- ---------------------------------------------------------------------------

-- | Optional filters for the insight record list query.
data InsightQueryFilter = InsightQueryFilter
  { symbolFilter :: Maybe Text
  -- ^ Filter by symbol (MVP: not applied at Firestore level).
  , limitCount :: Int
  -- ^ Maximum number of results.
  }

-- ---------------------------------------------------------------------------
-- FromFirestore instances
-- ---------------------------------------------------------------------------

instance FromFirestore InsightSummary where
  fromFirestoreFields fieldMap = do
    identifierValue <- requireField "identifier" fieldMap
    sourceTypeText <- requireField "sourceType" fieldMap
    sourceTypeValue <- parseInsightSourceType sourceTypeText
    summaryValue <- requireField "summary" fieldMap
    sourceUrlValue <- requireField "sourceUrl" fieldMap
    collectedAtValue <- requireField "collectedAt" fieldMap
    signalClassText <- requireField "signalClass" fieldMap
    signalClassValue <- parseInsightSignalClass signalClassText
    soWhatScoreValue <- requireDoubleField "soWhatScore" fieldMap
    skillVersionValue <- requireField "skillVersion" fieldMap
    pure
      InsightSummary
        { identifier = identifierValue
        , sourceType = sourceTypeValue
        , summary = summaryValue
        , sourceUrl = sourceUrlValue
        , collectedAt = collectedAtValue
        , signalClass = signalClassValue
        , soWhatScore = soWhatScoreValue
        , skillVersion = skillVersionValue
        }

instance FromFirestore InsightDetail where
  fromFirestoreFields fieldMap = do
    identifierValue <- requireField "identifier" fieldMap
    sourceTypeText <- requireField "sourceType" fieldMap
    sourceTypeValue <- parseInsightSourceType sourceTypeText
    summaryValue <- requireField "summary" fieldMap
    sourceUrlValue <- requireField "sourceUrl" fieldMap
    collectedAtValue <- requireField "collectedAt" fieldMap
    signalClassText <- requireField "signalClass" fieldMap
    signalClassValue <- parseInsightSignalClass signalClassText
    soWhatScoreValue <- requireDoubleField "soWhatScore" fieldMap
    skillVersionValue <- requireField "skillVersion" fieldMap
    evidenceSnippetValue <- requireField "evidenceSnippet" fieldMap
    themeValue <- requireField "theme" fieldMap
    maybeSentimentText <- requireField "sentiment" fieldMap
    sentimentValue <- case maybeSentimentText of
      Nothing -> pure Nothing
      Just sentimentText -> fmap Just (parseInsightSentiment sentimentText)
    traceValue <- requireField "trace" fieldMap
    pure
      InsightDetail
        { identifier = identifierValue
        , sourceType = sourceTypeValue
        , summary = summaryValue
        , sourceUrl = sourceUrlValue
        , collectedAt = collectedAtValue
        , signalClass = signalClassValue
        , soWhatScore = soWhatScoreValue
        , skillVersion = skillVersionValue
        , evidenceSnippet = evidenceSnippetValue
        , theme = themeValue
        , sentiment = sentimentValue
        , trace = traceValue
        }

-- ---------------------------------------------------------------------------
-- Repository operations
-- ---------------------------------------------------------------------------

{- | List insight records ordered by @collectedAt DESC@.

MVP: no Firestore-level symbol filter; returns all records up to limit.
-}
listInsightRecords ::
  FirestoreInsightRepositoryEnv ->
  InsightQueryFilter ->
  IO (Either FirestoreError [InsightSummary])
listInsightRecords insightRepositoryEnv queryFilter = do
  let orders = [QueryOrder{orderField = "collectedAt", orderDirection = Descending}]
      limitValue = max 1 (min 200 queryFilter.limitCount)
  Firestore.runQuery
    insightRepositoryEnv.firestoreContext
    (CollectionName "insight_records")
    []
    orders
    limitValue
    Nothing

{- | Get a single insight record by its identifier.

Returns 'Nothing' if the document does not exist.
-}
getInsightRecordByIdentifier ::
  FirestoreInsightRepositoryEnv ->
  Text ->
  IO (Either FirestoreError (Maybe InsightDetail))
getInsightRecordByIdentifier insightRepositoryEnv insightIdentifier =
  Firestore.getDocument
    insightRepositoryEnv.firestoreContext
    (CollectionName "insight_records")
    (DocumentId insightIdentifier)

-- ---------------------------------------------------------------------------
-- Status update
-- ---------------------------------------------------------------------------

-- | Payload for updating an insight record's action status in Firestore.
data InsightStatusUpdate = InsightStatusUpdate
  { actionStatus :: Text
  -- ^ One of @"adopted"@, @"rejected"@, or @"hypothesized"@.
  , updatedAt :: UTCTime
  }

instance ToFirestore InsightStatusUpdate where
  toFirestoreFields statusUpdate =
    HashMap.fromList
      [ ("actionStatus", toValue statusUpdate.actionStatus)
      , ("updatedAt", toValue statusUpdate.updatedAt)
      ]

{- | Overwrite the @actionStatus@ and @updatedAt@ fields of an insight record.

Uses 'Firestore.upsertDocument' (PATCH semantics — merges on the server side).
-}
updateInsightStatus ::
  FirestoreInsightRepositoryEnv ->
  -- | Insight identifier (ULID).
  Text ->
  InsightStatusUpdate ->
  IO (Either FirestoreError ())
updateInsightStatus insightRepositoryEnv insightIdentifier statusUpdate =
  Firestore.upsertDocument
    insightRepositoryEnv.firestoreContext
    (CollectionName "insight_records")
    (DocumentId insightIdentifier)
    statusUpdate

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

requireDoubleField :: Text -> HashMap Text GogolFireStore.Value -> Either Text Double
requireDoubleField key fields =
  case HashMap.lookup key fields of
    Nothing -> Left ("missing field: " <> key)
    Just value ->
      case value.doubleValue of
        Just d -> Right d
        Nothing ->
          case value.integerValue of
            Just i -> Right (fromIntegral i)
            Nothing -> Left ("field " <> key <> " is not a number")

parseInsightSourceType :: Text -> Either Text InsightSourceType
parseInsightSourceType "x" = Right InsightSourceTypeX
parseInsightSourceType "youtube" = Right InsightSourceTypeYouTube
parseInsightSourceType "paper" = Right InsightSourceTypePaper
parseInsightSourceType "github" = Right InsightSourceTypeGitHub
parseInsightSourceType unknown = Left ("Unknown insight source type: " <> unknown)

parseInsightSignalClass :: Text -> Either Text InsightSignalClass
parseInsightSignalClass "structural_anomaly" = Right InsightSignalClassStructuralAnomaly
parseInsightSignalClass "event_noise" = Right InsightSignalClassEventNoise
parseInsightSignalClass unknown = Left ("Unknown insight signal class: " <> unknown)

parseInsightSentiment :: Text -> Either Text InsightSentiment
parseInsightSentiment "positive" = Right InsightSentimentPositive
parseInsightSentiment "neutral" = Right InsightSentimentNeutral
parseInsightSentiment "negative" = Right InsightSentimentNegative
parseInsightSentiment unknown = Left ("Unknown insight sentiment: " <> unknown)
