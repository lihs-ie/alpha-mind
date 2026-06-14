module Domain.OrderProposal.Specification.SignalIntegritySpecificationSpec (spec) where

import Domain.OrderProposal.Specification.SignalIntegritySpecification (isSatisfiedBy)
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
 )
import Test.Hspec (Spec, describe, it, shouldBe)

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

spec :: Spec
spec =
  describe "Domain.OrderProposal.Specification.SignalIntegritySpecification" $ do
    describe "isSatisfiedBy (MUST-17)" $ do
      it "returns True when all required fields are non-empty" $ do
        isSatisfiedBy validSnapshot `shouldBe` True

      it "MUST-17: returns False when signalVersion is empty" $ do
        isSatisfiedBy validSnapshot{signalVersion = ""} `shouldBe` False

      it "MUST-17: returns False when modelVersion is empty" $ do
        isSatisfiedBy validSnapshot{modelVersion = ""} `shouldBe` False

      it "MUST-17: returns False when featureVersion is empty" $ do
        isSatisfiedBy validSnapshot{featureVersion = ""} `shouldBe` False

      it "MUST-17: returns False when storagePath is empty" $ do
        isSatisfiedBy validSnapshot{storagePath = ""} `shouldBe` False

      it "does not fail for other field variants (degradationFlag, requiresComplianceReview)" $ do
        -- These fields don't affect SignalIntegritySpecification
        isSatisfiedBy validSnapshot{degradationFlag = Block, requiresComplianceReview = True} `shouldBe` True
