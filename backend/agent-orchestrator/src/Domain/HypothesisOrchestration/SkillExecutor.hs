module Domain.HypothesisOrchestration.SkillExecutor (
  -- * Port types
  SkillInput (..),
  SkillOutput (..),

  -- * Port (Must-33)
  SkillExecutor (..),
) where

import Data.Text (Text)
import Domain.HypothesisOrchestration.Error (DomainError)

-- ---------------------------------------------------------------------
-- Port Types
-- ---------------------------------------------------------------------

-- | Skill 実行入力。
data SkillInput = SkillInput
  { skillName :: Text
  , skillVersion :: Text
  , promptHash :: Text
  , contextPayload :: Text
  }
  deriving stock (Eq, Show)

-- | Skill 実行出力。
data SkillOutput = SkillOutput
  { generatedContent :: Text
  , llmModel :: Text
  , sourceEvidence :: [Text]
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Port / ACL (Must-33)
-- ---------------------------------------------------------------------

{- | Must-33: SkillExecutor ポートインターフェース（ドメイン層が依存する ACL インターフェース）。
実装はインフラ層の責務であり、このモジュールには含まない。
-}
class (Monad m) => SkillExecutor m where
  executeSkill :: SkillInput -> m (Either DomainError SkillOutput)
