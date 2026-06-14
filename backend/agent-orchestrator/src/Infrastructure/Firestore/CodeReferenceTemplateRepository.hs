{-# LANGUAGE OverloadedRecordDot #-}

{- | Firestore implementation of 'CodeReferenceTemplateRepository'.

Must-08: find, findByScope, search implemented via injectable FirestoreTransport.
Must-09: markdownPath field absence → DomainError (MissingRequiredFields).

Collection: @code_reference_templates@
Document ID: template identifier text
-}
module Infrastructure.Firestore.CodeReferenceTemplateRepository (
  -- * Environment
  FirestoreCodeReferenceTemplateEnv (..),

  -- * Monad transformer
  FirestoreCodeReferenceTemplateRepositoryT (..),
  runFirestoreCodeReferenceTemplateRepositoryT,

  -- * Codec (exported for pure round-trip tests)
  templateToFields,
  fieldsToTemplate,
) where

import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Trans.Class (MonadTrans)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Either (rights)
import Data.HashMap.Strict qualified as HashMap
import Data.Maybe (fromMaybe)
import Data.Text (Text)
import Domain.HypothesisOrchestration.CodeReferenceTemplate (
  CodeReferenceTemplate (..),
  CodeReferenceTemplateRepository (..),
  CodeReferenceTemplateSearchCriteria (..),
 )
import Domain.HypothesisOrchestration.Error (DomainError (..))
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

codeReferenceTemplatesCollection :: CollectionName
codeReferenceTemplatesCollection = CollectionName "code_reference_templates"

defaultQueryLimit :: Int
defaultQueryLimit = 50

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype FirestoreCodeReferenceTemplateEnv = FirestoreCodeReferenceTemplateEnv
  { firestoreEnv :: FirestoreEnv
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype FirestoreCodeReferenceTemplateRepositoryT m a = FirestoreCodeReferenceTemplateRepositoryT
  { unFirestoreCodeReferenceTemplateRepositoryT :: ReaderT FirestoreCodeReferenceTemplateEnv m a
  }
  deriving newtype (Functor, Applicative, Monad, MonadIO, MonadTrans)

runFirestoreCodeReferenceTemplateRepositoryT ::
  FirestoreCodeReferenceTemplateEnv ->
  FirestoreCodeReferenceTemplateRepositoryT m a ->
  m a
runFirestoreCodeReferenceTemplateRepositoryT environment action =
  runReaderT (unFirestoreCodeReferenceTemplateRepositoryT action) environment

-- ---------------------------------------------------------------------------
-- Firestore codec
-- ---------------------------------------------------------------------------

{- | Encode a 'CodeReferenceTemplate' to Firestore field map.
The 'content' field is stored as @markdownPath@.
Exported for pure round-trip tests.
-}
templateToFields :: CodeReferenceTemplate -> HashMap.HashMap Text GogolFireStore.Value
templateToFields template =
  HashMap.fromList
    [ ("identifier", toValue template.identifier)
    , ("scope", toValue template.scope)
    , ("markdownPath", toValue template.content)
    , ("version", toValue template.version)
    ]

{- | Decode a Firestore field map to a 'CodeReferenceTemplate'.
Must-09: missing @markdownPath@ → 'Left (MissingRequiredFields ["markdownPath"] ResourceNotFound)'.
Exported for pure round-trip tests.
-}
fieldsToTemplate :: HashMap.HashMap Text GogolFireStore.Value -> Either DomainError CodeReferenceTemplate
fieldsToTemplate fields = do
  identifierValue <- liftTextError (requireField "identifier" fields)
  scopeValue <- liftTextError (requireField "scope" fields)
  contentValue <- case requireField "markdownPath" fields of
    Left _ -> Left (MissingRequiredFields ["markdownPath"] ResourceNotFound)
    Right v -> Right (v :: Text)
  versionValue <- liftTextError (requireField "version" fields)
  Right
    CodeReferenceTemplate
      { identifier = identifierValue
      , scope = scopeValue
      , content = contentValue
      , version = versionValue
      }

liftTextError :: Either Text a -> Either DomainError a
liftTextError (Right x) = Right x
liftTextError (Left message) = Left (MissingRequiredFields [message] ResourceNotFound)

-- ---------------------------------------------------------------------------
-- CodeReferenceTemplateRepository instance (Must-08)
-- ---------------------------------------------------------------------------

instance CodeReferenceTemplateRepository (FirestoreCodeReferenceTemplateRepositoryT IO) where
  find templateIdentifier = FirestoreCodeReferenceTemplateRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportGetDocument} = environment.firestoreEnv.firestoreExecute
    result <- liftIO $ transportGetDocument codeReferenceTemplatesCollection (DocumentId templateIdentifier)
    case result of
      Left _ -> pure Nothing
      Right Nothing -> pure Nothing
      Right (Just fieldMap) ->
        pure $ case fieldsToTemplate fieldMap of
          Left _ -> Nothing
          Right template -> Just template

  findByScope scopeText = FirestoreCodeReferenceTemplateRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        -- Composite index: scope ASC, updatedAt DESC (Must-08 spec note)
        filters = [QueryFilterEqual{filterField = "scope", filterValue = toValue scopeText}]
        orders = [QueryOrder{orderField = "scope", orderDirection = Ascending}]
    result <- liftIO $ transportRunQuery codeReferenceTemplatesCollection filters orders defaultQueryLimit
    case result of
      Left _ -> pure []
      Right fieldMaps -> pure (rights (map fieldsToTemplate fieldMaps))

  search criteria = FirestoreCodeReferenceTemplateRepositoryT $ do
    environment <- ask
    let FirestoreTransport{transportRunQuery} = environment.firestoreEnv.firestoreExecute
        limitValue = fromMaybe defaultQueryLimit criteria.limitCount
        scopeFilters = case criteria.scopeFilter of
          Nothing -> []
          Just s -> [QueryFilterEqual{filterField = "scope", filterValue = toValue s}]
        orders = [QueryOrder{orderField = "scope", orderDirection = Ascending}]
    result <- liftIO $ transportRunQuery codeReferenceTemplatesCollection scopeFilters orders limitValue
    case result of
      Left _ -> pure []
      Right fieldMaps -> pure (rights (map fieldsToTemplate fieldMaps))
