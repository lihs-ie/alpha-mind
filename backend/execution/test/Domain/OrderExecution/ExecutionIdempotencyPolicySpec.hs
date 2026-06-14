module Domain.OrderExecution.ExecutionIdempotencyPolicySpec (spec) where

import Data.Set qualified as Set
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution.Aggregate (OrderExecutionIdentifier (..))
import Domain.OrderExecution.ExecutionIdempotencyPolicy (isDuplicateDispatch)
import Test.Hspec (Spec, describe, it, shouldBe)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

identifierFor :: Integer -> OrderExecutionIdentifier
identifierFor = OrderExecutionIdentifier . mkULID

spec :: Spec
spec =
  describe "Domain.OrderExecution.ExecutionIdempotencyPolicy.isDuplicateDispatch (Must-16, RULE-EX-002)" $ do
    it "returns True when the identifier was already processed" $ do
      let processed = Set.fromList [identifierFor 1, identifierFor 2]
      isDuplicateDispatch processed (identifierFor 1) `shouldBe` True

    it "returns False for a fresh identifier" $ do
      let processed = Set.fromList [identifierFor 1, identifierFor 2]
      isDuplicateDispatch processed (identifierFor 3) `shouldBe` False

    it "returns False against an empty processed set" $ do
      isDuplicateDispatch Set.empty (identifierFor 1) `shouldBe` False
