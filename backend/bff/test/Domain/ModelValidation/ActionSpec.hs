module Domain.ModelValidation.ActionSpec (spec) where

import Domain.ModelValidation.Action (
  ModelValidationTransitionError (..),
  validateApprove,
  validateReject,
 )
import Domain.ModelValidation.Record (ModelValidationStatus (..))
import Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Domain.ModelValidation.Action" $ do
  describe "validateApprove" $ do
    it "returns Right () for candidate status without compliance review" $ do
      validateApprove ModelValidationStatusCandidate Nothing
        `shouldBe` Right ()

    it "returns Right () for candidate status with requiresComplianceReview=false" $ do
      validateApprove ModelValidationStatusCandidate (Just False)
        `shouldBe` Right ()

    it "returns Left ComplianceReviewRequired when requiresComplianceReview=true" $ do
      validateApprove ModelValidationStatusCandidate (Just True)
        `shouldBe` Left ComplianceReviewRequired

    it "returns Left InvalidStateTransition for approved status" $ do
      validateApprove ModelValidationStatusApproved Nothing
        `shouldBe` Left (InvalidStateTransition ModelValidationStatusApproved "approve")

    it "returns Left InvalidStateTransition for rejected status" $ do
      validateApprove ModelValidationStatusRejected Nothing
        `shouldBe` Left (InvalidStateTransition ModelValidationStatusRejected "approve")

  describe "validateReject" $ do
    it "returns Right () for candidate status" $ do
      validateReject ModelValidationStatusCandidate
        `shouldBe` Right ()

    it "returns Left InvalidStateTransition for approved status" $ do
      validateReject ModelValidationStatusApproved
        `shouldBe` Left (InvalidStateTransition ModelValidationStatusApproved "reject")

    it "returns Left InvalidStateTransition for rejected status" $ do
      validateReject ModelValidationStatusRejected
        `shouldBe` Left (InvalidStateTransition ModelValidationStatusRejected "reject")
