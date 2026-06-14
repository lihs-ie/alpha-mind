module Domain.Hypothesis.ActionSpec (spec) where

import Domain.Hypothesis.Action (
  HypothesisTransitionError (..),
  validatePromote,
  validateReject,
  validateRetest,
 )
import Domain.Hypothesis.Record (HypothesisStatus (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = describe "Domain.Hypothesis.Action" $ do
  describe "validatePromote" $ do
    it "allows demo → live when mnpiSelfDeclared=true and no compliance review required" $
      validatePromote HypothesisStatusDemo (Just False) (Just True) `shouldBe` Right ()

    it "allows demo → live when compliance review flag is Nothing" $
      validatePromote HypothesisStatusDemo Nothing (Just True) `shouldBe` Right ()

    it "blocks promotion when requiresComplianceReview=true" $
      validatePromote HypothesisStatusDemo (Just True) (Just True)
        `shouldSatisfy` \case
          Left ComplianceReviewRequired -> True
          _ -> False

    it "blocks promotion when mnpiSelfDeclared=false" $
      validatePromote HypothesisStatusDemo (Just False) (Just False)
        `shouldSatisfy` \case
          Left MnpiSelfDeclarationMissing -> True
          _ -> False

    it "blocks promotion when mnpiSelfDeclared=Nothing" $
      validatePromote HypothesisStatusDemo (Just False) Nothing
        `shouldSatisfy` \case
          Left MnpiSelfDeclarationMissing -> True
          _ -> False

    it "rejects promotion from draft (invalid transition)" $
      validatePromote HypothesisStatusDraft (Just False) (Just True)
        `shouldSatisfy` \case
          Left (InvalidStateTransition HypothesisStatusDraft _) -> True
          _ -> False

    it "rejects promotion from live (terminal)" $
      validatePromote HypothesisStatusLive (Just False) (Just True)
        `shouldSatisfy` \case
          Left (InvalidStateTransition HypothesisStatusLive _) -> True
          _ -> False

    it "rejects promotion from rejected (terminal)" $
      validatePromote HypothesisStatusRejected (Just False) (Just True)
        `shouldSatisfy` \case
          Left (InvalidStateTransition HypothesisStatusRejected _) -> True
          _ -> False

  describe "validateReject" $ do
    it "allows demo → rejected" $
      validateReject HypothesisStatusDemo `shouldBe` Right ()

    it "rejects rejection from draft" $
      validateReject HypothesisStatusDraft
        `shouldSatisfy` \case
          Left (InvalidStateTransition HypothesisStatusDraft _) -> True
          _ -> False

    it "rejects rejection from live (terminal)" $
      validateReject HypothesisStatusLive
        `shouldSatisfy` \case
          Left (InvalidStateTransition HypothesisStatusLive _) -> True
          _ -> False

    it "rejects rejection from rejected (already terminal)" $
      validateReject HypothesisStatusRejected
        `shouldSatisfy` \case
          Left (InvalidStateTransition HypothesisStatusRejected _) -> True
          _ -> False

  describe "validateRetest" $ do
    it "allows retest from demo" $
      validateRetest HypothesisStatusDemo `shouldBe` Right ()

    it "allows retest from backtested" $
      validateRetest HypothesisStatusBacktested `shouldBe` Right ()

    it "rejects retest from draft" $
      validateRetest HypothesisStatusDraft
        `shouldSatisfy` \case
          Left (InvalidStateTransition HypothesisStatusDraft _) -> True
          _ -> False

    it "rejects retest from live (terminal)" $
      validateRetest HypothesisStatusLive
        `shouldSatisfy` \case
          Left (InvalidStateTransition HypothesisStatusLive _) -> True
          _ -> False

    it "rejects retest from rejected (terminal)" $
      validateRetest HypothesisStatusRejected
        `shouldSatisfy` \case
          Left (InvalidStateTransition HypothesisStatusRejected _) -> True
          _ -> False
