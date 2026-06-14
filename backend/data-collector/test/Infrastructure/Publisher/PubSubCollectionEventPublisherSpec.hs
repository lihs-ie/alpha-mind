module Infrastructure.Publisher.PubSubCollectionEventPublisherSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Time (UTCTime (..), fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection.Aggregate (
  MarketSourceStatus (..),
  SourceStatus (..),
  mkCollectedArtifact,
 )
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Infrastructure.Publisher.PubSubCollectionEventPublisher (
  buildMarketCollectFailedEvent,
  buildMarketCollectedEvent,
 )
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)

spec :: Spec
spec = do
  describe "PubSubCollectionEventPublisherT" $ do
    -- TC-INFRA-006: buildMarketCollectedEvent — real builder path
    describe "TC-INFRA-006: buildMarketCollectedEvent" $ do
      it "CloudEvent JSON has correct eventType, schemaVersion, payload fields" $ do
        let targetDay = fromGregorian 2026 1 15
            now = UTCTime targetDay 0
            traceUlid = testUlid
            artifact =
              case mkCollectedArtifact
                targetDay
                "gs://bucket/path.ndjson"
                (SourceStatus Ok Ok)
                100 of
                Right a -> a
                Left domainError -> error ("test artifact: " <> show domainError)
            event = buildMarketCollectedEvent testUlid now traceUlid artifact
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) -> do
            KeyMap.lookup "eventType" obj
              `shouldBe` Just (Aeson.String "market.collected")
            KeyMap.lookup "schemaVersion" obj
              `shouldBe` Just (Aeson.String "1.0.0")
            case KeyMap.lookup "payload" obj of
              Nothing -> fail "missing payload field"
              Just (Aeson.Object payloadObj) -> do
                KeyMap.lookup "targetDate" payloadObj
                  `shouldBe` Just (Aeson.String "2026-01-15")
                KeyMap.lookup "storagePath" payloadObj
                  `shouldBe` Just (Aeson.String "gs://bucket/path.ndjson")
                case KeyMap.lookup "sourceStatus" payloadObj of
                  Nothing -> fail "missing sourceStatus in payload"
                  Just (Aeson.Object ssObj) ->
                    KeyMap.lookup "jp" ssObj `shouldBe` Just (Aeson.String "ok")
                  Just other -> fail ("unexpected sourceStatus: " <> show other)
              Just other -> fail ("unexpected payload: " <> show other)
          Just other -> fail ("expected JSON object, got: " <> show other)

    -- TC-INFRA-007: buildMarketCollectFailedEvent — real builder path, SCREAMING_SNAKE reasonCode
    describe "TC-INFRA-007: buildMarketCollectFailedEvent" $ do
      it "CloudEvent JSON has eventType=market.collect.failed and SCREAMING_SNAKE reasonCode" $ do
        let targetDay = fromGregorian 2026 1 15
            now = UTCTime targetDay 0
            traceUlid = testUlid
            event =
              buildMarketCollectFailedEvent
                testUlid
                now
                traceUlid
                DataSourceUnavailable
                Nothing
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) -> do
            KeyMap.lookup "eventType" obj
              `shouldBe` Just (Aeson.String "market.collect.failed")
            KeyMap.lookup "schemaVersion" obj
              `shouldBe` Just (Aeson.String "1.0.0")
            case KeyMap.lookup "payload" obj of
              Nothing -> fail "missing payload field"
              Just (Aeson.Object payloadObj) ->
                -- Must be SCREAMING_SNAKE_CASE per error-codes.json contract
                KeyMap.lookup "reasonCode" payloadObj
                  `shouldBe` Just (Aeson.String "DATA_SOURCE_UNAVAILABLE")
              Just other -> fail ("unexpected payload: " <> show other)
          Just other -> fail ("expected JSON object, got: " <> show other)

      it "all 8 ReasonCode values serialize to SCREAMING_SNAKE_CASE" $ do
        let targetDay = fromGregorian 2026 1 15
            now = UTCTime targetDay 0
            traceUlid = testUlid
            extractReasonCodeText reasonCode =
              let event =
                    buildMarketCollectFailedEvent
                      testUlid
                      now
                      traceUlid
                      reasonCode
                      Nothing
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
        extractReasonCodeText ComplianceSourceUnapproved
          `shouldBe` Just (Aeson.String "COMPLIANCE_SOURCE_UNAPPROVED")
        extractReasonCodeText DataSourceTimeout
          `shouldBe` Just (Aeson.String "DATA_SOURCE_TIMEOUT")
        extractReasonCodeText DataSourceUnavailable
          `shouldBe` Just (Aeson.String "DATA_SOURCE_UNAVAILABLE")
        extractReasonCodeText DataSchemaInvalid
          `shouldBe` Just (Aeson.String "DATA_SCHEMA_INVALID")
        extractReasonCodeText IdempotencyDuplicateEvent
          `shouldBe` Just (Aeson.String "IDEMPOTENCY_DUPLICATE_EVENT")
        extractReasonCodeText StateConflict
          `shouldBe` Just (Aeson.String "STATE_CONFLICT")
        extractReasonCodeText DependencyTimeout
          `shouldBe` Just (Aeson.String "DEPENDENCY_TIMEOUT")

      it "includes detail field when present" $ do
        let targetDay = fromGregorian 2026 1 15
            now = UTCTime targetDay 0
            traceUlid = testUlid
            event =
              buildMarketCollectFailedEvent
                testUlid
                now
                traceUlid
                DataSourceTimeout
                (Just "connection refused")
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "detail" payloadObj
                  `shouldSatisfy` (\v -> v == Just (Aeson.String "connection refused"))
              _ -> fail "missing payload"
          _ -> fail "could not decode"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 4 of
  Right ulid -> ulid
  Left _ -> error "test ulid"
