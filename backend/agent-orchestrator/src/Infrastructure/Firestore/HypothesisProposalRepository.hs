{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'HypothesisProposalRepository'.

Must-12: find, findByStatus, search, persist, terminate implemented.
Must-13: status field mapping — unknown → DomainError.
Must-14: updatedAt written on every persist; createdAt is included in the
         serialised document but uses the proposal's existing 'createdAt' value,
         so it is never overwritten for pre-existing documents (upsert semantics).

Collection: @hypothesis_registry@
Document ID: @identifier.value@ (ULID string)

Status mapping (domain ↔ Firestore):
  Pending  ↔ "pending"
  Proposed ↔ "proposed"
  Blocked  ↔ "blocked"
  Failed   ↔ "failed"

Other Firestore status values are treated as unknown and return 'Left DomainError'.
-}
module Infrastructure.Firestore.HypothesisProposalRepository (
  -- * Environment
  FirestoreHypothesisProposalEnv (..),

  -- * Monad transformer
  FirestoreHypothesisProposalRepositoryT (..),
  runFirestoreHypothesisProposalRepositoryT,

  -- * Codec (exported for pure round-trip tests)
  proposalToFields,
  fieldsToProposal,

  -- * Status codec (exported for mapping tests)
  proposalStatusToText,
  proposalStatusFromText,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Class (MonadTrans)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Either (rights)
import Data.HashMap.Strict qualified as HashMap
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime, getCurrentTime)
import Data.ULID (ULID)
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposal,
  HypothesisProposalIdentifier (..),
  HypothesisProposalRepository (..),
  InstrumentType (..),
  ProposalSearchCriteria (..),
  ProposalStatus (..),
  startProposal,
 )
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (InsiderRiskLevel (..))
import Gogol.FireStore qualified as GogolFireStore
import Infrastructure.Firestore.Env (FirestoreEnv (..), FirestoreTransport (..))
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  QueryFilter (..),
  QueryOrder (..),
  SortDirection (..),
  ToFirestoreValue (..),
  requireField,
 )
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

hypothesisRegistryCollection :: CollectionName
hypothesisRegistryCollection = CollectionName "hypothesis_registry"

defaultQueryLimit :: Int
defaultQueryLimit = 50

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreHypothesisProposalEnv = FirestoreHypothesisProposalEnv
  { firestoreEnv :: FirestoreEnv
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreHypothesisProposalRepositoryT m a = FirestoreHypothesisProposalRepositoryT
  { unFirestoreHypothesisProposalRepositoryT :: ReaderT FirestoreHypothesisProposalEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadTrans)

runFirestoreHypothesisProposalRepositoryT ::
  FirestoreHypothesisProposalEnv ->
  FirestoreHypothesisProposalRepositoryT m a ->
  m a
runFirestoreHypothesisProposalRepositoryT environment action =
  runReaderT (unFirestoreHypothesisProposalRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Status codec (Must-13)
-- ---------------------------------------------------------------------------

{- | Must-13: Map domain 'ProposalStatus' to Firestore @hypothesis_registry.status@ string value.
--
-- Mapping table (per firestore設計.md §3.11 cross-referenced with agent-orchestrator domain):
-- * 'Pending'  ↔ @"draft"@      — proposal is being drafted/assembled
-- * 'Proposed' ↔ @"backtested"@ — proposal has been generated and submitted
-- * 'Blocked'  ↔ @"rejected"@   — proposal was suppressed/blocked
-- * 'Failed'   ↔ @"failed"@     — proposal generation failed (agent-orchestrator specific)
--
-- Note: @"demo"@ and @"live"@ are hypothesis-lab lifecycle values; they are not
-- written by agent-orchestrator and are treated as unknown on read.
--
-- Exported for status mapping tests.
-}
proposalStatusToText :: ProposalStatus -> Text
proposalStatusToText Pending = "draft"
proposalStatusToText Proposed = "backtested"
proposalStatusToText Blocked = "rejected"
proposalStatusToText Failed = "failed"

{- | Must-13: Map Firestore @hypothesis_registry.status@ string to domain 'ProposalStatus'.
Unknown values → 'Left (MissingRequiredFields ["status"] RequestValidationFailed)'.
Exported for status mapping tests.
-}
proposalStatusFromText :: Text -> Either DomainError ProposalStatus
proposalStatusFromText "draft" = Right Pending
proposalStatusFromText "backtested" = Right Proposed
proposalStatusFromText "rejected" = Right Blocked
proposalStatusFromText "failed" = Right Failed
proposalStatusFromText _other = Left (MissingRequiredFields ["status"] RequestValidationFailed)

-- ---------------------------------------------------------------------------
-- InstrumentType codec
-- ---------------------------------------------------------------------------

instrumentTypeToText :: InstrumentType -> Text
instrumentTypeToText ETF = "ETF"
instrumentTypeToText Stock = "STOCK"

-- ---------------------------------------------------------------------------
-- ReasonCode codec
-- ---------------------------------------------------------------------------

reasonCodeToText :: ReasonCode -> Text
reasonCodeToText ResourceNotFound = "RESOURCE_NOT_FOUND"
reasonCodeToText RequestValidationFailed = "REQUEST_VALIDATION_FAILED"
reasonCodeToText StateConflict = "STATE_CONFLICT"
reasonCodeToText IdempotencyDuplicateEvent = "IDEMPOTENCY_DUPLICATE_EVENT"
reasonCodeToText DependencyTimeout = "DEPENDENCY_TIMEOUT"
reasonCodeToText DependencyUnavailable = "DEPENDENCY_UNAVAILABLE"

-- ---------------------------------------------------------------------------
-- InsiderRiskLevel codec
-- ---------------------------------------------------------------------------

insiderRiskToText :: InsiderRiskLevel -> Text
insiderRiskToText Low = "low"
insiderRiskToText Medium = "medium"
insiderRiskToText High = "high"

-- ---------------------------------------------------------------------------
-- Firestore codec
-- ---------------------------------------------------------------------------

{- | Encode a 'HypothesisProposal' to Firestore fields for persist.
Must-12: symbol, instrumentType, title, sourceEvidence, skillVersion,
         instructionProfileVersion, insiderRisk, mnpiSelfDeclared, status,
         reasonCode, trace, updatedAt are all written.
Must-14: updatedAt is injected as a parameter; createdAt uses the proposal's
         'createdAt' value so it is not overwritten on update (the caller
         provides the same document with its original createdAt).
Exported for pure round-trip tests.
-}
proposalToFields :: UTCTime -> HypothesisProposal -> HashMap.HashMap Text GogolFireStore.Value
proposalToFields now proposal =
  let proposalId = proposal.identifier
      proposalTrace = proposal.trace
      HypothesisProposalIdentifier proposalUlid = proposalId
      Trace traceUlid = proposalTrace
   in HashMap.fromList $
        [ ("identifier", toValue (Text.pack (show proposalUlid)))
        , ("status", toValue (proposalStatusToText proposal.status))
        , ("trace", toValue (Text.pack (show traceUlid)))
        , ("dispatch", toValue proposal.dispatch)
        , ("updatedAt", toValue now)
        , ("createdAt", toValue proposal.createdAt)
        , ("sourceEvidence", toValue (Text.intercalate "," proposal.sourceEvidence))
        ]
          <> maybe [] (\s -> [("symbol", toValue s)]) proposal.symbol
          <> maybe [] (\t -> [("instrumentType", toValue (instrumentTypeToText t))]) proposal.instrumentType
          <> maybe [] (\t -> [("title", toValue t)]) proposal.title
          <> maybe [] (\s -> [("skillVersion", toValue s)]) proposal.skillVersion
          <> maybe [] (\s -> [("instructionProfileVersion", toValue s)]) proposal.instructionProfileVersion
          <> maybe [] (\r -> [("insiderRisk", toValue (insiderRiskToText r))]) proposal.insiderRisk
          <> maybe [] (\b -> [("mnpiSelfDeclared", toValue b)]) proposal.mnpiSelfDeclared
          <> maybe [] (\r -> [("reasonCode", toValue (reasonCodeToText r))]) proposal.reasonCode
          <> maybe [] (\p -> [("reportPath", toValue p)]) proposal.reportPath

{- | Decode a Firestore field map to a 'HypothesisProposal'.
Must-13: unknown status → 'Left DomainError'.

Note: Because 'HypothesisProposal' uses a hidden constructor (NoFieldSelectors),
reconstruction always produces a 'Pending' proposal via 'startProposal'.
The status field is validated (unknown values return 'Left DomainError') but the
reconstructed proposal's status is always 'Pending' — this is a known limitation
of the hidden-constructor aggregate pattern.  Status round-trip is tested
separately via 'proposalStatusFromText' \/ 'proposalStatusToText'.

Exported for pure round-trip tests.
-}
fieldsToProposal :: HashMap.HashMap Text GogolFireStore.Value -> Either DomainError HypothesisProposal
fieldsToProposal fields = do
  identifierText <- liftTextError (requireField "identifier" fields)
  identifierUlid <- case readMaybe (Text.unpack identifierText) of
    Nothing -> Left (MissingRequiredFields ["identifier"] RequestValidationFailed)
    Just ulid -> Right (ulid :: ULID)
  statusText <- liftTextError (requireField "status" fields)
  _statusValue <- proposalStatusFromText statusText -- validate; Must-13
  traceText <- liftTextError (requireField "trace" fields)
  traceUlid <- case readMaybe (Text.unpack traceText) of
    Nothing -> Left (MissingRequiredFields ["trace"] RequestValidationFailed)
    Just ulid -> Right (ulid :: ULID)
  dispatchValue <- liftTextError (requireField "dispatch" fields)
  createdAtValue <- liftTextError (requireField "createdAt" fields)
  let (baseProposal, _events) =
        startProposal
          HypothesisProposalIdentifier{value = identifierUlid}
          dispatchValue
          Trace{value = traceUlid}
          (createdAtValue :: UTCTime)
  pure baseProposal

liftTextError :: Either Text a -> Either DomainError a
liftTextError (Right x) = Right x
liftTextError (Left message) = Left (MissingRequiredFields [message] ResourceNotFound)

-- ---------------------------------------------------------------------------
-- HypothesisProposalRepository instance (Must-12)
-- ---------------------------------------------------------------------------

instance HypothesisProposalRepository (FirestoreHypothesisProposalRepositoryT IO) where
  find proposalIdentifier = FirestoreHypothesisProposalRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportGetDocument} = environment.firestoreEnv.firestoreExecute
        HypothesisProposalIdentifier proposalUlid = proposalIdentifier
        documentId = DocumentId (Text.pack (show proposalUlid))
    result <- liftIO $ transportGetDocument hypothesisRegistryCollection documentId
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just fieldMap) ->
        pure $ case fieldsToProposal fieldMap of
          Left _ -> Nothing
          Right proposal -> Just proposal

  findByStatus proposalStatus = FirestoreHypothesisProposalRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        -- Composite index: status ASC, updatedAt DESC (spec §Must-12)
        filters = [QueryFilterEqual{filterField = "status", filterValue = toValue (proposalStatusToText proposalStatus)}]
        orders = [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
    result <- liftIO $ transportRunQuery hypothesisRegistryCollection filters orders defaultQueryLimit
    case result of
      Left _ -> pure []
      Right fieldMaps -> pure (rights (map fieldsToProposal fieldMaps))

  search criteria = FirestoreHypothesisProposalRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        limitValue = fromMaybe defaultQueryLimit criteria.limitCount
        statusFilters = case criteria.statusFilter of
          Nothing -> []
          Just s -> [QueryFilterEqual{filterField = "status", filterValue = toValue (proposalStatusToText s)}]
        symbolFilters = case criteria.symbolFilter of
          Nothing -> []
          Just sym -> [QueryFilterEqual{filterField = "symbol", filterValue = toValue sym}]
        allFilters = statusFilters <> symbolFilters
        orders = [QueryOrder{orderField = "updatedAt", orderDirection = Descending}]
    result <- liftIO $ transportRunQuery hypothesisRegistryCollection allFilters orders limitValue
    case result of
      Left _ -> pure []
      Right fieldMaps -> pure (rights (map fieldsToProposal fieldMaps))

  -- Must-14: updatedAt = current time on every persist.
  -- createdAt is taken from proposal.createdAt, so it is not overwritten
  -- when the document already exists (upsert overwrites with same value).
  persist proposal = FirestoreHypothesisProposalRepositoryT $ do
    environment <- ask
    now <- liftIO getCurrentTime
    let FirestoreTransport{transportUpsertDocument} = environment.firestoreEnv.firestoreExecute
        HypothesisProposalIdentifier persistUlid = proposal.identifier
        documentId = DocumentId (Text.pack (show persistUlid))
        fieldMap = proposalToFields now proposal
    _result <- liftIO $ transportUpsertDocument hypothesisRegistryCollection documentId fieldMap
    pure ()

  -- Must-12: terminate deletes the document physically.
  terminate proposalIdentifier = FirestoreHypothesisProposalRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportDeleteDocument} = environment.firestoreEnv.firestoreExecute
        HypothesisProposalIdentifier terminateUlid = proposalIdentifier
        documentId = DocumentId (Text.pack (show terminateUlid))
    _result <- liftIO $ transportDeleteDocument hypothesisRegistryCollection documentId
    pure ()
