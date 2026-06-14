module Domain.HypothesisOrchestration.OrchestrationDispatchSpec (spec) where

import Data.Either (isLeft, isRight)
import Data.Time (UTCTime (..))
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.OrchestrationDispatch (
  DispatchStatus (..),
  OrchestrationDispatch,
  OrchestrationDispatchIdentifier (..),
  markDuplicate,
  markFailed,
  markPublished,
  startDispatch,
 )
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (
  DispatchDecision,
  PublishedEventType (..),
  SourceEventSnapshot,
  SourceEventType (..),
  mkDispatchDecision,
  mkSourceEventSnapshot,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)

mkULID :: Integer -> ULID
mkULID n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

fixedTime2 :: UTCTime
fixedTime2 = UTCTime (fromGregorian 2026 1 16) 0

testIdentifier :: OrchestrationDispatchIdentifier
testIdentifier = OrchestrationDispatchIdentifier (mkULID 10)

testTrace :: Trace
testTrace = Trace (mkULID 200)

mkTestSnapshot :: SourceEventSnapshot
mkTestSnapshot =
  case mkSourceEventSnapshot "event-001" InsightCollected fixedTime "trace-001" "{}" of
    Right snapshot -> snapshot
    Left mkSnapshotError -> error (show mkSnapshotError)

mkPendingDispatch :: OrchestrationDispatch
mkPendingDispatch =
  let snapshot = mkTestSnapshot
   in startDispatch testIdentifier snapshot InsightCollected testTrace

testDecision :: DispatchDecision
testDecision = mkDispatchDecision HypothesisProposed False

spec :: Spec
spec =
  describe "Domain.HypothesisOrchestration.OrchestrationDispatch" $ do
    -- Must-36: 識別子型テスト
    describe "OrchestrationDispatchIdentifier (Must-36)" $ do
      it "supports equality" $ do
        OrchestrationDispatchIdentifier (mkULID 10) `shouldBe` OrchestrationDispatchIdentifier (mkULID 10)
        OrchestrationDispatchIdentifier (mkULID 10) `shouldNotBe` OrchestrationDispatchIdentifier (mkULID 20)

    -- Must-07: DispatchStatus テスト
    describe "DispatchStatus (Must-07)" $ do
      it "has exactly Pending, Published, DispatchFailed, Duplicate" $ do
        Pending `shouldBe` Pending
        Published `shouldBe` Published
        DispatchFailed `shouldBe` DispatchFailed
        Duplicate `shouldBe` Duplicate
        Pending `shouldNotBe` Published
        Published `shouldNotBe` DispatchFailed
        DispatchFailed `shouldNotBe` Duplicate

    -- Must-06 / Must-09: startDispatch テスト
    describe "startDispatch (Must-06, Must-09)" $ do
      it "creates Pending dispatch with given identifier" $ do
        let dispatch = mkPendingDispatch
        dispatch.dispatchStatus `shouldBe` Pending
        dispatch.identifier `shouldBe` testIdentifier
        dispatch.publishedEvent `shouldBe` Nothing
        dispatch.hypothesis `shouldBe` Nothing
        dispatch.reasonCode `shouldBe` Nothing
        dispatch.processedAt `shouldBe` Nothing

      it "holds sourceEventType" $ do
        let dispatch = mkPendingDispatch
        dispatch.sourceEventType `shouldBe` InsightCollected

    -- Must-08 INV-AO-004: markPublished テスト
    describe "markPublished INV-AO-004 (Must-08)" $ do
      it "transitions Pending to Published with publishedEvent" $ do
        markPublished HypothesisProposed testDecision "hypothesis-ref-001" fixedTime2 mkPendingDispatch
          `shouldSatisfy` isRight

      it "sets publishedEvent and hypothesis reference" $ do
        case markPublished HypothesisProposed testDecision "hypothesis-ref-001" fixedTime2 mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right updated -> do
            updated.dispatchStatus `shouldBe` Published
            updated.publishedEvent `shouldBe` Just HypothesisProposed
            updated.hypothesis `shouldBe` Just "hypothesis-ref-001"
            updated.processedAt `shouldBe` Just fixedTime2

      it "rejects transition from Published state (INV-AO-004)" $ do
        case markPublished HypothesisProposed testDecision "hyp-ref" fixedTime mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right published ->
            markPublished HypothesisProposalFailed testDecision "hyp-ref-2" fixedTime2 published
              `shouldSatisfy` isLeft

      it "rejects transition from DispatchFailed state" $ do
        case markFailed DependencyTimeout 0 fixedTime mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right failed ->
            markPublished HypothesisProposed testDecision "hyp-ref" fixedTime2 failed
              `shouldSatisfy` isLeft

      it "rejects transition from Duplicate state" $ do
        case markDuplicate fixedTime mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right duplicated ->
            markPublished HypothesisProposed testDecision "hyp-ref" fixedTime2 duplicated
              `shouldSatisfy` isLeft

    -- markDuplicate テスト
    describe "markDuplicate" $ do
      it "transitions Pending to Duplicate" $ do
        markDuplicate fixedTime2 mkPendingDispatch `shouldSatisfy` isRight

      it "sets IdempotencyDuplicateEvent reasonCode" $ do
        case markDuplicate fixedTime2 mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right updated -> do
            updated.dispatchStatus `shouldBe` Duplicate
            updated.reasonCode `shouldBe` Just IdempotencyDuplicateEvent

      it "rejects from Published state" $ do
        case markPublished HypothesisProposed testDecision "hyp-ref" fixedTime mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right published ->
            markDuplicate fixedTime2 published `shouldSatisfy` isLeft

    -- markFailed テスト
    describe "markFailed" $ do
      it "transitions Pending to DispatchFailed" $ do
        markFailed DependencyTimeout 0 fixedTime2 mkPendingDispatch `shouldSatisfy` isRight

      it "sets reasonCode and retryCount" $ do
        case markFailed DependencyTimeout 1 fixedTime2 mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right updated -> do
            updated.dispatchStatus `shouldBe` DispatchFailed
            updated.reasonCode `shouldBe` Just DependencyTimeout
            updated.retryCount `shouldBe` Just 1

      it "rejects from Published state" $ do
        case markPublished HypothesisProposed testDecision "hyp-ref" fixedTime mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right published ->
            markFailed DependencyTimeout 0 fixedTime2 published `shouldSatisfy` isLeft

    -- Must-09: identifier immutability テスト
    describe "identifier immutability (Must-09)" $ do
      it "identifier does not change after markPublished" $ do
        case markPublished HypothesisProposed testDecision "hyp-ref" fixedTime mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right updated -> updated.identifier `shouldBe` testIdentifier

      it "identifier does not change after markFailed" $ do
        case markFailed DependencyTimeout 0 fixedTime mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right updated -> updated.identifier `shouldBe` testIdentifier

    -- Must-10: hypothesis フィールド名テスト（Identifier サフィックスなし）
    describe "hypothesis field naming (Must-10, Must-38)" $ do
      it "uses 'hypothesis' field name without Identifier suffix" $ do
        case markPublished HypothesisProposed testDecision "hyp-ref-test" fixedTime mkPendingDispatch of
          Left domainError -> fail ("Unexpected Left: " ++ show domainError)
          Right updated -> updated.hypothesis `shouldBe` Just "hyp-ref-test"
