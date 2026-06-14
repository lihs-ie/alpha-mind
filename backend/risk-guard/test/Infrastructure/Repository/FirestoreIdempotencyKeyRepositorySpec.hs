{- | Pure unit tests for FirestoreIdempotencyKeyRepository logic.

TST-INFRA-008: isAlreadyProcessed returns True for processedAt = Just _, False for Nothing.
-}
module Infrastructure.Repository.FirestoreIdempotencyKeyRepositorySpec (spec) where

import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Infrastructure.Repository.FirestoreIdempotencyKeyRepository (
  IdempotencyProcessedRecord (..),
  isAlreadyProcessed,
 )
import Test.Hspec (Spec, describe, it, shouldBe)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = describe "Infrastructure.Repository.FirestoreIdempotencyKeyRepository" $ do
  describe "TST-INFRA-008: isAlreadyProcessed" $ do
    it "returns False when no record exists (Nothing)" $ do
      isAlreadyProcessed Nothing `shouldBe` False

    it "returns False when record exists but processedAt is Nothing (reserved, not complete)" $ do
      let record = IdempotencyProcessedRecord{processedAt = Nothing}
      isAlreadyProcessed (Just record) `shouldBe` False

    it "returns True when processedAt is Just _ (event already processed)" $ do
      let record = IdempotencyProcessedRecord{processedAt = Just fixedTime}
      isAlreadyProcessed (Just record) `shouldBe` True
