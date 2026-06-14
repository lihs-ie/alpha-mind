{-# OPTIONS_GHC -fno-hpc #-}

{- | Unit tests for 'Presentation.PubSubHandler'.

 Tests call 'processPubSubPushWith' (IO function) directly using injectable
 seams so no real Firestore or Pub/Sub connection is required.

 Test doubles (fake usecase runner, fake aggregate fetcher) live in this
 test file only; no mock enters src/.
-}
module Presentation.PubSubHandlerSpec (spec) where

import Config.Env (CommonRuntimeEnv (..))
import Data.Aeson (Value, encode, object, (.=))
import Data.Base64.Types (extractBase64)
import Data.ByteString.Base64 (encodeBase64)
import Data.ByteString.Lazy qualified as ByteStringLazy
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Time (UTCTime (..), getCurrentTime)
import Data.Time.Calendar (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderProposal (Trace (..))
import Domain.OrderProposal.Aggregate (
  OrderProposal,
  OrderProposalIdentifier (..),
  Side (..),
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
  PubSubPortfolioEventPublisherEnv (..),
 )
import Messaging.CloudEvent (CloudEvent (..))
import Messaging.PubSub (PubSubPublisher (..))
import Network.HTTP.Client (defaultManagerSettings, newManager)
import Observability.Logging (initLogger)
import Persistence.Firestore (FirestoreContext (..))
import Presentation.AppM (AppEnv (..))
import Presentation.PubSubHandler (
  PubSubPushResult (..),
  SignalPayload (..),
  cloudEventToSignalPayload,
  processPubSubPushWith,
  pubSubPushResultToStatus,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.PortfolioPlanningService (
  ProposeOrdersInput (..),
  ProposeOrdersResult (..),
 )

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

mkUlid :: Integer -> ULID
mkUlid n = case ulidFromInteger n of
  Right ulid -> ulid
  Left message -> error (show message)

validUlidText1 :: Text
validUlidText1 = "01ARZ3NDEKTSV4RRFFQ69G5FAV"

fixedTime :: UTCTime
fixedTime = UTCTime (fromGregorian 2026 1 15) 0

-- ---------------------------------------------------------------------------
-- Fake AppEnv builder
-- ---------------------------------------------------------------------------

makeTestAppEnv :: IO AppEnv
makeTestAppEnv = do
  httpManager <- newManager defaultManagerSettings
  let runtimeEnv =
        CommonRuntimeEnv
          { port = 8080
          , gcpProjectId = "test-project"
          , serviceName = "portfolio-planner"
          , serviceVersion = "test"
          , revision = Nothing
          , logLevel = "info"
          }
  logEnvironment <- initLogger runtimeEnv
  let firestoreCtx =
        FirestoreContext
          { projectId = "test-project"
          , databaseId = "(default)"
          }
      publisher =
        PubSubPublisher
          { manager = httpManager
          , projectId = "test-project"
          , baseURL = "http://localhost:19999/"
          , accessToken = pure "test-token"
          }
      pubSubEnvironment =
        PubSubPortfolioEventPublisherEnv
          { publisher = publisher
          , proposedTopicName = "orders-proposed"
          , failedTopicName = "orders-proposal-failed"
          }
  pure
    AppEnv
      { firestoreContext = firestoreCtx
      , logEnv = logEnvironment
      , pubSubEnv = pubSubEnvironment
      , serviceName = "portfolio-planner"
      }

-- ---------------------------------------------------------------------------
-- Fake usecase runners (test doubles in test/ only)
-- ---------------------------------------------------------------------------

-- | Always returns 'ProposeOrdersSucceeded' with the given dispatch identifier.
fakeSuccessRunner ::
  ProposeOrdersResult ->
  UTCTime ->
  ProposeOrdersInput ->
  IO ProposeOrdersResult
fakeSuccessRunner result _ _ = pure result

-- | Always returns 'ProposeOrdersDuplicate'.
fakeDuplicateRunner :: UTCTime -> ProposeOrdersInput -> IO ProposeOrdersResult
fakeDuplicateRunner _ _ = pure ProposeOrdersDuplicate

-- | Always returns 'ProposeOrdersFailed' with the given reason code.
fakeFailureRunner ::
  ReasonCode ->
  UTCTime ->
  ProposeOrdersInput ->
  IO ProposeOrdersResult
fakeFailureRunner failureReasonCode _ input =
  pure
    ProposeOrdersFailed
      { reasonCode = failureReasonCode
      , dispatch = input.eventIdentifier
      , trace = input.trace
      }

-- ---------------------------------------------------------------------------
-- Fake aggregate fetcher
-- ---------------------------------------------------------------------------

-- | Returns Nothing for dispatch and empty orders list.
fakeEmptyFetcher ::
  ProposalDispatchIdentifier ->
  [OrderProposalIdentifier] ->
  IO (Maybe ProposalDispatch, [OrderProposal])
fakeEmptyFetcher _ _ = pure (Nothing, [])

-- | Returns a pre-seeded ProposalDispatch and empty orders.
makeFakeDispatchFetcher ::
  ProposalDispatch ->
  ProposalDispatchIdentifier ->
  [OrderProposalIdentifier] ->
  IO (Maybe ProposalDispatch, [OrderProposal])
makeFakeDispatchFetcher dispatch _ _ = pure (Just dispatch, [])

-- ---------------------------------------------------------------------------
-- Pub/Sub body builders
-- ---------------------------------------------------------------------------

buildPubSubBody :: Value -> ByteStringLazy.ByteString
buildPubSubBody cloudEventValue =
  let rawBytes = ByteStringLazy.toStrict (encode cloudEventValue)
      base64Data = extractBase64 (encodeBase64 rawBytes)
   in encode
        ( object
            [ "message"
                .= object
                  [ "messageId" .= ("test-msg-id" :: Text)
                  , "publishTime" .= ("2026-01-15T00:00:00Z" :: Text)
                  , "data" .= base64Data
                  ]
            ]
        )

invalidJsonBody :: ByteStringLazy.ByteString
invalidJsonBody = "not-valid-json{{{"

-- | Build a valid signal.generated CloudEvent body.
buildValidSignalBody :: ULID -> Value
buildValidSignalBody eventUlid =
  let ulidText = showText eventUlid
   in object
        [ "identifier" .= ulidText
        , "eventType" .= ("signal.generated" :: Text)
        , "occurredAt" .= ("2026-01-15T00:00:00Z" :: Text)
        , "trace" .= ulidText
        , "schemaVersion" .= ("1.0.0" :: Text)
        , "payload"
            .= object
              [ "signalVersion" .= ("v1.0" :: Text)
              , "modelVersion" .= ("m2.0" :: Text)
              , "featureVersion" .= ("f3.0" :: Text)
              , "storagePath" .= ("gs://bucket/signals.parquet" :: Text)
              , "degradationFlag" .= ("NORMAL" :: Text)
              , "requiresComplianceReview" .= False
              , "proposalSymbol" .= ("7203" :: Text)
              , "proposalSide" .= ("BUY" :: Text)
              , "maxOrderCount" .= (10 :: Int)
              , "maxSingleOrderQty" .= (100.0 :: Double)
              , "rebalanceThreshold" .= (0.05 :: Double)
              ]
        ]

-- | Build a CloudEvent body with a missing required payload field.
buildMissingFieldBody :: Value
buildMissingFieldBody =
  let ulidText = validUlidText1
   in object
        [ "identifier" .= ulidText
        , "eventType" .= ("signal.generated" :: Text)
        , "occurredAt" .= ("2026-01-15T00:00:00Z" :: Text)
        , "trace" .= ulidText
        , "schemaVersion" .= ("1.0.0" :: Text)
        , "payload"
            .= object
              [ "signalVersion" .= ("v1.0" :: Text)
              -- proposalSymbol is missing
              ]
        ]

showText :: (Show a) => a -> Text
showText = Text.pack . show

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "Presentation.PubSubHandler" $ do
    describe "processPubSubPushWith — schema validation" $ do
      it "invalid JSON body returns PubSubPushSchemaInvalid" $ do
        appEnv <- makeTestAppEnv
        result <-
          processPubSubPushWith
            appEnv.logEnv
            appEnv
            (fakeSuccessRunner ProposeOrdersDuplicate)
            fakeEmptyFetcher
            invalidJsonBody
        result `shouldSatisfy` isSchemaInvalid

      it "missing required payload field returns PubSubPushSchemaInvalid" $ do
        appEnv <- makeTestAppEnv
        let body = buildPubSubBody buildMissingFieldBody
        result <-
          processPubSubPushWith
            appEnv.logEnv
            appEnv
            (fakeSuccessRunner ProposeOrdersDuplicate)
            fakeEmptyFetcher
            body
        result `shouldSatisfy` isSchemaInvalid

    describe "processPubSubPushWith — duplicate path" $ do
      it "duplicate usecase result returns PubSubPushProposalDuplicate" $ do
        appEnv <- makeTestAppEnv
        let eventUlid = mkUlid 1
            cloudEventValue = buildValidSignalBody eventUlid
            body = buildPubSubBody cloudEventValue
        result <-
          processPubSubPushWith
            appEnv.logEnv
            appEnv
            fakeDuplicateRunner
            fakeEmptyFetcher
            body
        result `shouldBe` PubSubPushProposalDuplicate

    describe "processPubSubPushWith — failure path" $ do
      it "failure usecase result returns PubSubPushProposalFailed" $ do
        appEnv <- makeTestAppEnv
        let eventUlid = mkUlid 2
            cloudEventValue = buildValidSignalBody eventUlid
            body = buildPubSubBody cloudEventValue
        result <-
          processPubSubPushWith
            appEnv.logEnv
            appEnv
            (fakeFailureRunner RequestValidationFailed)
            fakeEmptyFetcher
            body
        result `shouldSatisfy` isProposalFailed

    describe "processPubSubPushWith — success path" $ do
      it "success with dispatch found returns PubSubPushProposalSucceeded" $ do
        appEnv <- makeTestAppEnv
        let eventUlid = mkUlid 3
            dispatchIdentifier = ProposalDispatchIdentifier eventUlid
            traceValue = Trace eventUlid
            testSignalSnapshot =
              SignalSnapshot
                { signalVersion = "v1.0"
                , modelVersion = "m2.0"
                , featureVersion = "f3.0"
                , storagePath = "gs://bucket/signals.parquet"
                , degradationFlag = Normal
                , requiresComplianceReview = False
                }
            (preseededDispatch, _) = startDispatch dispatchIdentifier testSignalSnapshot traceValue
            cloudEventValue = buildValidSignalBody eventUlid
            body = buildPubSubBody cloudEventValue
            successResult =
              ProposeOrdersSucceeded
                { orders = [OrderProposalIdentifier (mkUlid 99)]
                , dispatch = dispatchIdentifier
                , trace = traceValue
                }
        result <-
          processPubSubPushWith
            appEnv.logEnv
            appEnv
            (fakeSuccessRunner successResult)
            (makeFakeDispatchFetcher preseededDispatch)
            body
        result `shouldBe` PubSubPushProposalSucceeded

      it "success with dispatch not found returns PubSubPushWriteFailed" $ do
        appEnv <- makeTestAppEnv
        let eventUlid = mkUlid 4
            dispatchIdentifier = ProposalDispatchIdentifier eventUlid
            traceValue = Trace eventUlid
            cloudEventValue = buildValidSignalBody eventUlid
            body = buildPubSubBody cloudEventValue
            successResult =
              ProposeOrdersSucceeded
                { orders = []
                , dispatch = dispatchIdentifier
                , trace = traceValue
                }
        result <-
          processPubSubPushWith
            appEnv.logEnv
            appEnv
            (fakeSuccessRunner successResult)
            fakeEmptyFetcher
            body
        result `shouldSatisfy` isWriteFailed

    describe "pubSubPushResultToStatus — HTTP mapping" $ do
      it "PubSubPushProposalSucceeded maps to Right (HTTP 200)" $ do
        pubSubPushResultToStatus PubSubPushProposalSucceeded
          `shouldBe` Right PubSubPushProposalSucceeded

      it "PubSubPushProposalDuplicate maps to Right (HTTP 200)" $ do
        pubSubPushResultToStatus PubSubPushProposalDuplicate
          `shouldBe` Right PubSubPushProposalDuplicate

      it "PubSubPushSchemaInvalid maps to Right (HTTP 200 — permanent failure)" $ do
        pubSubPushResultToStatus (PubSubPushSchemaInvalid "test")
          `shouldBe` Right (PubSubPushSchemaInvalid "test")

      it "PubSubPushProposalFailed maps to Left (HTTP 500 — transient)" $ do
        pubSubPushResultToStatus (PubSubPushProposalFailed "reason")
          `shouldSatisfy` isLeft

      it "PubSubPushWriteFailed maps to Left (HTTP 500 — transient)" $ do
        pubSubPushResultToStatus (PubSubPushWriteFailed "transient")
          `shouldSatisfy` isLeft

    describe "cloudEventToSignalPayload — field extraction" $ do
      it "extracts proposalSide Buy from 'BUY'" $ do
        let cloudEventValue =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "signal.generated"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload =
                    object
                      [ "signalVersion" .= ("v1.0" :: Text)
                      , "modelVersion" .= ("m2.0" :: Text)
                      , "featureVersion" .= ("f3.0" :: Text)
                      , "storagePath" .= ("gs://bucket" :: Text)
                      , "degradationFlag" .= ("NORMAL" :: Text)
                      , "requiresComplianceReview" .= False
                      , "proposalSymbol" .= ("7203" :: Text)
                      , "proposalSide" .= ("BUY" :: Text)
                      , "maxOrderCount" .= (10 :: Int)
                      , "maxSingleOrderQty" .= (100.0 :: Double)
                      , "rebalanceThreshold" .= (0.05 :: Double)
                      ]
                }
        case cloudEventToSignalPayload cloudEventValue of
          Left errorMessage -> fail ("Expected Right, got Left: " <> Text.unpack errorMessage)
          Right signalPayload -> signalPayload.proposalSide `shouldBe` Buy

      it "extracts proposalSide Sell from 'SELL'" $ do
        let cloudEventValue =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "signal.generated"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload =
                    object
                      [ "signalVersion" .= ("v1.0" :: Text)
                      , "modelVersion" .= ("m2.0" :: Text)
                      , "featureVersion" .= ("f3.0" :: Text)
                      , "storagePath" .= ("gs://bucket" :: Text)
                      , "degradationFlag" .= ("NORMAL" :: Text)
                      , "requiresComplianceReview" .= False
                      , "proposalSymbol" .= ("7203" :: Text)
                      , "proposalSide" .= ("SELL" :: Text)
                      , "maxOrderCount" .= (10 :: Int)
                      , "maxSingleOrderQty" .= (100.0 :: Double)
                      , "rebalanceThreshold" .= (0.05 :: Double)
                      ]
                }
        case cloudEventToSignalPayload cloudEventValue of
          Left errorMessage -> fail ("Expected Right, got Left: " <> Text.unpack errorMessage)
          Right signalPayload -> signalPayload.proposalSide `shouldBe` Sell

      it "extracts degradationFlag Warn from 'WARN'" $ do
        let cloudEventValue =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "signal.generated"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload =
                    object
                      [ "signalVersion" .= ("v1.0" :: Text)
                      , "modelVersion" .= ("m2.0" :: Text)
                      , "featureVersion" .= ("f3.0" :: Text)
                      , "storagePath" .= ("gs://bucket" :: Text)
                      , "degradationFlag" .= ("WARN" :: Text)
                      , "requiresComplianceReview" .= False
                      , "proposalSymbol" .= ("7203" :: Text)
                      , "proposalSide" .= ("BUY" :: Text)
                      , "maxOrderCount" .= (10 :: Int)
                      , "maxSingleOrderQty" .= (100.0 :: Double)
                      , "rebalanceThreshold" .= (0.05 :: Double)
                      ]
                }
        case cloudEventToSignalPayload cloudEventValue of
          Left errorMessage -> fail ("Expected Right, got Left: " <> Text.unpack errorMessage)
          Right signalPayload -> signalPayload.signalSnapshot.degradationFlag `shouldBe` Warn

      it "returns Left for unknown proposalSide" $ do
        let cloudEventValue =
              CloudEvent
                { identifier = mkUlid 1
                , eventType = "signal.generated"
                , occurredAt = UTCTime (fromGregorian 2026 1 15) 0
                , trace = mkUlid 2
                , schemaVersion = "1.0.0"
                , payload =
                    object
                      [ "signalVersion" .= ("v1.0" :: Text)
                      , "modelVersion" .= ("m2.0" :: Text)
                      , "featureVersion" .= ("f3.0" :: Text)
                      , "storagePath" .= ("gs://bucket" :: Text)
                      , "degradationFlag" .= ("NORMAL" :: Text)
                      , "requiresComplianceReview" .= False
                      , "proposalSymbol" .= ("7203" :: Text)
                      , "proposalSide" .= ("INVALID" :: Text)
                      , "maxOrderCount" .= (10 :: Int)
                      , "maxSingleOrderQty" .= (100.0 :: Double)
                      , "rebalanceThreshold" .= (0.05 :: Double)
                      ]
                }
        cloudEventToSignalPayload cloudEventValue `shouldSatisfy` isLeft

-- ---------------------------------------------------------------------------
-- Predicate helpers
-- ---------------------------------------------------------------------------

isSchemaInvalid :: PubSubPushResult -> Bool
isSchemaInvalid (PubSubPushSchemaInvalid _) = True
isSchemaInvalid _ = False

isProposalFailed :: PubSubPushResult -> Bool
isProposalFailed (PubSubPushProposalFailed _) = True
isProposalFailed _ = False

isWriteFailed :: PubSubPushResult -> Bool
isWriteFailed (PubSubPushWriteFailed _) = True
isWriteFailed _ = False

isLeft :: Either a b -> Bool
isLeft (Left _) = True
isLeft _ = False
