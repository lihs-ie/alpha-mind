module Domain.Insight.ActionSpec (spec) where

import Domain.Insight.Action (
  InsightActionError (..),
  checkMnpiFilter,
  mnpiSuspectedKeywords,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Domain.Insight.Action" $ do
  describe "mnpiSuspectedKeywords" $ do
    it "contains at least four keywords" $
      length mnpiSuspectedKeywords `shouldSatisfy` (>= 4)

  describe "checkMnpiFilter" $ do
    it "returns Right () for a clean comment" $
      checkMnpiFilter "通常の売買理由" `shouldBe` Right ()

    it "returns Right () for an empty comment" $
      checkMnpiFilter "" `shouldBe` Right ()

    it "detects 未公表 keyword" $
      checkMnpiFilter "未公表の情報を基に判断した" `shouldSatisfy` \case
        Left (MnpiSuspected keyword) -> keyword == "未公表"
        _ -> False

    it "detects insider keyword (case-insensitive)" $
      checkMnpiFilter "I have insider information" `shouldSatisfy` \case
        Left (MnpiSuspected _) -> True
        _ -> False

    it "detects 内部情報 keyword" $
      checkMnpiFilter "内部情報に基づく判断" `shouldSatisfy` \case
        Left (MnpiSuspected keyword) -> keyword == "内部情報"
        _ -> False

    it "detects 非公開 keyword" $
      checkMnpiFilter "非公開情報あり" `shouldSatisfy` \case
        Left (MnpiSuspected keyword) -> keyword == "非公開"
        _ -> False

    it "returns Right () for a comment about publicly disclosed information" $
      checkMnpiFilter "公開された決算資料を基に採択" `shouldBe` Right ()

    it "returns Right () for a comment with MANUAL_OPERATION reason" $
      checkMnpiFilter "根拠品質を確認済み" `shouldBe` Right ()
