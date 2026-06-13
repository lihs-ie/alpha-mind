module Domain.MarketCollection.CollectionDispatchSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (MarketCollectionIdentifier (..))
import Domain.MarketCollection.CollectionDispatch (
  CollectionDispatch,
  DispatchDecision (..),
  DispatchStatus (..),
  PublishedEventType (..),
  markDispatchFailed,
  markDispatched,
  startDispatch,
 )
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

fixedTime2 :: UTCTime
fixedTime2 = UTCTime (fromGregorian 2026 1 16) 0

testIdentifier :: MarketCollectionIdentifier
testIdentifier = MarketCollectionIdentifier (mkULID 10)

testTrace :: Trace
testTrace = Trace (mkULID 200)

mkPendingDispatch :: CollectionDispatch
mkPendingDispatch = startDispatch testIdentifier testTrace

spec :: Spec
spec =
  describe "Domain.MarketCollection.CollectionDispatch" $ do
    -- Must-04: DispatchStatus 3値テスト
    describe "DispatchStatus" $ do
      it "has exactly Pending, Published, Failed" $ do
        Pending `shouldBe` Pending
        Published `shouldBe` Published
        Failed `shouldBe` Failed
        Pending `shouldNotBe` Published
        Published `shouldNotBe` Failed

    -- Must-09: DispatchDecision フィールドテスト
    describe "DispatchDecision" $ do
      it "holds dispatchStatus, publishedEvent, reasonCode" $ do
        let decision = DispatchDecision{dispatchStatus = Published, publishedEvent = Just MarketCollected, reasonCode = Nothing}
        decision.dispatchStatus `shouldBe` Published
        decision.publishedEvent `shouldBe` Just MarketCollected
        decision.reasonCode `shouldBe` Nothing

    -- Must-02: CollectionDispatch フィールドテスト
    describe "startDispatch" $ do
      it "creates a Pending dispatch with given identifier" $ do
        let dispatch = mkPendingDispatch
        dispatch.dispatchStatus `shouldBe` Pending
        dispatch.identifier `shouldBe` testIdentifier
        dispatch.processedAt `shouldBe` Nothing

      it "initializes dispatchDecision with Pending status" $ do
        let dispatch = mkPendingDispatch
        dispatch.dispatchDecision.dispatchStatus `shouldBe` Pending
        dispatch.dispatchDecision.publishedEvent `shouldBe` Nothing
        dispatch.dispatchDecision.reasonCode `shouldBe` Nothing

    -- Must-14: INV-DC-004 — 一方向遷移テスト
    describe "markDispatched (INV-DC-004)" $ do
      it "transitions Pending to Published" $ do
        markDispatched MarketCollected fixedTime mkPendingDispatch
          `shouldSatisfy` isRight

      it "sets publishedEvent and processedAt" $ do
        case markDispatched MarketCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right updated -> do
            updated.dispatchStatus `shouldBe` Published
            updated.dispatchDecision.publishedEvent `shouldBe` Just MarketCollected
            updated.processedAt `shouldBe` Just fixedTime

      it "rejects transition from Published state" $ do
        -- Must-14 受入条件: Published 状態からの遷移コマンドは Left DomainError を返す
        case markDispatched MarketCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right published ->
            markDispatched MarketCollected fixedTime2 published
              `shouldSatisfy` isLeft

      it "rejects transition from Failed state" $ do
        -- Must-14 受入条件: Failed 状態からの遷移コマンドは Left DomainError を返す
        case markDispatchFailed StateConflict fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right failed ->
            markDispatched MarketCollected fixedTime2 failed
              `shouldSatisfy` isLeft

    describe "markDispatchFailed (INV-DC-004)" $ do
      it "transitions Pending to Failed" $ do
        markDispatchFailed DataSchemaInvalid fixedTime mkPendingDispatch
          `shouldSatisfy` isRight

      it "sets reasonCode and processedAt" $ do
        case markDispatchFailed DataSchemaInvalid fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right updated -> do
            updated.dispatchStatus `shouldBe` Failed
            updated.dispatchDecision.reasonCode `shouldBe` Just DataSchemaInvalid
            updated.processedAt `shouldBe` Just fixedTime

      it "rejects transition from Published state" $ do
        case markDispatched MarketCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right published ->
            markDispatchFailed DataSchemaInvalid fixedTime2 published
              `shouldSatisfy` isLeft

    -- TST-DC-004: RULE-DC-004 — 冪等性テスト
    describe "TST-DC-004: idempotency (INV-DC-004)" $ do
      it "prevents re-dispatching an already Published dispatch" $ do
        case markDispatched MarketCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right published ->
            -- 再遷移は拒否される
            markDispatched MarketCollectFailed fixedTime2 published
              `shouldSatisfy` isLeft

    -- TST-DC-005: RULE-DC-005 — market.collected 発行制御テスト
    describe "TST-DC-005: dispatch only after collection success" $ do
      it "MarketCollected event type is represented correctly" $ do
        case markDispatched MarketCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right updated ->
            updated.dispatchDecision.publishedEvent `shouldBe` Just MarketCollected
