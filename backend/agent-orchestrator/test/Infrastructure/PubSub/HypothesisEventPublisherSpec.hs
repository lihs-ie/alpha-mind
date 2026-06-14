module Infrastructure.PubSub.HypothesisEventPublisherSpec (spec) where

import Data.Aeson (Value (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as Aeson.Key
import Data.Aeson.KeyMap qualified as Aeson.KeyMap
import Data.ByteString.Lazy (ByteString)
import Data.IORef (IORef, modifyIORef, newIORef, readIORef)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..))
import Data.ULID (ULID)
import Domain.HypothesisOrchestration (Trace (..))
import Domain.HypothesisOrchestration.Aggregate (
  HypothesisProposal,
  HypothesisProposalIdentifier (..),
  InstrumentType (..),
  completeProposal,
  failProposal,
  startProposal,
 )
import Domain.HypothesisOrchestration.Error (DomainError (..))
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode (..))
import Domain.HypothesisOrchestration.ValueObjects (mkProposalArtifact)
import Infrastructure.PubSub.HypothesisEventPublisher (
  HypothesisPublisherEnv (..),
  hypothesisPubSubTopicEnvVar,
  publishHypothesisProposalFailed,
  publishHypothesisProposed,
  runHypothesisEventPublisher,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldNotBe, shouldSatisfy)
import Text.Read (readMaybe)

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case readMaybe "01ARZ3NDEKTSV4RRFFQ69G5FAV" of
  Just u -> u
  Nothing -> error "invalid test ULID"

testTraceUlid :: ULID
testTraceUlid = case readMaybe "01BX5ZZKBKACTAV9WEVGEMMVRE" of
  Just u -> u
  Nothing -> error "invalid test trace ULID"

testNow :: UTCTime
testNow = UTCTime (fromGregorian 2024 1 15) 0

testPendingProposal :: HypothesisProposal
testPendingProposal =
  fst $
    startProposal
      HypothesisProposalIdentifier{value = testUlid}
      "dispatch-ref-001"
      Trace{value = testTraceUlid}
      testNow

testProposedProposal :: HypothesisProposal
testProposedProposal =
  let artifact = mkProposalArtifact "gs://bucket/reports/hyp-001.md" "gpt-4o" testNow
   in case completeProposal
        "7203.T"
        Stock
        "Toyota undervalued hypothesis"
        ["evidence-1", "evidence-2"]
        "hypothesis-skill-v1"
        "instruction-v1"
        Nothing
        (Just False)
        artifact
        testNow
        testPendingProposal of
        Right (proposal, _) -> proposal
        Left domainError -> error ("Failed to complete proposal: " <> show domainError)

testFailedProposal :: HypothesisProposal
testFailedProposal =
  case failProposal DependencyTimeout testNow testPendingProposal of
    Right (proposal, _) -> proposal
    Left domainError -> error ("Failed to fail proposal: " <> show domainError)

-- ---------------------------------------------------------------------------
-- Mock environment helpers (Must-28: no real Pub/Sub calls)
-- ---------------------------------------------------------------------------

makeEnvWithCapture ::
  IORef [(Text, ByteString)] ->
  HypothesisPublisherEnv
makeEnvWithCapture capturedRef =
  HypothesisPublisherEnv
    { topicName = "projects/test-project/topics/hypothesis-events"
    , pubsubPublish = \topic bytes ->
        modifyIORef capturedRef ((topic, bytes) :)
    }

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False

getJsonField :: ByteString -> Text -> Maybe Aeson.Value
getJsonField bytes fieldName =
  case Aeson.decode bytes of
    Nothing -> Nothing
    Just (Aeson.Object objectMap) -> Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) objectMap
    Just _ -> Nothing

getPayloadField :: ByteString -> Text -> Maybe Aeson.Value
getPayloadField bytes fieldName =
  case getJsonField bytes "payload" of
    Just (Aeson.Object payloadMap) -> Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) payloadMap
    _ -> Nothing

-- ---------------------------------------------------------------------------
-- Spec (Must-27, Must-30)
-- ---------------------------------------------------------------------------

spec :: Spec
spec =
  describe "Infrastructure.PubSub.HypothesisEventPublisher" $ do
    -- Environment variable name (Must-19)
    describe "environment variable" $ do
      it "hypothesisPubSubTopicEnvVar is PUBSUB_TOPIC_HYPOTHESIS (Must-19)" $
        hypothesisPubSubTopicEnvVar `shouldBe` "PUBSUB_TOPIC_HYPOTHESIS"

    -- publishHypothesisProposed tests (Must-30)
    describe "publishHypothesisProposed" $ do
      it "normal case (status=Proposed): publishes message with eventType=hypothesis.proposed (Must-30)" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        result <- runHypothesisEventPublisher environment (publishHypothesisProposed testProposedProposal)
        result `shouldBe` Right ()
        captured <- readIORef capturedRef
        length captured `shouldBe` 1
        let (_, messageBytes) = head captured
        case getJsonField messageBytes "eventType" of
          Just (Aeson.String eventTypeText) -> eventTypeText `shouldBe` "hypothesis.proposed"
          other -> fail ("Expected eventType string 'hypothesis.proposed', got: " <> show other)

      it "normal case: published JSON has identifier, occurredAt, trace, schemaVersion (Must-20)" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        _result <- runHypothesisEventPublisher environment (publishHypothesisProposed testProposedProposal)
        captured <- readIORef capturedRef
        let (_, messageBytes) = head captured
        getJsonField messageBytes "identifier" `shouldSatisfy` (/= Nothing)
        getJsonField messageBytes "occurredAt" `shouldSatisfy` (/= Nothing)
        getJsonField messageBytes "trace" `shouldSatisfy` (/= Nothing)
        getJsonField messageBytes "schemaVersion" `shouldSatisfy` (/= Nothing)

      it "normal case: payload.symbol is non-empty (Must-20)" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        _result <- runHypothesisEventPublisher environment (publishHypothesisProposed testProposedProposal)
        captured <- readIORef capturedRef
        let (_, messageBytes) = head captured
        case getPayloadField messageBytes "symbol" of
          Just (Aeson.String s) -> s `shouldSatisfy` (not . Text.null)
          other -> fail ("Expected non-empty symbol string, got: " <> show other)

      it "normal case: payload.sourceEvidence is an array (Must-20)" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        _result <- runHypothesisEventPublisher environment (publishHypothesisProposed testProposedProposal)
        captured <- readIORef capturedRef
        let (_, messageBytes) = head captured
        case getPayloadField messageBytes "sourceEvidence" of
          Just (Aeson.Array _) -> pure ()
          other -> fail ("Expected sourceEvidence array, got: " <> show other)

      it "normal case: payload.instrumentType is a string (Must-20)" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        _result <- runHypothesisEventPublisher environment (publishHypothesisProposed testProposedProposal)
        captured <- readIORef capturedRef
        let (_, messageBytes) = head captured
        case getPayloadField messageBytes "instrumentType" of
          Just (Aeson.String _) -> pure ()
          other -> fail ("Expected instrumentType string, got: " <> show other)

      it "must-22: two consecutive calls produce different event identifiers" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        _result1 <- runHypothesisEventPublisher environment (publishHypothesisProposed testProposedProposal)
        _result2 <- runHypothesisEventPublisher environment (publishHypothesisProposed testProposedProposal)
        captured <- readIORef capturedRef
        length captured `shouldBe` 2
        -- list is reversed: [second, first]
        let (_, bytes2) = head captured
            (_, bytes1) = captured !! 1
        getJsonField bytes1 "identifier" `shouldNotBe` getJsonField bytes2 "identifier"

      it "must-23: guard violation (status=Pending) → Left DomainError, no publish" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        result <- runHypothesisEventPublisher environment (publishHypothesisProposed testPendingProposal)
        result `shouldSatisfy` isLeft
        captured <- readIORef capturedRef
        length captured `shouldBe` 0

      it "must-23: guard violation (status=Failed) → Left DomainError, no publish" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        result <- runHypothesisEventPublisher environment (publishHypothesisProposed testFailedProposal)
        result `shouldSatisfy` isLeft
        captured <- readIORef capturedRef
        length captured `shouldBe` 0

    -- publishHypothesisProposalFailed tests (Must-30)
    describe "publishHypothesisProposalFailed" $ do
      it "normal case (status=Failed): publishes message with eventType=hypothesis.proposal.failed (Must-30)" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        result <- runHypothesisEventPublisher environment (publishHypothesisProposalFailed testFailedProposal DependencyTimeout)
        result `shouldBe` Right ()
        captured <- readIORef capturedRef
        length captured `shouldBe` 1
        let (_, messageBytes) = head captured
        case getJsonField messageBytes "eventType" of
          Just (Aeson.String eventTypeText) -> eventTypeText `shouldBe` "hypothesis.proposal.failed"
          other -> fail ("Expected 'hypothesis.proposal.failed', got: " <> show other)

      it "normal case: payload.reasonCode is non-empty string (Must-21)" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        _result <-
          runHypothesisEventPublisher environment (publishHypothesisProposalFailed testFailedProposal DependencyTimeout)
        captured <- readIORef capturedRef
        let (_, messageBytes) = head captured
        case getPayloadField messageBytes "reasonCode" of
          Just (Aeson.String reasonCodeText) -> reasonCodeText `shouldSatisfy` (not . Text.null)
          other -> fail ("Expected non-empty reasonCode string, got: " <> show other)

      it "must-24: guard violation (status=Pending) → Left DomainError, no publish" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        result <-
          runHypothesisEventPublisher environment (publishHypothesisProposalFailed testPendingProposal DependencyTimeout)
        result `shouldSatisfy` isLeft
        captured <- readIORef capturedRef
        length captured `shouldBe` 0

      it "must-24: guard violation (status=Proposed) → Left DomainError, no publish" $ do
        capturedRef <- newIORef []
        let environment = makeEnvWithCapture capturedRef
        result <-
          runHypothesisEventPublisher environment (publishHypothesisProposalFailed testProposedProposal DependencyTimeout)
        result `shouldSatisfy` isLeft
        captured <- readIORef capturedRef
        length captured `shouldBe` 0
