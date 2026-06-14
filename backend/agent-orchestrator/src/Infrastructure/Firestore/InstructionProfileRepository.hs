{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'InstructionProfileRepository'.

Must-06: find, findByVersion, search implemented via injectable FirestoreTransport.
Must-07: contentPath field absence → DomainError (MissingRequiredFields).

Collection: @instruction_profiles@
Document ID: profile identifier text
-}
module Infrastructure.Firestore.InstructionProfileRepository (
  -- * Environment
  FirestoreInstructionProfileEnv (..),

  -- * Monad transformer
  FirestoreInstructionProfileRepositoryT (..),
  runFirestoreInstructionProfileRepositoryT,

  -- * Codec (exported for pure round-trip tests)
  profileToFields,
  fieldsToProfile,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Class (MonadTrans)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Either (rights)
import Data.HashMap.Strict qualified as HashMap
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.InstructionProfile (
  InstructionProfile (..),
  InstructionProfileRepository (..),
  InstructionProfileSearchCriteria (..),
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
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

-- ---------------------------------------------------------------------------
-- Collection constant
-- ---------------------------------------------------------------------------

instructionProfilesCollection :: CollectionName
instructionProfilesCollection = CollectionName "instruction_profiles"

defaultQueryLimit :: Int
defaultQueryLimit = 50

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreInstructionProfileEnv = FirestoreInstructionProfileEnv
  { firestoreEnv :: FirestoreEnv
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreInstructionProfileRepositoryT m a = FirestoreInstructionProfileRepositoryT
  { unFirestoreInstructionProfileRepositoryT :: ReaderT FirestoreInstructionProfileEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadTrans)

runFirestoreInstructionProfileRepositoryT ::
  FirestoreInstructionProfileEnv ->
  FirestoreInstructionProfileRepositoryT m a ->
  m a
runFirestoreInstructionProfileRepositoryT environment action =
  runReaderT (unFirestoreInstructionProfileRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Firestore codec
-- ---------------------------------------------------------------------------

{- | Encode an 'InstructionProfile' to Firestore field map.
The 'content' field is stored as @contentPath@.
Exported for pure round-trip tests.
-}
profileToFields :: InstructionProfile -> HashMap.HashMap Text GogolFireStore.Value
profileToFields profile =
  HashMap.fromList
    [ ("identifier", toValue profile.identifier)
    , ("name", toValue profile.name)
    , ("version", toValue profile.version)
    , ("contentPath", toValue profile.content)
    ]

{- | Decode a Firestore field map to an 'InstructionProfile'.
Must-07: missing @contentPath@ → 'Left (MissingRequiredFields ["contentPath"] ResourceNotFound)'.
Exported for pure round-trip tests.
-}
fieldsToProfile :: HashMap.HashMap Text GogolFireStore.Value -> Either DomainError InstructionProfile
fieldsToProfile fields = do
  identifierValue <- liftTextError (requireField "identifier" fields)
  nameValue <- liftTextError (requireField "name" fields)
  versionValue <- liftTextError (requireField "version" fields)
  contentValue <- case requireField "contentPath" fields of
    Left _ -> Left (MissingRequiredFields ["contentPath"] ResourceNotFound)
    Right v -> Right (v :: Text)
  Right
    InstructionProfile
      { identifier = identifierValue
      , name = nameValue
      , version = versionValue
      , content = contentValue
      }

liftTextError :: Either Text a -> Either DomainError a
liftTextError (Right x) = Right x
liftTextError (Left message) = Left (MissingRequiredFields [message] ResourceNotFound)

-- ---------------------------------------------------------------------------
-- InstructionProfileRepository instance (Must-06)
-- ---------------------------------------------------------------------------

instance InstructionProfileRepository (FirestoreInstructionProfileRepositoryT IO) where
  find profileIdentifier = FirestoreInstructionProfileRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportGetDocument} = environment.firestoreEnv.firestoreExecute
    result <- liftIO $ transportGetDocument instructionProfilesCollection (DocumentId profileIdentifier)
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just fieldMap) ->
        pure $ case fieldsToProfile fieldMap of
          Left _ -> Nothing
          Right profile -> Just profile

  findByVersion versionText = FirestoreInstructionProfileRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        filters = [QueryFilterEqual{filterField = "version", filterValue = toValue versionText}]
        orders = [QueryOrder{orderField = "name", orderDirection = Ascending}]
    result <- liftIO $ transportRunQuery instructionProfilesCollection filters orders 1
    case result of
      Left _ -> pure Nothing
      Right [] -> pure Nothing
      Right (fieldMap : _rest) ->
        pure $ case fieldsToProfile fieldMap of
          Left _ -> Nothing
          Right profile -> Just profile

  search criteria = FirestoreInstructionProfileRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        limitValue = fromMaybe defaultQueryLimit criteria.limitCount
        orders = [QueryOrder{orderField = "name", orderDirection = Ascending}]
    result <- liftIO $ transportRunQuery instructionProfilesCollection [] orders limitValue
    case result of
      Left _ -> pure []
      Right fieldMaps ->
        let allProfiles = rights (map fieldsToProfile fieldMaps)
         in pure $ case criteria.nameFilter of
              Nothing -> allProfiles
              Just nameFilter -> filter (\p -> nameFilter `Text.isInfixOf` p.name) allProfiles
