module Domain.HypothesisOrchestration.InstructionProfile (
  -- * External entity types
  InstructionProfile (..),

  -- * Search criteria
  InstructionProfileSearchCriteria (..),
  emptyInstructionProfileSearchCriteria,

  -- * Repository Port (Must-21)
  InstructionProfileRepository (..),
) where

import Data.Text (Text)

-- ---------------------------------------------------------------------
-- External entity types
-- ---------------------------------------------------------------------

-- | InstructionProfile エンティティ（外部境界コンテキスト）。
data InstructionProfile = InstructionProfile
  { identifier :: Text
  , name :: Text
  , version :: Text
  , content :: Text
  }
  deriving stock (Eq, Show)

-- | InstructionProfile 検索条件。
data InstructionProfileSearchCriteria = InstructionProfileSearchCriteria
  { nameFilter :: Maybe Text
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

emptyInstructionProfileSearchCriteria :: InstructionProfileSearchCriteria
emptyInstructionProfileSearchCriteria =
  InstructionProfileSearchCriteria
    { nameFilter = Nothing
    , limitCount = Nothing
    }

-- ---------------------------------------------------------------------
-- Repository Port (Must-21)
-- ---------------------------------------------------------------------

-- | Must-21: InstructionProfileRepository 型クラス Port（実装は infra 層）。
class (Monad m) => InstructionProfileRepository m where
  find :: Text -> m (Maybe InstructionProfile)
  findByVersion :: Text -> m (Maybe InstructionProfile)
  search :: InstructionProfileSearchCriteria -> m [InstructionProfile]
