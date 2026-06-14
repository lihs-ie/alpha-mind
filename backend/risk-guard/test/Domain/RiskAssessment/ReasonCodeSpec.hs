module Domain.RiskAssessment.ReasonCodeSpec (spec) where

import Domain.RiskAssessment.ReasonCode (
  OperatorActionReasonCode (..),
  ReasonCode (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe)

spec :: Spec
spec =
  describe "Domain.RiskAssessment.ReasonCode" $ do
    describe "ReasonCode" $ do
      it "has distinct values" $ do
        KillSwitchEnabled `shouldNotBe` RiskLimitExceeded
        RiskLimitExceeded `shouldNotBe` ComplianceRestrictedSymbol
        ComplianceRestrictedSymbol `shouldNotBe` ComplianceBlackoutActive
        ComplianceBlackoutActive `shouldNotBe` RiskEvaluationUnavailable
        RiskEvaluationUnavailable `shouldNotBe` IdempotencyDuplicateEvent

      it "supports equality" $ do
        KillSwitchEnabled `shouldBe` KillSwitchEnabled
        RiskLimitExceeded `shouldBe` RiskLimitExceeded
        ComplianceRestrictedSymbol `shouldBe` ComplianceRestrictedSymbol
        ComplianceBlackoutActive `shouldBe` ComplianceBlackoutActive
        RiskEvaluationUnavailable `shouldBe` RiskEvaluationUnavailable
        IdempotencyDuplicateEvent `shouldBe` IdempotencyDuplicateEvent

    -- TST-RG-009: identifier naming uses 'identifier' not 'stockId'/'Id'
    describe "OperatorActionReasonCode" $ do
      it "has distinct values" $ do
        ManualApproval `shouldNotBe` ManualRejection
        ManualRejection `shouldNotBe` ComplianceOverride
        ComplianceOverride `shouldNotBe` ManualApproval

      it "supports equality" $ do
        ManualApproval `shouldBe` ManualApproval
        ManualRejection `shouldBe` ManualRejection
        ComplianceOverride `shouldBe` ComplianceOverride
