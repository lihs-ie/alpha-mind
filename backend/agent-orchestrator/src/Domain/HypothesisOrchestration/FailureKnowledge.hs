module Domain.HypothesisOrchestration.FailureKnowledge (
  -- * External entity types
  FailureKnowledgeIdentifier (..),
  FailureKnowledge (..),

  -- * Search criteria
  FailureKnowledgeSearchCriteria (..),
  emptyFailureKnowledgeSearchCriteria,

  -- * Repository Port (Must-23)
  FailureKnowledgeRepository (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode)

-- ---------------------------------------------------------------------
-- External entity types
-- ---------------------------------------------------------------------

-- | FailureKnowledge 識別子型（ULID）。
newtype FailureKnowledgeIdentifier = FailureKnowledgeIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- | FailureKnowledge エンティティ。
data FailureKnowledge = FailureKnowledge
  { identifier :: FailureKnowledgeIdentifier
  , reasonCode :: ReasonCode
  , summary :: Text
  , markdownSummary :: Text
  , similarityHash :: Text
  , recordedAt :: UTCTime
  }
  deriving stock (Eq, Show)

-- | FailureKnowledge 検索条件。
data FailureKnowledgeSearchCriteria = FailureKnowledgeSearchCriteria
  { reasonCodeFilter :: Maybe ReasonCode
  , similarityHashFilter :: Maybe Text
  , limitCount :: Maybe Int
  }
  deriving stock (Eq, Show)

emptyFailureKnowledgeSearchCriteria :: FailureKnowledgeSearchCriteria
emptyFailureKnowledgeSearchCriteria =
  FailureKnowledgeSearchCriteria
    { reasonCodeFilter = Nothing
    , similarityHashFilter = Nothing
    , limitCount = Nothing
    }

-- ---------------------------------------------------------------------
-- Repository Port (Must-23)
-- ---------------------------------------------------------------------

-- | Must-23: FailureKnowledgeRepository 型クラス Port（実装は infra 層）。
class (Monad m) => FailureKnowledgeRepository m where
  find :: FailureKnowledgeIdentifier -> m (Maybe FailureKnowledge)
  findByReasonCode :: ReasonCode -> m [FailureKnowledge]
  search :: FailureKnowledgeSearchCriteria -> m [FailureKnowledge]
  persist :: FailureKnowledge -> m ()
