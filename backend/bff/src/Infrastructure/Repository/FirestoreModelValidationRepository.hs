module Infrastructure.Repository.FirestoreModelValidationRepository (
  FirestoreModelValidationRepositoryEnv (..),
  ModelValidationQueryFilter (..),
  listModelValidations,
  getModelValidationByVersion,
)
where

import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Domain.ModelValidation.Record (
  DegradationFlag (..),
  ModelMetrics (..),
  ModelValidationDetail (..),
  ModelValidationStatus (..),
  ModelValidationSummary (..),
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
  requireField,
 )
import Persistence.Firestore qualified as Firestore

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- | Environment for reading the @model_registry@ Firestore collection.
newtype FirestoreModelValidationRepositoryEnv = FirestoreModelValidationRepositoryEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Query filter
-- ---------------------------------------------------------------------------

-- | Optional filters for the model validation list query.
data ModelValidationQueryFilter = ModelValidationQueryFilter
  { statusFilter :: Maybe Text
  -- ^ Filter by status (MVP: not applied at Firestore level).
  , limitCount :: Int
  -- ^ Maximum number of results.
  }

-- ---------------------------------------------------------------------------
-- FromFirestore instances
-- ---------------------------------------------------------------------------

instance FromFirestore ModelValidationSummary where
  fromFirestoreFields fieldMap = do
    modelVersionValue <- requireField "modelVersion" fieldMap
    statusText <- requireField "status" fieldMap
    statusValue <- parseModelValidationStatus statusText
    degradationFlagText <- requireField "degradationFlag" fieldMap
    degradationFlagValue <- parseDegradationFlag degradationFlagText
    createdAtValue <- requireField "createdAt" fieldMap
    pure
      ModelValidationSummary
        { modelVersion = modelVersionValue
        , status = statusValue
        , degradationFlag = degradationFlagValue
        , createdAt = createdAtValue
        }

instance FromFirestore ModelValidationDetail where
  fromFirestoreFields fieldMap = do
    modelVersionValue <- requireField "modelVersion" fieldMap
    statusText <- requireField "status" fieldMap
    statusValue <- parseModelValidationStatus statusText
    degradationFlagText <- requireField "degradationFlag" fieldMap
    degradationFlagValue <- parseDegradationFlag degradationFlagText
    createdAtValue <- requireField "createdAt" fieldMap
    metricsValue <- parseModelMetrics fieldMap
    requiresComplianceReviewValue <- requireField "requiresComplianceReview" fieldMap
    pure
      ModelValidationDetail
        { modelVersion = modelVersionValue
        , status = statusValue
        , degradationFlag = degradationFlagValue
        , createdAt = createdAtValue
        , metrics = metricsValue
        , requiresComplianceReview = requiresComplianceReviewValue
        }

-- ---------------------------------------------------------------------------
-- Repository operations
-- ---------------------------------------------------------------------------

{- | List model validations ordered by @createdAt DESC@.

MVP: no Firestore-level status filter; returns all entries up to limit.
-}
listModelValidations ::
  FirestoreModelValidationRepositoryEnv ->
  ModelValidationQueryFilter ->
  IO (Either FirestoreError [ModelValidationSummary])
listModelValidations modelValidationRepositoryEnv queryFilter = do
  let orders = [QueryOrder{orderField = "createdAt", orderDirection = Descending}]
      limitValue = max 1 (min 200 queryFilter.limitCount)
  Firestore.runQuery
    modelValidationRepositoryEnv.firestoreContext
    (CollectionName "model_registry")
    []
    orders
    limitValue
    Nothing

{- | Get a single model validation entry by its modelVersion (document ID).

Returns 'Nothing' if the document does not exist.
-}
getModelValidationByVersion ::
  FirestoreModelValidationRepositoryEnv ->
  Text ->
  IO (Either FirestoreError (Maybe ModelValidationDetail))
getModelValidationByVersion modelValidationRepositoryEnv modelVersionText =
  Firestore.getDocument
    modelValidationRepositoryEnv.firestoreContext
    (CollectionName "model_registry")
    (DocumentId modelVersionText)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

parseModelValidationStatus :: Text -> Either Text ModelValidationStatus
parseModelValidationStatus "candidate" = Right ModelValidationStatusCandidate
parseModelValidationStatus "approved" = Right ModelValidationStatusApproved
parseModelValidationStatus "rejected" = Right ModelValidationStatusRejected
parseModelValidationStatus unknown = Left ("Unknown model validation status: " <> unknown)

parseDegradationFlag :: Text -> Either Text DegradationFlag
parseDegradationFlag "normal" = Right DegradationFlagNormal
parseDegradationFlag "warn" = Right DegradationFlagWarn
parseDegradationFlag "block" = Right DegradationFlagBlock
parseDegradationFlag unknown = Left ("Unknown degradation flag: " <> unknown)

parseModelMetrics ::
  HashMap Text GogolFireStore.Value ->
  Either Text ModelMetrics
parseModelMetrics fieldMap = do
  oosReturnValue <- requireDoubleField "oosReturn" fieldMap
  sharpeValue <- requireDoubleField "sharpe" fieldMap
  maxDrawdownValue <- requireDoubleField "maxDrawdown" fieldMap
  turnoverValue <- requireDoubleField "turnover" fieldMap
  pboValue <- requireDoubleField "pbo" fieldMap
  dsrValue <- requireDoubleField "dsr" fieldMap
  costAdjustedReturnValue <- requireDoubleField "costAdjustedReturn" fieldMap
  slippageAdjustedSharpeValue <- requireDoubleField "slippageAdjustedSharpe" fieldMap
  pure
    ModelMetrics
      { oosReturn = oosReturnValue
      , sharpe = sharpeValue
      , maxDrawdown = maxDrawdownValue
      , turnover = turnoverValue
      , pbo = pboValue
      , dsr = dsrValue
      , costAdjustedReturn = costAdjustedReturnValue
      , slippageAdjustedSharpe = slippageAdjustedSharpeValue
      }

requireDoubleField ::
  Text ->
  HashMap Text GogolFireStore.Value ->
  Either Text Double
requireDoubleField key fields =
  case HashMap.lookup key fields of
    Nothing -> Left ("Missing required field: " <> key)
    Just value ->
      case value.doubleValue of
        Just d -> Right d
        Nothing ->
          case value.integerValue of
            Just i -> Right (fromIntegral i)
            Nothing -> Left ("Field " <> key <> " is not a number")
