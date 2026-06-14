module Infrastructure.Publisher.PubSubInsightEventPublisherSpec (spec) where

import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Time (UTCTime (..), fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.InsightCollection.Aggregate (
  InsightArtifact (..),
  InsightCollectionIdentifier (..),
  SourceCollectionStatus (..),
  SourceOutcome (..),
  SourceType (..),
 )
import Domain.InsightCollection.ReasonCode (ReasonCode (..))
import Infrastructure.Publisher.PubSubInsightEventPublisher (
  buildInsightCollectFailedEvent,
  buildInsightCollectedEvent,
 )
import Test.Hspec (Spec, describe, it, shouldBe)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 1 of Right u -> u; Left _ -> error "test ulid"

sampleArtifact :: InsightArtifact
sampleArtifact =
  InsightArtifact
    { identifier = InsightCollectionIdentifier{value = testUlid}
    , count = 42
    , storagePath = "gs://alpha-mind-insights/2026-06-14/insights.json"
    , sourceStatus =
        [ SourceCollectionStatus{sourceType = X, status = SourceSuccess}
        , SourceCollectionStatus{sourceType = YouTube, status = SourceSuccess}
        , SourceCollectionStatus{sourceType = Paper, status = SourceFailed}
        , SourceCollectionStatus{sourceType = GitHub, status = QuotaExhausted}
        ]
    , partialFailure = True
    }

sampleNow :: UTCTime
sampleNow = UTCTime (fromGregorian 2026 6 14) 0

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "PubSubInsightEventPublisherT" $ do
    describe "buildInsightCollectedEvent" $ do
      it "Must-INFRA-020: eventType is insight.collected" $ do
        let event = buildInsightCollectedEvent testUlid sampleNow testUlid sampleArtifact
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            KeyMap.lookup "eventType" obj `shouldBe` Just (Aeson.String "insight.collected")
          Just _ -> fail "expected JSON object"

      it "Must-INFRA-020: schemaVersion is 1.0.0" $ do
        let event = buildInsightCollectedEvent testUlid sampleNow testUlid sampleArtifact
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            KeyMap.lookup "schemaVersion" obj `shouldBe` Just (Aeson.String "1.0.0")
          Just _ -> fail "expected JSON object"

      it "Must-INFRA-020: payload count is 42" $ do
        let event = buildInsightCollectedEvent testUlid sampleNow testUlid sampleArtifact
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "count" payloadObj `shouldBe` Just (Aeson.Number 42)
              _ -> fail "missing payload object"
          Just _ -> fail "expected JSON object"

      it "Must-INFRA-020: payload storagePath is correct" $ do
        let event = buildInsightCollectedEvent testUlid sampleNow testUlid sampleArtifact
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "storagePath" payloadObj
                  `shouldBe` Just (Aeson.String "gs://alpha-mind-insights/2026-06-14/insights.json")
              _ -> fail "missing payload object"
          Just _ -> fail "expected JSON object"

      it "Must-INFRA-020: payload sourceStatus has 4 entries" $ do
        let event = buildInsightCollectedEvent testUlid sampleNow testUlid sampleArtifact
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                case KeyMap.lookup "sourceStatus" payloadObj of
                  Just (Aeson.Array arr) -> length arr `shouldBe` 4
                  _ -> fail "missing sourceStatus array"
              _ -> fail "missing payload object"
          Just _ -> fail "expected JSON object"

    describe "buildInsightCollectFailedEvent" $ do
      it "Must-INFRA-021: eventType is insight.collect.failed" $ do
        let event = buildInsightCollectFailedEvent testUlid sampleNow testUlid DependencyTimeout Nothing
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            KeyMap.lookup "eventType" obj `shouldBe` Just (Aeson.String "insight.collect.failed")
          Just _ -> fail "expected JSON object"

      it "Must-INFRA-021: reasonCode maps DependencyTimeout to DEPENDENCY_TIMEOUT" $ do
        let event = buildInsightCollectFailedEvent testUlid sampleNow testUlid DependencyTimeout Nothing
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "reasonCode" payloadObj
                  `shouldBe` Just (Aeson.String "DEPENDENCY_TIMEOUT")
              _ -> fail "missing payload object"
          Just _ -> fail "expected JSON object"

      it "Must-INFRA-021: reasonCode maps DataSchemaInvalid to DATA_SCHEMA_INVALID" $ do
        let event = buildInsightCollectFailedEvent testUlid sampleNow testUlid DataSchemaInvalid Nothing
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "reasonCode" payloadObj
                  `shouldBe` Just (Aeson.String "DATA_SCHEMA_INVALID")
              _ -> fail "missing payload object"
          Just _ -> fail "expected JSON object"

      it "Must-INFRA-021: detail is omitted when Nothing" $ do
        let event = buildInsightCollectFailedEvent testUlid sampleNow testUlid DependencyTimeout Nothing
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "detail" payloadObj `shouldBe` Nothing
              _ -> fail "missing payload object"
          Just _ -> fail "expected JSON object"

      it "Must-INFRA-021: detail is included when Just" $ do
        let event = buildInsightCollectFailedEvent testUlid sampleNow testUlid DependencyTimeout (Just "connection timeout after 30s")
            jsonBytes = Aeson.encode event
        case Aeson.decode jsonBytes :: Maybe Aeson.Value of
          Nothing -> fail "could not decode CloudEvent JSON"
          Just (Aeson.Object obj) ->
            case KeyMap.lookup "payload" obj of
              Just (Aeson.Object payloadObj) ->
                KeyMap.lookup "detail" payloadObj
                  `shouldBe` Just (Aeson.String "connection timeout after 30s")
              _ -> fail "missing payload object"
          Just _ -> fail "expected JSON object"

      it "Must-INFRA-021: all 7 ReasonCode values serialize to SCREAMING_SNAKE_CASE" $ do
        let reasonCodes =
              [ (RequestValidationFailed, "REQUEST_VALIDATION_FAILED")
              , (ComplianceSourceUnapproved, "COMPLIANCE_SOURCE_UNAPPROVED")
              , (DependencyTimeout, "DEPENDENCY_TIMEOUT")
              , (DependencyUnavailable, "DEPENDENCY_UNAVAILABLE")
              , (DataSchemaInvalid, "DATA_SCHEMA_INVALID")
              , (StateConflict, "STATE_CONFLICT")
              , (IdempotencyDuplicateEvent, "IDEMPOTENCY_DUPLICATE_EVENT")
              ]
        mapM_
          ( \(reasonCode, expected) -> do
              let event = buildInsightCollectFailedEvent testUlid sampleNow testUlid reasonCode Nothing
                  jsonBytes = Aeson.encode event
              case Aeson.decode jsonBytes :: Maybe Aeson.Value of
                Just (Aeson.Object obj) ->
                  case KeyMap.lookup "payload" obj of
                    Just (Aeson.Object payloadObj) ->
                      KeyMap.lookup "reasonCode" payloadObj
                        `shouldBe` Just (Aeson.String expected)
                    _ -> fail "missing payload object"
                _ -> fail "could not decode CloudEvent JSON"
          )
          reasonCodes
