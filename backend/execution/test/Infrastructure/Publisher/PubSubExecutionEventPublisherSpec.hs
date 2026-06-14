module Infrastructure.Publisher.PubSubExecutionEventPublisherSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Time (UTCTime (..), fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.OrderExecution.Aggregate (OrderExecutionIdentifier (..))
import Domain.OrderExecution.DemoRunEvaluation (DemoPerformance (..))
import Domain.OrderExecution.ReasonCode (ReasonCode (..))
import Infrastructure.Publisher.PubSubExecutionEventPublisher (
  buildHypothesisDemoCompletedEvent,
  buildOrdersExecutedEvent,
  buildOrdersExecutionFailedEvent,
 )
import Test.Hspec (Spec, describe, it, shouldBe)
import UseCase.CompleteDemoRun (DemoRunIdentifier (..), HypothesisIdentifier (..))
import UseCase.ExecuteOrder (BrokerOrder (..))

spec :: Spec
spec = do
  describe "PubSubExecutionEventPublisherT" $ do
    -- TST-INFRA-004: buildOrdersExecutedEvent payload fields
    describe "TST-INFRA-004: buildOrdersExecutedEvent" $ do
      it "CloudEvent JSON has correct eventType, schemaVersion, and payload fields" $ do
        let now = UTCTime (fromGregorian 2026 1 15) 0
            traceUlid = testUlid
            executionIdentifier = OrderExecutionIdentifier{value = testUlid}
            brokerOrderValue = BrokerOrder{value = "broker-order-001"}
            executedAtTime = UTCTime (fromGregorian 2026 1 15) 3600
            event =
              buildOrdersExecutedEvent
                testUlid
                now
                traceUlid
                executionIdentifier
                brokerOrderValue
                executedAtTime
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) -> do
            KeyMap.lookup "eventType" obj
              `shouldBe` Just (Aeson.String "orders.executed")
            KeyMap.lookup "schemaVersion" obj
              `shouldBe` Just (Aeson.String "1.0.0")
            case KeyMap.lookup "payload" obj of
              Nothing -> fail "missing payload field"
              Just (Aeson.Object payloadObj) -> do
                KeyMap.lookup "brokerOrder" payloadObj
                  `shouldBe` Just (Aeson.String "broker-order-001")
                case KeyMap.lookup "executedAt" payloadObj of
                  Nothing -> fail "missing executedAt in payload"
                  Just _ -> pure ()
                case KeyMap.lookup "identifier" payloadObj of
                  Nothing -> fail "missing identifier in payload"
                  Just _ -> pure ()
              Just other -> fail ("unexpected payload: " <> show other)
          Just other -> fail ("expected JSON object, got: " <> show other)

    -- TST-INFRA-005: buildOrdersExecutionFailedEvent payload field (reasonCode)
    describe "TST-INFRA-005: buildOrdersExecutionFailedEvent" $ do
      it "CloudEvent JSON has eventType=orders.execution.failed and SCREAMING_SNAKE reasonCode" $ do
        let now = UTCTime (fromGregorian 2026 1 15) 0
            traceUlid = testUlid
            executionIdentifier = OrderExecutionIdentifier{value = testUlid}
            event =
              buildOrdersExecutionFailedEvent
                testUlid
                now
                traceUlid
                executionIdentifier
                ExecutionBrokerTimeout
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) -> do
            KeyMap.lookup "eventType" obj
              `shouldBe` Just (Aeson.String "orders.execution.failed")
            KeyMap.lookup "schemaVersion" obj
              `shouldBe` Just (Aeson.String "1.0.0")
            case KeyMap.lookup "payload" obj of
              Nothing -> fail "missing payload field"
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "reasonCode" payloadObj
                  `shouldBe` Just (Aeson.String "EXECUTION_BROKER_TIMEOUT")
              Just other -> fail ("unexpected payload: " <> show other)
          Just other -> fail ("expected JSON object, got: " <> show other)

      it "all ReasonCode values serialize to SCREAMING_SNAKE_CASE" $ do
        let now = UTCTime (fromGregorian 2026 1 15) 0
            traceUlid = testUlid
            executionIdentifier = OrderExecutionIdentifier{value = testUlid}
            extractReasonCodeText reasonCode =
              let event =
                    buildOrdersExecutionFailedEvent
                      testUlid
                      now
                      traceUlid
                      executionIdentifier
                      reasonCode
                  jsonBytes = Aeson.encode event
               in case Aeson.decode jsonBytes :: Maybe Aeson.Value of
                    Just (Aeson.Object obj) ->
                      case KeyMap.lookup "payload" obj of
                        Just (Aeson.Object payloadObj) ->
                          KeyMap.lookup "reasonCode" payloadObj
                        _ -> Nothing
                    _ -> Nothing
        extractReasonCodeText ExecutionBrokerTimeout
          `shouldBe` Just (Aeson.String "EXECUTION_BROKER_TIMEOUT")
        extractReasonCodeText ExecutionBrokerRejected
          `shouldBe` Just (Aeson.String "EXECUTION_BROKER_REJECTED")
        extractReasonCodeText ExecutionMarketClosed
          `shouldBe` Just (Aeson.String "EXECUTION_MARKET_CLOSED")
        extractReasonCodeText ExecutionInsufficientFunds
          `shouldBe` Just (Aeson.String "EXECUTION_INSUFFICIENT_FUNDS")
        extractReasonCodeText IdempotencyDuplicateEvent
          `shouldBe` Just (Aeson.String "IDEMPOTENCY_DUPLICATE_EVENT")
        extractReasonCodeText StateConflict
          `shouldBe` Just (Aeson.String "STATE_CONFLICT")
        extractReasonCodeText DependencyTimeout
          `shouldBe` Just (Aeson.String "DEPENDENCY_TIMEOUT")
        extractReasonCodeText InternalError
          `shouldBe` Just (Aeson.String "INTERNAL_ERROR")

    -- TST-INFRA-006: buildHypothesisDemoCompletedEvent includes mnpiSelfDeclared in payload
    describe "TST-INFRA-006: buildHypothesisDemoCompletedEvent" $ do
      it "CloudEvent JSON has eventType=hypothesis.demo.completed and mnpiSelfDeclared in payload" $ do
        let now = UTCTime (fromGregorian 2026 1 15) 0
            traceUlid = testUlid
            hypothesisIdentifier = HypothesisIdentifier{value = testUlid}
            demoRunIdentifier = DemoRunIdentifier{value = "demo-20260115-001"}
            performance =
              DemoPerformance
                { costAdjustedReturn = 4.2
                , dsr = Just 1.14
                , pbo = Just 0.08
                , demoPeriodDays = 45
                }
            event =
              buildHypothesisDemoCompletedEvent
                testUlid
                now
                traceUlid
                hypothesisIdentifier
                demoRunIdentifier
                "1306.T"
                "ETF"
                "NONE"
                now
                now
                True
                False
                False
                performance
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) -> do
            KeyMap.lookup "eventType" obj
              `shouldBe` Just (Aeson.String "hypothesis.demo.completed")
            KeyMap.lookup "schemaVersion" obj
              `shouldBe` Just (Aeson.String "1.0.0")
            case KeyMap.lookup "payload" obj of
              Nothing -> fail "missing payload field"
              Just (Aeson.Object payloadObj) -> do
                KeyMap.lookup "demoRun" payloadObj
                  `shouldBe` Just (Aeson.String "demo-20260115-001")
                KeyMap.lookup "demoPeriodDays" payloadObj
                  `shouldBe` Just (Aeson.Number 45)
                KeyMap.lookup "mnpiSelfDeclared" payloadObj
                  `shouldBe` Just (Aeson.Bool False)
                KeyMap.lookup "promotable" payloadObj
                  `shouldBe` Just (Aeson.Bool True)
                KeyMap.lookup "symbol" payloadObj
                  `shouldBe` Just (Aeson.String "1306.T")
              Just other -> fail ("unexpected payload: " <> show other)
          Just other -> fail ("expected JSON object, got: " <> show other)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 5 of
  Right ulid -> ulid
  Left _ -> error "test ulid"
