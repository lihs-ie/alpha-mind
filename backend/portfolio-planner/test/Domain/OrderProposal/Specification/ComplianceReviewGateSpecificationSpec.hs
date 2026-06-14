module Domain.OrderProposal.Specification.ComplianceReviewGateSpecificationSpec (spec) where

import Domain.OrderProposal.Specification.ComplianceReviewGateSpecification (isSatisfiedBy)
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe)

baseSnapshot :: SignalSnapshot
baseSnapshot =
  SignalSnapshot
    { signalVersion = "v1.0"
    , modelVersion = "m2.0"
    , featureVersion = "f3.0"
    , storagePath = "gs://bucket/signals/2026-01-15.parquet"
    , degradationFlag = Normal
    , requiresComplianceReview = False
    }

spec :: Spec
spec =
  describe "Domain.OrderProposal.Specification.ComplianceReviewGateSpecification" $ do
    describe "isSatisfiedBy (MUST-18)" $ do
      it "returns True when requiresComplianceReview is False" $ do
        isSatisfiedBy baseSnapshot{requiresComplianceReview = False} `shouldBe` True

      it "MUST-18: returns False when requiresComplianceReview is True" $ do
        isSatisfiedBy baseSnapshot{requiresComplianceReview = True} `shouldBe` False

      it "is independent of degradationFlag value" $ do
        isSatisfiedBy baseSnapshot{degradationFlag = Block, requiresComplianceReview = False} `shouldBe` True
        isSatisfiedBy baseSnapshot{degradationFlag = Warn, requiresComplianceReview = True} `shouldBe` False
