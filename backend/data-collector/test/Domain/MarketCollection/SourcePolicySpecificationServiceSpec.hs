module Domain.MarketCollection.SourcePolicySpecificationServiceSpec (spec) where

import Data.Either (isLeft, isRight)
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Domain.MarketCollection.SourcePolicySpecificationService (
  ApprovedSourceSpecification (..),
  DataSourceName (..),
  validateSourcePolicy,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

jQuantsSource :: DataSourceName
jQuantsSource = DataSourceName "J-Quants"

alpacaSource :: DataSourceName
alpacaSource = DataSourceName "Alpaca"

unapprovedSource :: DataSourceName
unapprovedSource = DataSourceName "UnknownSource"

approvedSpec :: ApprovedSourceSpecification
approvedSpec =
  ApprovedSourceSpecification
    { approvedSources = [jQuantsSource, alpacaSource]
    }

spec :: Spec
spec =
  describe "Domain.MarketCollection.SourcePolicySpecificationService" $ do
    -- Must-17, TST-DC-002: RULE-DC-002 — 未承認ソース判定テスト
    describe "validateSourcePolicy" $ do
      it "returns Right () when all sources are approved" $ do
        validateSourcePolicy approvedSpec [jQuantsSource, alpacaSource]
          `shouldSatisfy` isRight

      it "returns Left ComplianceSourceUnapproved when any source is unapproved" $ do
        -- TST-DC-002 受入条件: 未承認ソースで COMPLIANCE_SOURCE_UNAPPROVED
        validateSourcePolicy approvedSpec [unapprovedSource]
          `shouldBe` Left ComplianceSourceUnapproved

      it "returns Left when mixed approved and unapproved sources" $ do
        validateSourcePolicy approvedSpec [jQuantsSource, unapprovedSource]
          `shouldSatisfy` isLeft

      it "returns Right () for empty source list" $ do
        validateSourcePolicy approvedSpec []
          `shouldSatisfy` isRight

      it "is pure — no IO involved" $ do
        -- 型検査がそのまま証明。validateSourcePolicy は Either ReasonCode () を返す純粋関数。
        let result = validateSourcePolicy approvedSpec [jQuantsSource]
        result `shouldBe` Right ()
