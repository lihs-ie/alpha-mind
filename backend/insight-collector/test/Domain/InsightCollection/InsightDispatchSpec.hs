module Domain.InsightCollection.InsightDispatchSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (InsightCollectionIdentifier (..))
import Domain.InsightCollection.InsightDispatch (
  DispatchDecision (..),
  DispatchStatus (..),
  InsightDispatch,
  PublishedEventType (..),
  markDispatchFailed,
  markDispatched,
  startDispatch,
 )
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

fixedTime2 :: UTCTime
fixedTime2 = UTCTime (fromGregorian 2026 1 16) 0

testIdentifier :: InsightCollectionIdentifier
testIdentifier = InsightCollectionIdentifier (mkULID 10)

testTrace :: Trace
testTrace = Trace (mkULID 200)

mkPendingDispatch :: InsightDispatch
mkPendingDispatch = startDispatch testIdentifier testTrace

spec :: Spec
spec =
  describe "Domain.InsightCollection.InsightDispatch" $ do
    -- Must-2: DispatchStatus 3値テスト
    describe "DispatchStatus" $ do
      it "has exactly Pending, Published, Failed" $ do
        Pending `shouldBe` Pending
        Published `shouldBe` Published
        Failed `shouldBe` Failed
        Pending `shouldNotBe` Published
        Published `shouldNotBe` Failed

    -- Must-9: DispatchDecision フィールドテスト
    describe "DispatchDecision" $ do
      it "holds dispatchStatus, publishedEvent, reasonCode" $ do
        let decision =
              DispatchDecision
                { dispatchStatus = Published
                , publishedEvent = Just InsightCollected
                , reasonCode = Nothing
                }
        decision.dispatchStatus `shouldBe` Published
        decision.publishedEvent `shouldBe` Just InsightCollected
        decision.reasonCode `shouldBe` Nothing

    -- Must-2: InsightDispatch フィールドテスト
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

    -- Must-25 INV-IC-004: 一方向遷移テスト
    describe "markDispatched (INV-IC-004)" $ do
      it "transitions Pending to Published" $ do
        markDispatched InsightCollected fixedTime mkPendingDispatch
          `shouldSatisfy` isRight

      it "sets publishedEvent and processedAt" $ do
        case markDispatched InsightCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right updated -> do
            updated.dispatchStatus `shouldBe` Published
            updated.dispatchDecision.publishedEvent `shouldBe` Just InsightCollected
            updated.processedAt `shouldBe` Just fixedTime

      it "returns idempotent Right when already Published (INV-IC-004)" $ do
        case markDispatched InsightCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right published ->
            markDispatched InsightCollected fixedTime2 published
              `shouldSatisfy` isRight

      it "rejects transition from Failed state" $ do
        case markDispatchFailed StateConflict fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right failed ->
            markDispatched InsightCollected fixedTime2 failed
              `shouldSatisfy` isLeft

    describe "markDispatchFailed (INV-IC-004)" $ do
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
        case markDispatched InsightCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right published ->
            markDispatchFailed DataSchemaInvalid fixedTime2 published
              `shouldSatisfy` isLeft

    -- Must-25 TST-IC-004: 冪等性テスト (INV-IC-004: 同一identifierは1回のみpublished → 冪等扱い)
    describe "TST-IC-004: idempotency (INV-IC-004)" $ do
      it "returns Right (same state) when re-dispatching an already Published dispatch (idempotent)" $ do
        case markDispatched InsightCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right published ->
            markDispatched InsightCollectFailed fixedTime2 published
              `shouldSatisfy` isRight

      it "Published state is preserved unchanged on idempotent re-dispatch" $ do
        case markDispatched InsightCollected fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right published ->
            case markDispatched InsightCollectFailed fixedTime2 published of
              Left failure -> fail ("Expected Right (idempotent): " ++ show failure)
              Right result -> result.dispatchStatus `shouldBe` Published

    -- TST-IC-004: dispatch event type distinction
    describe "TST-IC-004: dispatch event types" $ do
      it "InsightCollected and InsightCollectFailed are distinct" $ do
        InsightCollected `shouldNotBe` InsightCollectFailed

      it "marks InsightCollectFailed correctly" $ do
        case markDispatched InsightCollectFailed fixedTime mkPendingDispatch of
          Left failure -> fail ("Unexpected Left: " ++ show failure)
          Right updated ->
            updated.dispatchDecision.publishedEvent `shouldBe` Just InsightCollectFailed
