{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'SkillRegistryRepository'.

Must-04: find, findByStatus, search implemented via injectable FirestoreTransport.
Must-05: status field "active"/"deprecated"/"draft" only; unknown → DomainError.

Collection: @skill_registry@
Document ID: skill identifier text (e.g. ULID string)
-}
module Infrastructure.Firestore.SkillRegistryRepository (
  -- * Environment
  FirestoreSkillRegistryEnv (..),

  -- * Monad transformer
  FirestoreSkillRegistryRepositoryT (..),
  runFirestoreSkillRegistryRepositoryT,

  -- * Codec (exported for pure round-trip tests)
  skillToFields,
  fieldsToSkill,
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
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.SkillRegistry (
  Skill (..),
  SkillRegistryRepository (..),
  SkillSearchCriteria (..),
  SkillStatus (..),
 )
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

skillRegistryCollection :: CollectionName
skillRegistryCollection = CollectionName "skill_registry"

defaultQueryLimit :: Int
defaultQueryLimit = 50

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreSkillRegistryEnv = FirestoreSkillRegistryEnv
  { firestoreEnv :: FirestoreEnv
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreSkillRegistryRepositoryT m a = FirestoreSkillRegistryRepositoryT
  { unFirestoreSkillRegistryRepositoryT :: ReaderT FirestoreSkillRegistryEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadTrans)

runFirestoreSkillRegistryRepositoryT ::
  FirestoreSkillRegistryEnv ->
  FirestoreSkillRegistryRepositoryT m a ->
  m a
runFirestoreSkillRegistryRepositoryT environment action =
  runReaderT (unFirestoreSkillRegistryRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Status codec (Must-05)
-- ---------------------------------------------------------------------------

skillStatusToText :: SkillStatus -> Text
skillStatusToText SkillActive = "active"
skillStatusToText SkillDeprecated = "deprecated"
skillStatusToText SkillDraft = "draft"

skillStatusFromText :: Text -> Either DomainError SkillStatus
skillStatusFromText "active" = Right SkillActive
skillStatusFromText "deprecated" = Right SkillDeprecated
skillStatusFromText "draft" = Right SkillDraft
skillStatusFromText _other =
  Left (MissingRequiredFields ["status"] RequestValidationFailed)

-- ---------------------------------------------------------------------------
-- Firestore codec
-- ---------------------------------------------------------------------------

{- | Encode a 'Skill' to Firestore field map.
Exported for pure round-trip tests.
-}
skillToFields :: Skill -> HashMap.HashMap Text GogolFireStore.Value
skillToFields skill =
  HashMap.fromList
    [ ("identifier", toValue skill.identifier)
    , ("name", toValue skill.name)
    , ("version", toValue skill.version)
    , ("status", toValue (skillStatusToText skill.status))
    ]

{- | Decode a Firestore field map to a 'Skill'.
Must-05: unknown status → 'Left DomainError'.
Exported for pure round-trip tests.
-}
fieldsToSkill :: HashMap.HashMap Text GogolFireStore.Value -> Either DomainError Skill
fieldsToSkill fields = do
  identifierValue <- liftTextError (requireField "identifier" fields)
  nameValue <- liftTextError (requireField "name" fields)
  versionValue <- liftTextError (requireField "version" fields)
  statusText <- liftTextError (requireField "status" fields)
  statusValue <- skillStatusFromText statusText
  Right
    Skill
      { identifier = identifierValue
      , name = nameValue
      , version = versionValue
      , status = statusValue
      }

liftTextError :: Either Text a -> Either DomainError a
liftTextError (Right x) = Right x
liftTextError (Left message) = Left (MissingRequiredFields [message] ResourceNotFound)

-- ---------------------------------------------------------------------------
-- SkillRegistryRepository instance (Must-04)
-- ---------------------------------------------------------------------------

instance SkillRegistryRepository (FirestoreSkillRegistryRepositoryT IO) where
  find skillIdentifier = FirestoreSkillRegistryRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportGetDocument} = environment.firestoreEnv.firestoreExecute
    result <- liftIO $ transportGetDocument skillRegistryCollection (DocumentId skillIdentifier)
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just fieldMap) ->
        pure $ case fieldsToSkill fieldMap of
          Left _ -> Nothing
          Right skill -> Just skill

  findByStatus skillStatus = FirestoreSkillRegistryRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        filters = [QueryFilterEqual{filterField = "status", filterValue = toValue (skillStatusToText skillStatus)}]
        orders = [QueryOrder{orderField = "name", orderDirection = Ascending}]
    result <- liftIO $ transportRunQuery skillRegistryCollection filters orders defaultQueryLimit
    case result of
      Left _ -> pure []
      Right fieldMaps -> pure (rights (map fieldsToSkill fieldMaps))

  search criteria = FirestoreSkillRegistryRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        limitValue = fromMaybe defaultQueryLimit criteria.limitCount
        statusFilters = case criteria.statusFilter of
          Nothing -> []
          Just s -> [QueryFilterEqual{filterField = "status", filterValue = toValue (skillStatusToText s)}]
        orders = [QueryOrder{orderField = "name", orderDirection = Ascending}]
    result <- liftIO $ transportRunQuery skillRegistryCollection statusFilters orders limitValue
    case result of
      Left _ -> pure []
      Right fieldMaps ->
        let allSkills = rights (map fieldsToSkill fieldMaps)
         in pure $ case criteria.nameFilter of
              Nothing -> allSkills
              Just nameFilter -> filter (\s -> nameFilter `Text.isInfixOf` s.name) allSkills
