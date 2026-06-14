{- | Payload encoding tests for PubSubPortfolioEventPublisher.
Must-07: eventType present, reasonCode SCREAMING_SNAKE_CASE.
-}
module Infrastructure.Publisher.PubSubPortfolioEventPublisherSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Ratio ((%))
import Data.Time (UTCTime (..), fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalIdentifier (..),
  Side (..),
  createProposal,
 )
import Domain.OrderProposal.ProposalDispatch (
  ProposalDispatch,
  ProposalDispatchIdentifier (..),
  startDispatch,
 )
import Domain.OrderProposal.ReasonCode (ReasonCode (..))
import Domain.OrderProposal.ValueObjects (
  DegradationFlag (..),
  SignalSnapshot (..),
  StrategySnapshot (..),
 )
import Infrastructure.Publisher.PubSubPortfolioEventPublisher (
  buildOrdersProposalFailedEvent,
  buildOrdersProposedEvent,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "PubSubPortfolioEventPublisher" $ do
    describe "buildOrdersProposedEvent" $ do
      it "CloudEvent JSON has eventType=orders.proposed" $ do
        let dispatch = testDispatch
            orders = [testProposal]
            event = buildOrdersProposedEvent testUlid testTime testUlid dispatch orders
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            KeyMap.lookup "eventType" obj
              `shouldBe` Just (Aeson.String "orders.proposed")
          Just other -> fail ("expected JSON object, got: " <> show other)

      it "CloudEvent JSON has schemaVersion=1.0.0" $ do
        let dispatch = testDispatch
            orders = [testProposal]
            event = buildOrdersProposedEvent testUlid testTime testUlid dispatch orders
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            KeyMap.lookup "schemaVersion" obj
              `shouldBe` Just (Aeson.String "1.0.0")
          Just other -> fail ("expected JSON object, got: " <> show other)

      it "payload contains orders array" $ do
        let dispatch = testDispatch
            orders = [testProposal]
            event = buildOrdersProposedEvent testUlid testTime testUlid dispatch orders
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "orders" payloadObj `shouldSatisfy` \v -> case v of
                  Just (Aeson.Array _) -> True
                  _ -> False
              _ -> fail "missing payload"
          _ -> fail "could not decode"

    describe "buildOrdersProposalFailedEvent" $ do
      it "CloudEvent JSON has eventType=orders.proposal.failed" $ do
        let event =
              buildOrdersProposalFailedEvent
                testUlid
                testTime
                testUlid
                testDispatchIdentifier
                DependencyTimeout
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            KeyMap.lookup "eventType" obj
              `shouldBe` Just (Aeson.String "orders.proposal.failed")
          Just other -> fail ("expected JSON object, got: " <> show other)

      it "payload reasonCode is SCREAMING_SNAKE_CASE for DependencyTimeout" $ do
        let event =
              buildOrdersProposalFailedEvent
                testUlid
                testTime
                testUlid
                testDispatchIdentifier
                DependencyTimeout
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "reasonCode" payloadObj
                  `shouldBe` Just (Aeson.String "DEPENDENCY_TIMEOUT")
              _ -> fail "missing payload"
          _ -> fail "could not decode"

      it "all 5 ReasonCode values serialize to SCREAMING_SNAKE_CASE" $ do
        let now = testTime
            extractReasonCodeText reasonCode =
              let event =
                    buildOrdersProposalFailedEvent
                      testUlid
                      now
                      testUlid
                      testDispatchIdentifier
                      reasonCode
                  jsonBytes = Aeson.encode event
               in case Aeson.decode jsonBytes :: Maybe Aeson.Value of
                    Just (Aeson.Object obj) ->
                      case KeyMap.lookup "payload" obj of
                        Just (Aeson.Object payloadObj) ->
                          KeyMap.lookup "reasonCode" payloadObj
                        _ -> Nothing
                    _ -> Nothing
        extractReasonCodeText RequestValidationFailed
          `shouldBe` Just (Aeson.String "REQUEST_VALIDATION_FAILED")
        extractReasonCodeText ComplianceReviewRequired
          `shouldBe` Just (Aeson.String "COMPLIANCE_REVIEW_REQUIRED")
        extractReasonCodeText IdempotencyDuplicateEvent
          `shouldBe` Just (Aeson.String "IDEMPOTENCY_DUPLICATE_EVENT")
        extractReasonCodeText DependencyTimeout
          `shouldBe` Just (Aeson.String "DEPENDENCY_TIMEOUT")
        extractReasonCodeText DependencyUnavailable
          `shouldBe` Just (Aeson.String "DEPENDENCY_UNAVAILABLE")

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 13 of
  Right ulid -> ulid
  Left _ -> error "test ulid"

testTime :: UTCTime
testTime = UTCTime (fromGregorian 2026 1 15) 0

testDispatchIdentifier :: ProposalDispatchIdentifier
testDispatchIdentifier = ProposalDispatchIdentifier{value = testUlid}

testSignalSnapshot :: SignalSnapshot
testSignalSnapshot =
  SignalSnapshot
    { signalVersion = "v1.0"
    , modelVersion = "m1.0"
    , featureVersion = "f1.0"
    , storagePath = "gs://bucket/signals/v1.parquet"
    , degradationFlag = Normal
    , requiresComplianceReview = False
    }

testStrategySnapshot :: StrategySnapshot
testStrategySnapshot =
  StrategySnapshot
    { maxOrderCount = 10
    , maxSingleOrderQty = 100
    , rebalanceThreshold = 5 % 100
    }

testDispatch :: ProposalDispatch
testDispatch =
  let (dispatch, _) =
        startDispatch
          testDispatchIdentifier
          testSignalSnapshot
          Trace{value = testUlid}
   in dispatch

testProposal :: OrderProposal
testProposal =
  case createProposal
    OrderProposalIdentifier{value = testUlid}
    "7203.T"
    Buy
    100
    testSignalSnapshot
    Nothing
    testStrategySnapshot
    Trace{value = testUlid}
    testTime of
    Right (proposal, _) -> proposal
    Left domainError -> error ("test proposal: " <> show domainError)
