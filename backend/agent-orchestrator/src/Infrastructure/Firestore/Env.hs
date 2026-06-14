{- | Shared Firestore environment for agent-orchestrator infrastructure.

Must-02: FirestoreEnv record with injectable firestoreExecute transport function.
Must-03: GCP_PROJECT_ID environment variable name documented here.

The 'firestoreExecute' field is a record of injectable IO actions that wrap
the Firestore REST API operations.  In production, these are implemented via
'Persistence.Firestore' (gogol-firestore 1.0.0).  In tests, they can be replaced
with pure in-memory functions — no real GCP calls are made.

Environment variable: @GCP_PROJECT_ID@ — GCP project identifier.
Environment variable: @FIRESTORE_DATABASE_ID@ — Firestore database identifier (default: @(default)@).
-}
module Infrastructure.Firestore.Env (
  -- * Environment
  FirestoreEnv (..),

  -- * Transport
  FirestoreTransport (..),

  -- * Constants
  gcpProjectIdEnvVar,
  firestoreDatabaseIdEnvVar,
) where

import Data.HashMap.Strict (HashMap)
import Data.Text (Text)
import Gogol.FireStore qualified as GogolFireStore
import Persistence.Firestore (
  CollectionName,
  DocumentId,
  FirestoreError,
  QueryFilter,
  QueryOrder,
 )

-- ---------------------------------------------------------------------------
-- Environment variable names (Must-03)
-- ---------------------------------------------------------------------------

{- | Must-03: Environment variable for GCP project identifier.
Value is read at startup by 'Main.hs' wiring; not read by this module itself.
-}
gcpProjectIdEnvVar :: Text
gcpProjectIdEnvVar = "GCP_PROJECT_ID"

{- | Environment variable for Firestore database identifier.
Defaults to @"(default)"@ when not set.
-}
firestoreDatabaseIdEnvVar :: Text
firestoreDatabaseIdEnvVar = "FIRESTORE_DATABASE_ID"

-- ---------------------------------------------------------------------------
-- Transport (injectable for tests — Must-26)
-- ---------------------------------------------------------------------------

{- | Injectable Firestore transport.
All operations are functions from inputs to IO results, allowing
test code to replace the real gogol-firestore implementation with
in-memory stubs without any network calls.

Field naming uses @transport@ prefix to avoid shadowing
'Persistence.Firestore' exported functions.
-}
data FirestoreTransport = FirestoreTransport
  { transportGetDocument ::
      CollectionName ->
      DocumentId ->
      IO (Either FirestoreError (Maybe (HashMap Text GogolFireStore.Value)))
  {- ^ Fetch a single document by collection + document ID.
  Returns 'Nothing' when the document does not exist (404).
  -}
  , transportUpsertDocument ::
      CollectionName ->
      DocumentId ->
      HashMap Text GogolFireStore.Value ->
      IO (Either FirestoreError ())
  -- ^ Create or replace a document (PATCH semantics).
  , transportDeleteDocument ::
      CollectionName ->
      DocumentId ->
      IO (Either FirestoreError ())
  -- ^ Physically delete a document.
  , transportRunQuery ::
      CollectionName ->
      [QueryFilter] ->
      [QueryOrder] ->
      Int ->
      IO (Either FirestoreError [HashMap Text GogolFireStore.Value])
  -- ^ Execute a structured query returning raw field maps.
  }

-- ---------------------------------------------------------------------------
-- Environment (Must-02)
-- ---------------------------------------------------------------------------

{- | Must-02: Firestore environment record.

Fields:
  * 'firestoreExecute' — injectable transport capability (replaced in tests).
  * 'projectIdentifier' — GCP project ID (read from @GCP_PROJECT_ID@).
  * 'databaseIdentifier' — Firestore database ID (read from @FIRESTORE_DATABASE_ID@,
    default @"(default)"@).
-}
data FirestoreEnv = FirestoreEnv
  { firestoreExecute :: FirestoreTransport
  -- ^ Must-02: mockable transport — no real GCP calls when replaced in tests.
  , projectIdentifier :: Text
  -- ^ Must-02/Must-03: GCP project ID from @GCP_PROJECT_ID@.
  , databaseIdentifier :: Text
  -- ^ Must-02: Firestore database ID from @FIRESTORE_DATABASE_ID@.
  }
