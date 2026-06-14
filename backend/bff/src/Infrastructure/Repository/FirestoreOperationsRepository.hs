module Infrastructure.Repository.FirestoreOperationsRepository (
  FirestoreOperationsRepositoryEnv (..),
  OperationsRuntime (..),
  getOperationsRuntime,
)
where

import Data.Text (Text)
import Domain.Dashboard.Summary (RuntimeState (..))
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext (..),
  FirestoreError,
  FromFirestore (..),
  requireField,
 )
import Persistence.Firestore qualified as Firestore

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

-- | Environment for reading the @operations@ Firestore collection.
newtype FirestoreOperationsRepositoryEnv = FirestoreOperationsRepositoryEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Domain record
-- ---------------------------------------------------------------------------

-- | Must-04: Data read from @operations\/runtime@ Firestore document.
data OperationsRuntime = OperationsRuntime
  { runtimeState :: RuntimeState
  -- ^ RUNNING or STOPPED.
  , killSwitchEnabled :: Bool
  -- ^ Kill-switch flag.
  }

instance FromFirestore OperationsRuntime where
  fromFirestoreFields fieldMap = do
    runtimeStateText <- requireField "runtimeState" fieldMap
    runtimeStateValue <- parseRuntimeState runtimeStateText
    killSwitchValue <- requireField "killSwitchEnabled" fieldMap
    pure
      OperationsRuntime
        { runtimeState = runtimeStateValue
        , killSwitchEnabled = killSwitchValue
        }

parseRuntimeState :: Text -> Either Text RuntimeState
parseRuntimeState "RUNNING" = Right Running
parseRuntimeState "STOPPED" = Right Stopped
parseRuntimeState unknown = Left ("Unknown runtimeState: " <> unknown)

-- ---------------------------------------------------------------------------
-- Repository
-- ---------------------------------------------------------------------------

{- | Must-04: Read the @operations\/runtime@ document from Firestore.

Must-07: Returns default 'OperationsRuntime' when the document does not exist.
-}
getOperationsRuntime ::
  FirestoreOperationsRepositoryEnv ->
  IO (Either FirestoreError OperationsRuntime)
getOperationsRuntime operationsRepositoryEnv = do
  resultValue <-
    Firestore.getDocument
      operationsRepositoryEnv.firestoreContext
      (CollectionName "operations")
      (DocumentId "runtime")
  pure $ case resultValue of
    Left firestoreError -> Left firestoreError
    Right Nothing ->
      Right
        OperationsRuntime
          { runtimeState = Stopped
          , killSwitchEnabled = False
          }
    Right (Just documentValue) -> Right documentValue
