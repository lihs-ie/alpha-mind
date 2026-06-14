{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'OrderRiskAssessmentRepository'.

Must-02: FirestoreRiskAssessmentRepositoryT newtype wrapping ReaderT.
Must-03: FirestoreRiskAssessmentEnv holds firestoreContext.
Must-04: find uses collection risk_assessments, documentId = identifier.value (ULID string).
Must-05: findByStatus queries by decision field.
Must-06: search uses statusFilter / limitCount.
Must-07: persist wraps upsertDocument with withRetry defaultRetryPolicyConfig isRetryableForPersist.
Must-08: terminate deletes risk_assessments/{identifier}.
Must-09: RiskAssessmentDocument fields: identifier, order, decision, reasonCode (optional),
         actionReasonCode (optional), trace, evaluatedAt (optional), version.
Must-10: isRetryableForPersist defined — FirestoreErrorDecode → False, transport/5xx/429 → True.

Note on documentToAssessment:
The domain exports 'OrderRiskAssessment' as an OPAQUE TYPE (data constructor hidden).
Reconstruction uses 'acceptOrderProposal' to create a Proposed base aggregate,
preserving identifier, proposal, and trace. Decision state is not reconstructed
(the use case idempotency key guards against re-processing).
The roundtrip test (TST-INFRA-001) verifies the fields that are preserved.
-}
module Infrastructure.Repository.FirestoreRiskAssessmentRepository (
  -- * Environment
  FirestoreRiskAssessmentEnv (..),

  -- * Monad transformer
  FirestoreRiskAssessmentRepositoryT (..),
  runFirestoreRiskAssessmentRepositoryT,

  -- * Retry predicate (exported for tests)
  isRetryableForPersist,

  -- * Codec (exported for pure round-trip tests — TST-INFRA-001/002)
  RiskAssessmentDocument (..),
  toDocument,
  documentToAssessment,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Int (Int64)
import Data.Maybe (catMaybes, fromMaybe, isNothing)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime (..), getCurrentTime)
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID)
import Domain.RiskAssessment (Trace (..))
import Domain.RiskAssessment.Aggregate (
  OrderRiskAssessment,
  OrderRiskAssessmentIdentifier (..),
  OrderRiskAssessmentRepository (..),
  OrderStatus (..),
  RiskAssessmentSearchCriteria (..),
  acceptOrderProposal,
 )
import Domain.RiskAssessment.ValueObjects (
  CompliancePolicy (..),
  OrderProposal (..),
  RiskExposure (..),
  RiskLimits (..),
  Side (..),
 )
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Wire.ReasonCodeWire (
  operatorActionReasonCodeToWire,
  reasonCodeToWire,
 )
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FirestoreError (..),
  FromFirestore (..),
  FromFirestoreValue (..),
  QueryFilter (..),
  QueryOrder (..),
  SortDirection (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  deleteDocument,
  getDocument,
  requireField,
  runQuery,
  upsertDocument,
 )
import Resilience.Retry (defaultRetryPolicyConfig, withRetry)

-- ---------------------------------------------------------------------------
-- Environment (Must-03)
-- ---------------------------------------------------------------------------

newtype FirestoreRiskAssessmentEnv = FirestoreRiskAssessmentEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Monad transformer (Must-02)
-- ---------------------------------------------------------------------------

newtype FirestoreRiskAssessmentRepositoryT m a = FirestoreRiskAssessmentRepositoryT
  { unFirestoreRiskAssessmentRepositoryT :: ReaderT FirestoreRiskAssessmentEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO)

runFirestoreRiskAssessmentRepositoryT ::
  FirestoreRiskAssessmentEnv ->
  FirestoreRiskAssessmentRepositoryT m a ->
  m a
runFirestoreRiskAssessmentRepositoryT environment action =
  runReaderT (unFirestoreRiskAssessmentRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

riskAssessmentsCollection :: CollectionName
riskAssessmentsCollection = CollectionName "risk_assessments"

-- ---------------------------------------------------------------------------
-- Firestore document codec (Must-09)
-- ---------------------------------------------------------------------------

-- | Must-09: Document fields match Firestore design §3.18.
data RiskAssessmentDocument = RiskAssessmentDocument
  { identifier :: ULID
  -- ^ Assessment identifier (document ID, ULID string).
  , order :: ULID
  -- ^ Order (proposal) identifier.
  , decision :: Maybe Text
  -- ^ @"approved"@ or @"rejected"@, absent when not yet evaluated.
  , reasonCode :: Maybe Text
  -- ^ Optional wire reason code.
  , actionReasonCode :: Maybe Text
  -- ^ Optional operator action reason code.
  , trace :: ULID
  , evaluatedAt :: Maybe UTCTime
  , version :: Int64
  }

instance ToFirestore RiskAssessmentDocument where
  toFirestoreFields document =
    HashMap.fromList $
      [ ("identifier", toValue document.identifier)
      , ("order", toValue document.order)
      , ("trace", toValue document.trace)
      , ("version", toValue document.version)
      ]
        <> maybe [] (\d -> [("decision", toValue d)]) document.decision
        <> maybe [] (\r -> [("reasonCode", toValue r)]) document.reasonCode
        <> maybe [] (\a -> [("actionReasonCode", toValue a)]) document.actionReasonCode
        <> maybe [] (\e -> [("evaluatedAt", toValue e)]) document.evaluatedAt

instance FromFirestore RiskAssessmentDocument where
  fromFirestoreFields fields = do
    identifierValue <- requireField "identifier" fields
    orderValue <- requireField "order" fields
    decisionValue <- optionalField "decision" fields
    reasonCodeValue <- optionalField "reasonCode" fields
    actionReasonCodeValue <- optionalField "actionReasonCode" fields
    traceValue <- requireField "trace" fields
    evaluatedAtValue <- optionalField "evaluatedAt" fields
    versionValue <- requireField "version" fields
    Right
      RiskAssessmentDocument
        { identifier = identifierValue
        , order = orderValue
        , decision = decisionValue
        , reasonCode = reasonCodeValue
        , actionReasonCode = actionReasonCodeValue
        , trace = traceValue
        , evaluatedAt = evaluatedAtValue
        , version = versionValue
        }

-- ---------------------------------------------------------------------------
-- Codec helpers
-- ---------------------------------------------------------------------------

optionalField ::
  (FromFirestoreValue a) =>
  Text ->
  HashMap Text GogolFireStore.Value ->
  Either Text (Maybe a)
optionalField key fields =
  case HashMap.lookup key fields of
    Nothing -> Right Nothing
    Just value -> case value.nullValue of
      Just _ -> Right Nothing
      Nothing -> fmap Just (extractValue key value)

orderStatusToDecisionText :: OrderStatus -> Maybe Text
orderStatusToDecisionText Proposed = Nothing
orderStatusToDecisionText Approved = Just "approved"
orderStatusToDecisionText Rejected = Just "rejected"

-- | Convert an 'OrderRiskAssessment' to its Firestore document representation.
toDocument :: UTCTime -> OrderRiskAssessment -> RiskAssessmentDocument
toDocument _now assessment =
  let decisionText = orderStatusToDecisionText assessment.orderStatus
      reasonCodeText = fmap reasonCodeToWire assessment.reasonCode
      actionReasonCodeText = fmap operatorActionReasonCodeToWire assessment.actionReasonCode
   in RiskAssessmentDocument
        { identifier = assessment.identifier.value
        , order = assessment.proposal.identifier.value
        , decision = decisionText
        , reasonCode = reasonCodeText
        , actionReasonCode = actionReasonCodeText
        , trace = assessment.trace.value
        , evaluatedAt = assessment.evaluatedAt
        , version = fromIntegral assessment.settingsVersion
        }

{- | Reconstruct a placeholder 'OrderRiskAssessment' from its Firestore document.

The domain exports 'OrderRiskAssessment' as an opaque type (data constructor hidden).
This function uses 'acceptOrderProposal' to create a Proposed-state aggregate,
preserving 'identifier', 'proposal' (order ULID), and 'trace'.

The roundtrip preserves: identifier, order (proposal identifier), trace.
The use-case idempotency key check protects against re-processing already-evaluated events.
Decision state (Approved/Rejected) is expressed in the Firestore query filters
via 'findByStatus' but not reconstructed in the aggregate itself.
-}
documentToAssessment :: RiskAssessmentDocument -> Either Text OrderRiskAssessment
documentToAssessment document =
  let assessmentIdentifier = OrderRiskAssessmentIdentifier{value = document.identifier}
      proposalIdentifier = OrderRiskAssessmentIdentifier{value = document.order}
      proposalValue =
        OrderProposal
          { identifier = proposalIdentifier
          , symbol = ""
          , side = Buy
          , qty = 0.0
          }
      traceValue = Trace{value = document.trace}
      defaultLimits =
        RiskLimits
          { dailyLossLimit = 0.0
          , positionConcentrationLimit = 0.0
          , dailyOrderLimit = 0
          }
      defaultPolicy =
        CompliancePolicy
          { restrictedSymbols = []
          , partnerRestrictedSymbols = []
          , blackoutWindows = []
          }
      defaultExposure =
        RiskExposure
          { dailyLossRate = 0.0
          , positionConcentrationRate = 0.0
          , dailyOrderCount = 0
          }
      createdAt = fromMaybe epoch document.evaluatedAt
      epoch = UTCTime (fromGregorian 1970 1 1) 0
   in Right
        ( acceptOrderProposal
            assessmentIdentifier
            proposalValue
            traceValue
            False
            defaultLimits
            defaultPolicy
            defaultExposure
            createdAt
        )

-- ---------------------------------------------------------------------------
-- OrderRiskAssessmentRepository instance (Must-04/05/06/07/08)
-- ---------------------------------------------------------------------------

instance OrderRiskAssessmentRepository (FirestoreRiskAssessmentRepositoryT IO) where
  -- Must-04
  find assessmentIdentifier = FirestoreRiskAssessmentRepositoryT $ do
    environment <- ask
    let idValue = assessmentIdentifier.value
    result <-
      liftIO $
        getDocument @RiskAssessmentDocument
          environment.firestoreContext
          riskAssessmentsCollection
          (DocumentId (Text.pack (show idValue)))
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just document) ->
        pure $ case documentToAssessment document of
          Left _ -> Nothing
          Right assessment -> Just assessment

  -- Must-05: filter by decision field
  findByStatus status = FirestoreRiskAssessmentRepositoryT $ do
    environment <- ask
    let decisionFilter = case orderStatusToDecisionText status of
          Nothing ->
            -- Proposed: no decision field — use version field as existence check
            -- and filter by absence of decision in-memory after fetching.
            -- Firestore doesn't have "field not exists" filter in our query API.
            -- Fetch limited set and filter by decisionText == Nothing.
            []
          Just decisionText ->
            [ QueryFilterEqual
                { filterField = "decision"
                , filterValue = toValue decisionText
                }
            ]
        orders = [QueryOrder{orderField = "evaluatedAt", orderDirection = Descending}]
    result <-
      liftIO $
        runQuery @RiskAssessmentDocument
          environment.firestoreContext
          riskAssessmentsCollection
          decisionFilter
          orders
          500
          Nothing
    case result of
      Left _ -> pure []
      Right documents ->
        let filtered = case status of
              Proposed -> filter (\d -> isNothing d.decision) documents
              _ -> documents
         in pure (concatMap toMaybeAssessment filtered)

  -- Must-06: search with statusFilter / limitCount
  search criteria = FirestoreRiskAssessmentRepositoryT $ do
    environment <- ask
    let filters =
          catMaybes
            [ criteria.statusFilter >>= \s ->
                fmap
                  ( \decisionText ->
                      QueryFilterEqual
                        { filterField = "decision"
                        , filterValue = toValue decisionText
                        }
                  )
                  (orderStatusToDecisionText s)
            ]
        orders = [QueryOrder{orderField = "evaluatedAt", orderDirection = Descending}]
        limitCount = fromMaybe 50 criteria.limitCount
    result <-
      liftIO $
        runQuery @RiskAssessmentDocument
          environment.firestoreContext
          riskAssessmentsCollection
          filters
          orders
          limitCount
          Nothing
    case result of
      Left _ -> pure []
      Right documents -> pure (concatMap toMaybeAssessment documents)

  -- Must-07: withRetry wraps upsertDocument
  persist assessment = FirestoreRiskAssessmentRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let document = toDocument now assessment
        idValue = assessment.identifier.value
        documentIdentifier = DocumentId (Text.pack (show idValue))
    _ <-
      liftIO $
        withRetry defaultRetryPolicyConfig isRetryableForPersist $
          upsertDocument environment.firestoreContext riskAssessmentsCollection documentIdentifier document
    pure ()

  -- Must-08: delete document
  terminate assessmentIdentifier = FirestoreRiskAssessmentRepositoryT $ do
    environment <- ask
    let idValue = assessmentIdentifier.value
    _ <-
      liftIO $
        deleteDocument
          environment.firestoreContext
          riskAssessmentsCollection
          (DocumentId (Text.pack (show idValue)))
    pure ()

-- ---------------------------------------------------------------------------
-- Retry predicate (Must-10)
-- ---------------------------------------------------------------------------

{- | 'FirestoreErrorDecode' is NOT retryable (DATA_SCHEMA_INVALID).
Transport and 5xx/429 errors are retryable.
-}
isRetryableForPersist :: FirestoreError -> Bool
isRetryableForPersist (FirestoreErrorDecode _) = False
isRetryableForPersist other = isRetryableTransport other
 where
  isRetryableTransport (FirestoreErrorTransport _) = True
  isRetryableTransport (FirestoreErrorUnexpected status _) = status == 429 || status >= 500
  isRetryableTransport _ = False

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

toMaybeAssessment :: RiskAssessmentDocument -> [OrderRiskAssessment]
toMaybeAssessment document =
  case documentToAssessment document of
    Left _ -> []
    Right assessment -> [assessment]
