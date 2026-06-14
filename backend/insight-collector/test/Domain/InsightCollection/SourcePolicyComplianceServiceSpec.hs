module Domain.InsightCollection.SourcePolicyComplianceServiceSpec (spec) where

import Data.Either (isLeft, isRight)
import Domain.InsightCollection.Aggregate (
  GitHubConfig (..),
  SourceConfig (..),
  SourcePolicySnapshot (..),
  SourceType (..),
 )
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Domain.InsightCollection.SourcePolicyComplianceService (
  validateSourcePolicy,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- Helper to build a policy snapshot
mkPolicy :: SourceType -> Bool -> Bool -> SourcePolicySnapshot
mkPolicy sourceType enabled redistributionAllowed =
  SourcePolicySnapshot
    { sourceType = sourceType
    , enabled = enabled
    , termsVersion = "v1.0"
    , redistributionAllowed = redistributionAllowed
    , dailyQuota = Nothing
    , sourceConfig =
        GitHubSourceConfig
          GitHubConfig{personalAccessTokenSecretName = "secret/github-token"}
    }

xApproved :: SourcePolicySnapshot
xApproved = mkPolicy X True True

gitHubApproved :: SourcePolicySnapshot
gitHubApproved = mkPolicy GitHub True True

xDisabled :: SourcePolicySnapshot
xDisabled = mkPolicy X False True

youTubeNoRedistribution :: SourcePolicySnapshot
youTubeNoRedistribution = mkPolicy YouTube True False

spec :: Spec
spec =
  describe "Domain.InsightCollection.SourcePolicyComplianceService" $ do
    -- Must-18, Must-21, TST-IC-002: RULE-IC-002 — 未承認ソース判定テスト
    describe "validateSourcePolicy" $ do
      it "returns Right with approved policies when all sources are enabled and redistributionAllowed" $ do
        -- TST-IC-002: 承認済みソースのみ → Right
        validateSourcePolicy [xApproved, gitHubApproved] [X, GitHub]
          `shouldSatisfy` isRight

      it "returns Left ComplianceSourceUnapproved when source is disabled (enabled=false)" $ do
        -- Must-21: enabled=false → ComplianceSourceUnapproved
        validateSourcePolicy [xDisabled] [X]
          `shouldBe` Left ComplianceSourceUnapproved

      it "returns Left ComplianceSourceUnapproved when redistributionAllowed=false" $ do
        -- Must-21: redistributionAllowed=false → ComplianceSourceUnapproved
        validateSourcePolicy [youTubeNoRedistribution] [YouTube]
          `shouldBe` Left ComplianceSourceUnapproved

      it "returns Left when mixed approved and unapproved sources" $ do
        validateSourcePolicy [xApproved, xDisabled] [X]
          `shouldSatisfy` isLeft

      it "returns Right for empty requested source types" $ do
        validateSourcePolicy [xApproved] []
          `shouldSatisfy` isRight

      it "is pure — no IO involved" $ do
        -- 型検査がそのまま証明。validateSourcePolicy は Either ReasonCode [SourcePolicySnapshot] を返す純粋関数。
        let result = validateSourcePolicy [xApproved] [X]
        result `shouldSatisfy` isRight
