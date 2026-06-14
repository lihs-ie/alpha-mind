module Domain.HypothesisOrchestration.CodeReferenceTemplate (
  -- * External entity types
  CodeReferenceTemplate (..),

  -- * Search criteria
  CodeReferenceTemplateSearchCriteria (..),
  emptyCodeReferenceTemplateSearchCriteria,

  -- * Repository Port (Must-22)
  CodeReferenceTemplateRepository (..),
) where

import Data.Text (Text)

-- ---------------------------------------------------------------------
-- External entity types
-- ---------------------------------------------------------------------

-- | CodeReferenceTemplate エンティティ（外部境界コンテキスト）。
data CodeReferenceTemplate = CodeReferenceTemplate
  { identifier :: Text
  , scope :: Text
  , content :: Text
  , version :: Text
  }
  deriving stock (Eq, Show)

-- | CodeReferenceTemplate 検索条件。
data CodeReferenceTemplateSearchCriteria = CodeReferenceTemplateSearchCriteria
  { scopeFilter :: Maybe Text
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

emptyCodeReferenceTemplateSearchCriteria :: CodeReferenceTemplateSearchCriteria
emptyCodeReferenceTemplateSearchCriteria =
  CodeReferenceTemplateSearchCriteria
    { scopeFilter = Nothing
    , limitCount = Nothing
    }

-- ---------------------------------------------------------------------
-- Repository Port (Must-22)
-- ---------------------------------------------------------------------

-- | Must-22: CodeReferenceTemplateRepository 型クラス Port（実装は infra 層）。
class (Monad m) => CodeReferenceTemplateRepository m where
  find :: Text -> m (Maybe CodeReferenceTemplate)
  findByScope :: Text -> m [CodeReferenceTemplate]
  search :: CodeReferenceTemplateSearchCriteria -> m [CodeReferenceTemplate]
