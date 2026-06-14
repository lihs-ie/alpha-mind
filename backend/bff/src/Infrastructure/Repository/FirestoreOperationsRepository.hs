module Infrastructure.Repository.FirestoreOperationsRepository (
  FirestoreOperationsRepositoryEnv (..),
  OperationsRuntime (..),
  OperationsUpdate (..),
  getOperationsRuntime,
  operationsRuntimeState,
  operationsKillSwitchEnabled,
  operationsVersion,
  updateOperationsRuntime,
)
where

import Data.HashMap.Strict qualified as HashMap
import Data.Int (Int64)
import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.Dashboard.Summary (RuntimeState (..))
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext (..),
  FirestoreError,
  FromFirestore (..),
  FromFirestoreValue (..),
  ToFirestore (..),
  ToFirestoreValue (..),
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
  , version :: Int
  -- ^ Optimistic concurrency version counter.
  }

instance FromFirestore OperationsRuntime where
  fromFirestoreFields fieldMap = do
    runtimeStateText <- requireField "runtimeState" fieldMap
    runtimeStateValue <- parseRuntimeState runtimeStateText
    killSwitchValue <- requireField "killSwitchEnabled" fieldMap
    let versionValue = case HashMap.lookup "version" fieldMap of
          Nothing -> 0
          Just fieldValue ->
            case extractValue "version" fieldValue :: Either Text Int64 of
              Left _ -> 0
              Right integerValue -> fromIntegral integerValue
    pure
      OperationsRuntime
        { runtimeState = runtimeStateValue
        , killSwitchEnabled = killSwitchValue
        , version = versionValue
        }

parseRuntimeState :: Text -> Either Text RuntimeState
parseRuntimeState "RUNNING" = Right Running
parseRuntimeState "STOPPED" = Right Stopped
parseRuntimeState unknown = Left ("Unknown runtimeState: " <> unknown)

-- ---------------------------------------------------------------------------
-- Update record
-- ---------------------------------------------------------------------------

-- | Data for writing to @operations\/runtime@ Firestore document.
data OperationsUpdate = OperationsUpdate
  { runtimeState :: RuntimeState
  , killSwitchEnabled :: Bool
  , updatedBy :: Text
  , updatedAt :: UTCTime
  , version :: Int
  }

instance ToFirestore OperationsUpdate where
  toFirestoreFields operationsUpdate =
    HashMap.fromList
      [ ("runtimeState", toValue (runtimeStateToText operationsUpdate.runtimeState))
      , ("killSwitchEnabled", toValue operationsUpdate.killSwitchEnabled)
      , ("updatedBy", toValue operationsUpdate.updatedBy)
      , ("updatedAt", toValue operationsUpdate.updatedAt)
      , ("version", toValue (fromIntegral operationsUpdate.version :: Int64))
      ]

runtimeStateToText :: RuntimeState -> Text
runtimeStateToText Running = "RUNNING"
runtimeStateToText Stopped = "STOPPED"

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
          , version = 0
          }
    Right (Just documentValue) -> Right documentValue

-- ---------------------------------------------------------------------------
-- Field accessors (avoids DuplicateRecordFields ambiguity in consumers)
-- ---------------------------------------------------------------------------

-- | Extract @runtimeState@ from 'OperationsRuntime'.
operationsRuntimeState :: OperationsRuntime -> RuntimeState
operationsRuntimeState r = r.runtimeState

-- | Extract @killSwitchEnabled@ from 'OperationsRuntime'.
operationsKillSwitchEnabled :: OperationsRuntime -> Bool
operationsKillSwitchEnabled r = r.killSwitchEnabled

-- | Extract @version@ from 'OperationsRuntime'.
operationsVersion :: OperationsRuntime -> Int
operationsVersion r = r.version

-- | Write updated operations state to @operations\/runtime@ Firestore document.
updateOperationsRuntime ::
  FirestoreOperationsRepositoryEnv ->
  OperationsUpdate ->
  IO (Either FirestoreError ())
updateOperationsRuntime operationsRepositoryEnv operationsUpdate =
  Firestore.upsertDocument
    operationsRepositoryEnv.firestoreContext
    (CollectionName "operations")
    (DocumentId "runtime")
    operationsUpdate
