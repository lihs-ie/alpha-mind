module Domain.HypothesisOrchestration.SkillRegistry (
  -- * External entity types
  SkillStatus (..),
  Skill (..),

  -- * Search criteria
  SkillSearchCriteria (..),
  emptySkillSearchCriteria,

  -- * Repository Port (Must-20)
  SkillRegistryRepository (..),
) where

import Data.Text (Text)

-- ---------------------------------------------------------------------
-- External entity types
-- ---------------------------------------------------------------------

-- | Skill の状態。
data SkillStatus
  = SkillActive
  | SkillDeprecated
  | SkillDraft
  deriving stock (Eq, Ord, Show)

-- | Skill エンティティ（外部境界コンテキスト）。
data Skill = Skill
  { identifier :: Text
  , name :: Text
  , version :: Text
  , status :: SkillStatus
  }
  deriving stock (Eq, Show)

-- | Skill 検索条件。
data SkillSearchCriteria = SkillSearchCriteria
  { nameFilter :: Maybe Text
  , statusFilter :: Maybe SkillStatus
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

emptySkillSearchCriteria :: SkillSearchCriteria
emptySkillSearchCriteria =
  SkillSearchCriteria
    { nameFilter = Nothing
    , statusFilter = Nothing
    , limitCount = Nothing
    }

-- ---------------------------------------------------------------------
-- Repository Port (Must-20)
-- ---------------------------------------------------------------------

-- | Must-20: SkillRegistryRepository 型クラス Port（実装は infra 層）。
class (Monad m) => SkillRegistryRepository m where
  find :: Text -> m (Maybe Skill)
  findByStatus :: SkillStatus -> m [Skill]
  search :: SkillSearchCriteria -> m [Skill]
