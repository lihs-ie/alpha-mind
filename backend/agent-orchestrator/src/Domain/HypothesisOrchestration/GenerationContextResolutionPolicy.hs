module Domain.HypothesisOrchestration.GenerationContextResolutionPolicy (
  -- * Policy input types
  SkillResolutionInput (..),
  ProfileResolutionInput (..),
  TemplateResolutionInput (..),

  -- * Policy
  GenerationContextResolutionPolicy (..),
  resolveGenerationContext,
) where

import Data.Text (Text)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))

-- ---------------------------------------------------------------------
-- Policy Input Types
-- ---------------------------------------------------------------------

-- | Skill 解決入力。
data SkillResolutionInput = SkillResolutionInput
  { skillName :: Text
  , skillVersion :: Text
  , available :: Bool
  }
  deriving stock (Eq, Show)

-- | 指示書（InstructionProfile）解決入力。
data ProfileResolutionInput = ProfileResolutionInput
  { profileName :: Text
  , profileVersion :: Text
  , available :: Bool
  }
  deriving stock (Eq, Show)

-- | コードリファレンステンプレート解決入力。
data TemplateResolutionInput = TemplateResolutionInput
  { templateScope :: Text
  , available :: Bool
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Policy (Must-26)
-- ---------------------------------------------------------------------

{- | Must-26: GenerationContextResolutionPolicy — 純粋関数、IO非依存。
Skill/指示書/テンプレートの解決可否を判定する。
Must-41 RULE-AO-002: 解決失敗時は RESOURCE_NOT_FOUND を reasonCode とするドメインエラーを返す。
-}
newtype GenerationContextResolutionPolicy = GenerationContextResolutionPolicy
  { requiredTemplateScopes :: [Text]
  }
  deriving stock (Eq, Show)

{- | Must-26: Skill/指示書/テンプレートすべてが利用可能かを検証する純粋関数。
解決失敗時は Left (InvariantViolation ... RESOURCE_NOT_FOUND) を返す（RULE-AO-002）。
-}
resolveGenerationContext ::
  GenerationContextResolutionPolicy ->
  SkillResolutionInput ->
  ProfileResolutionInput ->
  TemplateResolutionInput ->
  Either DomainError ()
resolveGenerationContext policy skillInput profileInput templateInput =
  let missingResources =
        ["skill:" <> skillInput.skillVersion | not skillInput.available]
          ++ ["profile:" <> profileInput.profileVersion | not profileInput.available]
          ++ [ "template:" <> templateInput.templateScope
             | not templateInput.available
                 || templateInput.templateScope `notElem` policy.requiredTemplateScopes
             ]
   in case missingResources of
        [] -> Right ()
        resources ->
          Left
            ( InvariantViolation
                "GenerationContext"
                ("Resources not found: " <> mconcat resources)
                ResourceNotFound
            )
