module Domain.OrderProposal.Service.ProposalEligibilityPolicySpec (spec) where

import Data.Either (isLeft, isRight)
import Domain.OrderProposal.Error (DomainError (..))
import Domain.OrderProposal.Service.ProposalEligibilityPolicy (checkEligibility)
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
 )
import Test.Hspec (Spec, describe, expectationFailure, it, shouldBe, shouldSatisfy)

-- ---------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------

validSnapshot :: SignalSnapshot
validSnapshot =
  SignalSnapshot
    { signalVersion = "v1.0"
    , modelVersion = "m2.0"
    , featureVersion = "f3.0"
    , storagePath = "gs://bucket/signals/2026-01-15.parquet"
    , degradationFlag = Normal
    , requiresComplianceReview = False
    }

-- ---------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------

spec :: Spec
spec =
  describe "Domain.OrderProposal.Service.ProposalEligibilityPolicy" $ do
    describe "checkEligibility (MUST-14, MUST-15)" $ do
      it "returns Right () for a fully valid SignalSnapshot" $ do
        checkEligibility validSnapshot `shouldSatisfy` isRight

      -- MUST-14: Required field validation (RULE-PP-001)
      it "MUST-14: returns Left when signalVersion is empty (RULE-PP-001)" $ do
        checkEligibility validSnapshot{signalVersion = ""} `shouldSatisfy` isLeft

      it "MUST-14: returns Left when modelVersion is empty (RULE-PP-001)" $ do
        checkEligibility validSnapshot{modelVersion = ""} `shouldSatisfy` isLeft

      it "MUST-14: returns Left when featureVersion is empty (RULE-PP-001)" $ do
        checkEligibility validSnapshot{featureVersion = ""} `shouldSatisfy` isLeft

      it "MUST-14: returns Left when storagePath is empty (RULE-PP-001)" $ do
        checkEligibility validSnapshot{storagePath = ""} `shouldSatisfy` isLeft

      -- MUST-15: Compliance review gate (RULE-PP-002)
      it "MUST-15: returns Left ComplianceReviewRequired when requiresComplianceReview is True (RULE-PP-002)" $ do
        checkEligibility validSnapshot{requiresComplianceReview = True}
          `shouldBe` Left ComplianceReviewRequired

      it "MUST-15: checks integrity before compliance (empty fields take precedence)" $ do
        -- When both integrity fails AND compliance flag is set, MissingRequiredFields is returned first
        let snapshot = validSnapshot{signalVersion = "", requiresComplianceReview = True}
        let result = checkEligibility snapshot
        case result of
          Left (MissingRequiredFields _) -> pure ()
          other -> expectationFailure ("Expected MissingRequiredFields, got: " ++ show other)

      it "degradationFlag Block does not affect eligibility check by itself" $ do
        -- degradationFlag is not checked by ProposalEligibilityPolicy (only compliance + integrity)
        checkEligibility validSnapshot{degradationFlag = Block} `shouldSatisfy` isRight
