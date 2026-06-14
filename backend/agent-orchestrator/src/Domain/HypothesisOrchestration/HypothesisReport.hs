module Domain.HypothesisOrchestration.HypothesisReport (
  -- * External entity types
  HypothesisReportIdentifier (..),
  HypothesisReport (..),

  -- * Repository Port (Must-24)
  HypothesisReportRepository (..),
) where

import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Domain.HypothesisOrchestration.Aggregate (HypothesisProposalIdentifier)

-- ---------------------------------------------------------------------
-- External entity types
-- ---------------------------------------------------------------------

-- | HypothesisReport 識別子型（ULID）。
newtype HypothesisReportIdentifier = HypothesisReportIdentifier {value :: ULID}
  deriving stock (Eq, Ord, Show)

-- | HypothesisReport エンティティ。
data HypothesisReport = HypothesisReport
  { identifier :: HypothesisReportIdentifier
  , proposal :: HypothesisProposalIdentifier
  -- ^ Must-10: proposal は HypothesisProposal の識別子参照
  , reportPath :: Text
  , llmModel :: Text
  , generatedAt :: UTCTime
  , content :: Text
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Repository Port (Must-24)
-- ---------------------------------------------------------------------

-- | Must-24: HypothesisReportRepository 型クラス Port（実装は infra 層）。
class (Monad m) => HypothesisReportRepository m where
  persist :: HypothesisReport -> m ()
  find :: HypothesisReportIdentifier -> m (Maybe HypothesisReport)
