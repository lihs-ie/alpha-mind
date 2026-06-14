module Domain.HypothesisOrchestration.GenerationContextResolutionPolicySpec (spec) where

import Data.Either (isLeft, isRight)
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.GenerationContextResolutionPolicy (
  GenerationContextResolutionPolicy (..),
  ProfileResolutionInput (..),
  SkillResolutionInput (..),
  TemplateResolutionInput (..),
  resolveGenerationContext,
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

testPolicy :: GenerationContextResolutionPolicy
testPolicy = GenerationContextResolutionPolicy{requiredTemplateScopes = ["hypothesis-template"]}

availableSkill :: SkillResolutionInput
availableSkill =
  SkillResolutionInput
    { skillName = "hypothesis-skill"
    , skillVersion = "1.0.0"
    , available = True
    }

unavailableSkill :: SkillResolutionInput
unavailableSkill =
  SkillResolutionInput
    { skillName = "hypothesis-skill"
    , skillVersion = "1.0.0"
    , available = False
    }

availableProfile :: ProfileResolutionInput
availableProfile =
  ProfileResolutionInput
    { profileName = "default-profile"
    , profileVersion = "2.0.0"
    , available = True
    }

unavailableProfile :: ProfileResolutionInput
unavailableProfile =
  ProfileResolutionInput
    { profileName = "default-profile"
    , profileVersion = "2.0.0"
    , available = False
    }

availableTemplate :: TemplateResolutionInput
availableTemplate =
  TemplateResolutionInput
    { templateScope = "hypothesis-template"
    , available = True
    }

unavailableTemplate :: TemplateResolutionInput
unavailableTemplate =
  TemplateResolutionInput
    { templateScope = "hypothesis-template"
    , available = False
    }

wrongScopeTemplate :: TemplateResolutionInput
wrongScopeTemplate =
  TemplateResolutionInput
    { templateScope = "wrong-scope"
    , available = True
    }

spec :: Spec
spec =
  describe "Domain.HypothesisOrchestration.GenerationContextResolutionPolicy (Must-26)" $ do
    -- Must-26: すべて利用可能な場合のテスト
    describe "resolveGenerationContext" $ do
      it "returns Right () when all resources are available (Must-26)" $ do
        resolveGenerationContext testPolicy availableSkill availableProfile availableTemplate
          `shouldSatisfy` isRight

      -- Must-41 RULE-AO-002: Skill 解決失敗時は RESOURCE_NOT_FOUND
      it "returns RESOURCE_NOT_FOUND when skill is unavailable (Must-41 RULE-AO-002)" $ do
        let result = resolveGenerationContext testPolicy unavailableSkill availableProfile availableTemplate
        result `shouldSatisfy` isLeft
        case result of
          Left (InvariantViolation _ _ ResourceNotFound) -> pure ()
          Left other -> fail ("Expected RESOURCE_NOT_FOUND, got: " ++ show other)
          Right _ -> fail "Expected Left"

      -- Must-41: Profile 解決失敗時は RESOURCE_NOT_FOUND
      it "returns RESOURCE_NOT_FOUND when profile is unavailable (Must-41)" $ do
        let result = resolveGenerationContext testPolicy availableSkill unavailableProfile availableTemplate
        result `shouldSatisfy` isLeft
        case result of
          Left (InvariantViolation _ _ ResourceNotFound) -> pure ()
          Left other -> fail ("Expected RESOURCE_NOT_FOUND, got: " ++ show other)
          Right _ -> fail "Expected Left"

      -- Must-41: Template 解決失敗時は RESOURCE_NOT_FOUND
      it "returns RESOURCE_NOT_FOUND when template is unavailable (Must-41)" $ do
        let result = resolveGenerationContext testPolicy availableSkill availableProfile unavailableTemplate
        result `shouldSatisfy` isLeft
        case result of
          Left (InvariantViolation _ _ ResourceNotFound) -> pure ()
          Left other -> fail ("Expected RESOURCE_NOT_FOUND, got: " ++ show other)
          Right _ -> fail "Expected Left"

      -- Template scope が policy の required scope と一致しない場合
      it "returns RESOURCE_NOT_FOUND when template scope does not match required (Must-41)" $ do
        let result = resolveGenerationContext testPolicy availableSkill availableProfile wrongScopeTemplate
        result `shouldSatisfy` isLeft
        case result of
          Left (InvariantViolation _ _ ResourceNotFound) -> pure ()
          Left other -> fail ("Expected RESOURCE_NOT_FOUND, got: " ++ show other)
          Right _ -> fail "Expected Left"

      -- IO を含まないことの確認（純粋関数であること）
      it "is a pure function (no IO dependency)" $ do
        let result1 = resolveGenerationContext testPolicy availableSkill availableProfile availableTemplate
        let result2 = resolveGenerationContext testPolicy availableSkill availableProfile availableTemplate
        result1 `shouldBe` result2
