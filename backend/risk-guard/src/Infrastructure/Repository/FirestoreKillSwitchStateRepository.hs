{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation for kill switch state persistence.

Must-20: Provides persistKillSwitchState and loadKillSwitchState.
Both operate on the @operations/runtime@ document.

'persistKillSwitchState' upserts the @killSwitchEnabled@ field.
'loadKillSwitchState' reads the @killSwitchEnabled@ field.
-}
module Infrastructure.Repository.FirestoreKillSwitchStateRepository (
  -- * Environment
  FirestoreKillSwitchStateEnv (..),

  -- * Functions
  persistKillSwitchState,
  loadKillSwitchState,
) where

import Data.HashMap.Strict qualified as HashMap
import Data.Time (UTCTime, getCurrentTime)
import Persistence.Firestore (
  CollectionName (..),
  DocumentId (..),
  FirestoreContext,
  FromFirestore (..),
  ToFirestore (..),
  ToFirestoreValue (..),
  getDocument,
  requireField,
  upsertDocument,
 )

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreKillSwitchStateEnv = FirestoreKillSwitchStateEnv
  { firestoreContext :: FirestoreContext
  }

-- ---------------------------------------------------------------------------
-- Document codec
-- ---------------------------------------------------------------------------

-- | Minimal document for reading kill switch state from operations/runtime.
newtype RuntimeStateDocument = RuntimeStateDocument
  { killSwitchEnabled :: Bool
  }

instance FromFirestore RuntimeStateDocument where
  fromFirestoreFields fields = do
    killSwitchEnabledValue <- requireField "killSwitchEnabled" fields
    Right RuntimeStateDocument{killSwitchEnabled = killSwitchEnabledValue}

-- | Minimal document for writing kill switch state.
data RuntimeKillSwitchWriteDocument = RuntimeKillSwitchWriteDocument
  { killSwitchEnabled :: Bool
  , updatedAt :: UTCTime
  }

instance ToFirestore RuntimeKillSwitchWriteDocument where
  toFirestoreFields document =
    HashMap.fromList
      [ ("killSwitchEnabled", toValue document.killSwitchEnabled)
      , ("updatedAt", toValue document.updatedAt)
      ]

-- ---------------------------------------------------------------------------
-- operations/runtime document identifiers
-- ---------------------------------------------------------------------------

operationsCollection :: CollectionName
operationsCollection = CollectionName "operations"

runtimeDocumentId :: DocumentId
runtimeDocumentId = DocumentId "runtime"

-- ---------------------------------------------------------------------------
-- Must-20: persistKillSwitchState
-- ---------------------------------------------------------------------------

{- | Persist the kill switch state to @operations/runtime@.

Upserts only the @killSwitchEnabled@ and @updatedAt@ fields.
Other fields (runtimeState, reason, updatedBy) are preserved by Firestore.
-}
persistKillSwitchState :: FirestoreKillSwitchStateEnv -> Bool -> IO ()
persistKillSwitchState environment enabled = do
  now <- getCurrentTime
  let document =
        RuntimeKillSwitchWriteDocument
          { killSwitchEnabled = enabled
          , updatedAt = now
          }
  _ <-
    upsertDocument
      environment.firestoreContext
      operationsCollection
      runtimeDocumentId
      document
  pure ()

-- ---------------------------------------------------------------------------
-- Must-20: loadKillSwitchState
-- ---------------------------------------------------------------------------

{- | Load the kill switch state from @operations/runtime@.

Returns 'True' (kill switch enabled) on error — fail-safe: halt trading on uncertainty.
-}
loadKillSwitchState :: FirestoreKillSwitchStateEnv -> IO Bool
loadKillSwitchState environment = do
  result <-
    getDocument @RuntimeStateDocument
      environment.firestoreContext
      operationsCollection
      runtimeDocumentId
  case result of
    Left _ -> pure True
    Right Nothing -> pure True
    Right (Just document) -> pure document.killSwitchEnabled
