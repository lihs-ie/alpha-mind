module Infrastructure.Repository.FirestoreHypothesisRepository (
  FirestoreHypothesisRepositoryEnv (..),
  HypothesisQueryFilter (..),
  HypothesisStatusUpdate (..),
  HypothesisMnpiUpdate (..),
  listHypotheses,
  getHypothesisByIdentifier,
  updateHypothesisStatus,
  updateHypothesisMnpi,
)
where

import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.Hypothesis.Record (
  HypothesisDetail (..),
  HypothesisInsiderRisk (..),
  HypothesisInstrumentType (..),
  HypothesisPromotionMode (..),
  HypothesisStatus (..),
  HypothesisSummary (..),
  hypothesisStatusToText,
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

-- | Environment for reading the @hypothesis_registry@ Firestore collection.
newtype FirestoreHypothesisRepositoryEnv = FirestoreHypothesisRepositoryEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Query filter
-- ---------------------------------------------------------------------------

-- | Optional filters for the hypothesis list query.
data HypothesisQueryFilter = HypothesisQueryFilter
  { statusFilter :: Maybe Text
  -- ^ Filter by status (MVP: not applied at Firestore level).
  , limitCount :: Int
  -- ^ Maximum number of results.
  }

-- ---------------------------------------------------------------------------
-- FromFirestore instances
-- ---------------------------------------------------------------------------

instance FromFirestore HypothesisSummary where
  fromFirestoreFields fieldMap = do
    identifierValue <- requireField "identifier" fieldMap
    symbolValue <- requireField "symbol" fieldMap
    instrumentTypeText <- requireField "instrumentType" fieldMap
    instrumentTypeValue <- parseHypothesisInstrumentType instrumentTypeText
    statusText <- requireField "status" fieldMap
    statusValue <- parseHypothesisStatus statusText
    titleValue <- requireField "title" fieldMap
    updatedAtValue <- requireField "updatedAt" fieldMap
    pure
      HypothesisSummary
        { identifier = identifierValue
        , symbol = symbolValue
        , instrumentType = instrumentTypeValue
        , status = statusValue
        , title = titleValue
        , updatedAt = updatedAtValue
        }

instance FromFirestore HypothesisDetail where
  fromFirestoreFields fieldMap = do
    identifierValue <- requireField "identifier" fieldMap
    symbolValue <- requireField "symbol" fieldMap
    instrumentTypeText <- requireField "instrumentType" fieldMap
    instrumentTypeValue <- parseHypothesisInstrumentType instrumentTypeText
    statusText <- requireField "status" fieldMap
    statusValue <- parseHypothesisStatus statusText
    titleValue <- requireField "title" fieldMap
    updatedAtValue <- requireField "updatedAt" fieldMap
    sourceEvidenceValue <- requireArrayTextField "sourceEvidence" fieldMap
    skillVersionValue <- requireField "skillVersion" fieldMap
    instructionProfileVersionValue <- requireField "instructionProfileVersion" fieldMap
    costAdjustedReturnValue <- optionalDoubleField "costAdjustedReturn" fieldMap
    dsrValue <- optionalDoubleField "dsr" fieldMap
    pboValue <- optionalDoubleField "pbo" fieldMap
    demoPeriodValue <- requireField "demoPeriod" fieldMap
    maybeInsiderRiskText <- requireField "insiderRisk" fieldMap
    insiderRiskValue <- case maybeInsiderRiskText of
      Nothing -> pure Nothing
      Just insiderRiskText -> fmap Just (parseHypothesisInsiderRisk insiderRiskText)
    requiresComplianceReviewValue <- requireField "requiresComplianceReview" fieldMap
    mnpiSelfDeclaredValue <- requireField "mnpiSelfDeclared" fieldMap
    autoPromotionEligibleValue <- requireField "autoPromotionEligible" fieldMap
    maybePromotionModeText <- requireField "promotionMode" fieldMap
    promotionModeValue <- case maybePromotionModeText of
      Nothing -> pure Nothing
      Just promotionModeText -> fmap Just (parseHypothesisPromotionMode promotionModeText)
    latestFailureSummaryValue <- requireField "latestFailureSummary" fieldMap
    pure
      HypothesisDetail
        { identifier = identifierValue
        , symbol = symbolValue
        , instrumentType = instrumentTypeValue
        , status = statusValue
        , title = titleValue
        , updatedAt = updatedAtValue
        , sourceEvidence = sourceEvidenceValue
        , skillVersion = skillVersionValue
        , instructionProfileVersion = instructionProfileVersionValue
        , costAdjustedReturn = costAdjustedReturnValue
        , dsr = dsrValue
        , pbo = pboValue
        , demoPeriod = demoPeriodValue
        , insiderRisk = insiderRiskValue
        , requiresComplianceReview = requiresComplianceReviewValue
        , mnpiSelfDeclared = mnpiSelfDeclaredValue
        , autoPromotionEligible = autoPromotionEligibleValue
        , promotionMode = promotionModeValue
        , latestFailureSummary = latestFailureSummaryValue
        }

-- ---------------------------------------------------------------------------
-- Repository operations
-- ---------------------------------------------------------------------------

{- | List hypotheses ordered by @updatedAt DESC@.

MVP: no Firestore-level status filter; returns all hypotheses up to limit.
-}
listHypotheses ::
  FirestoreHypothesisRepositoryEnv ->
  HypothesisQueryFilter ->
  IO (Either FirestoreError [HypothesisSummary])
listHypotheses hypothesisRepositoryEnv queryFilter = do
  let orders = [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
      limitValue = max 1 (min 200 queryFilter.limitCount)
  Firestore.runQuery
    hypothesisRepositoryEnv.firestoreContext
    (CollectionName "hypothesis_registry")
    []
    orders
    limitValue
    Nothing

{- | Get a single hypothesis by its identifier.

Returns 'Nothing' if the document does not exist.
-}
getHypothesisByIdentifier ::
  FirestoreHypothesisRepositoryEnv ->
  Text ->
  IO (Either FirestoreError (Maybe HypothesisDetail))
getHypothesisByIdentifier hypothesisRepositoryEnv hypothesisIdentifier =
  Firestore.getDocument
    hypothesisRepositoryEnv.firestoreContext
    (CollectionName "hypothesis_registry")
    (DocumentId hypothesisIdentifier)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

requireArrayTextField ::
  Text ->
  HashMap Text GogolFireStore.Value ->
  Either Text [Text]
requireArrayTextField key fields =
  case HashMap.lookup key fields of
    Nothing -> Right []
    Just value ->
      case value.arrayValue of
        Nothing -> Right []
        Just arrayValue ->
          case arrayValue.values of
            Nothing -> Right []
            Just valueList ->
              mapM extractTextValue valueList
 where
  extractTextValue v =
    case v.stringValue of
      Just t -> Right t
      Nothing -> Left ("array element in " <> key <> " is not a string")

optionalDoubleField ::
  Text ->
  HashMap Text GogolFireStore.Value ->
  Either Text (Maybe Double)
optionalDoubleField key fields =
  case HashMap.lookup key fields of
    Nothing -> Right Nothing
    Just value ->
      case value.nullValue of
        Just _ -> Right Nothing
        Nothing ->
          case value.doubleValue of
            Just d -> Right (Just d)
            Nothing ->
              case value.integerValue of
                Just i -> Right (Just (fromIntegral i))
                Nothing -> Left ("field " <> key <> " is not a number")

parseHypothesisStatus :: Text -> Either Text HypothesisStatus
parseHypothesisStatus "draft" = Right HypothesisStatusDraft
parseHypothesisStatus "backtested" = Right HypothesisStatusBacktested
parseHypothesisStatus "demo" = Right HypothesisStatusDemo
parseHypothesisStatus "live" = Right HypothesisStatusLive
parseHypothesisStatus "rejected" = Right HypothesisStatusRejected
parseHypothesisStatus unknown = Left ("Unknown hypothesis status: " <> unknown)

parseHypothesisInstrumentType :: Text -> Either Text HypothesisInstrumentType
parseHypothesisInstrumentType "ETF" = Right HypothesisInstrumentTypeETF
parseHypothesisInstrumentType "STOCK" = Right HypothesisInstrumentTypeStock
parseHypothesisInstrumentType unknown = Left ("Unknown hypothesis instrument type: " <> unknown)

parseHypothesisInsiderRisk :: Text -> Either Text HypothesisInsiderRisk
parseHypothesisInsiderRisk "low" = Right HypothesisInsiderRiskLow
parseHypothesisInsiderRisk "medium" = Right HypothesisInsiderRiskMedium
parseHypothesisInsiderRisk "high" = Right HypothesisInsiderRiskHigh
parseHypothesisInsiderRisk unknown = Left ("Unknown hypothesis insider risk: " <> unknown)

parseHypothesisPromotionMode :: Text -> Either Text HypothesisPromotionMode
parseHypothesisPromotionMode "manual" = Right HypothesisPromotionModeManual
parseHypothesisPromotionMode "auto" = Right HypothesisPromotionModeAuto
parseHypothesisPromotionMode unknown = Left ("Unknown hypothesis promotion mode: " <> unknown)

-- ---------------------------------------------------------------------------
-- Update records
-- ---------------------------------------------------------------------------

-- | Fields to update when promoting or rejecting a hypothesis.
data HypothesisStatusUpdate = HypothesisStatusUpdate
  { newStatus :: HypothesisStatus
  , newPromotionMode :: Maybe Text
  -- ^ @"manual"@, @"auto"@, or 'Nothing' when not changing.
  , updatedAt :: UTCTime
  }

instance ToFirestore HypothesisStatusUpdate where
  toFirestoreFields statusUpdate =
    HashMap.fromList $
      [ ("status", toValue (hypothesisStatusToText statusUpdate.newStatus))
      , ("updatedAt", toValue statusUpdate.updatedAt)
      ]
        <> case statusUpdate.newPromotionMode of
          Nothing -> []
          Just modeText -> [("promotionMode", toValue modeText)]

-- | Fields to update when recording an MNPI self-declaration.
data HypothesisMnpiUpdate = HypothesisMnpiUpdate
  { mnpiSelfDeclared :: Bool
  , updatedAt :: UTCTime
  }

instance ToFirestore HypothesisMnpiUpdate where
  toFirestoreFields mnpiUpdate =
    HashMap.fromList
      [ ("mnpiSelfDeclared", toValue mnpiUpdate.mnpiSelfDeclared)
      , ("updatedAt", toValue mnpiUpdate.updatedAt)
      ]

-- ---------------------------------------------------------------------------
-- Update operations
-- ---------------------------------------------------------------------------

{- | Overwrite @status@, optionally @promotionMode@, and @updatedAt@ of a
hypothesis document in @hypothesis_registry@.
-}
updateHypothesisStatus ::
  FirestoreHypothesisRepositoryEnv ->
  -- | Hypothesis identifier (ULID).
  Text ->
  HypothesisStatusUpdate ->
  IO (Either FirestoreError ())
updateHypothesisStatus hypothesisRepositoryEnv hypothesisIdentifier statusUpdate =
  Firestore.upsertDocument
    hypothesisRepositoryEnv.firestoreContext
    (CollectionName "hypothesis_registry")
    (DocumentId hypothesisIdentifier)
    statusUpdate

{- | Overwrite @mnpiSelfDeclared@ and @updatedAt@ of a hypothesis document
in @hypothesis_registry@.
-}
updateHypothesisMnpi ::
  FirestoreHypothesisRepositoryEnv ->
  -- | Hypothesis identifier (ULID).
  Text ->
  HypothesisMnpiUpdate ->
  IO (Either FirestoreError ())
updateHypothesisMnpi hypothesisRepositoryEnv hypothesisIdentifier mnpiUpdate =
  Firestore.upsertDocument
    hypothesisRepositoryEnv.firestoreContext
    (CollectionName "hypothesis_registry")
    (DocumentId hypothesisIdentifier)
    mnpiUpdate
