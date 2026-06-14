module Infrastructure.Logging.CloudLoggingCollectionAuditWriterSpec (spec) where

import Data.Aeson (Value (..))
import Data.HashMap.Strict qualified as HashMap
import Data.Maybe (isJust)
import Data.Time (fromGregorian)
import Data.ULID (ULID, ulidFromInteger)
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  MarketCollectionIdentifier (..),
  MarketSourceStatus (..),
  SourceStatus (..),
 )
import Domain.MarketCollection.ReasonCode (ReasonCode (..))
import Infrastructure.Logging.CloudLoggingCollectionAuditWriter (buildLogContext)
import Observability.Logging (LogContext (..))
import Test.Hspec (Spec, describe, it, shouldBe, shouldSatisfy)
import UseCase.RecordCollectionAudit (
  CollectionAuditEntry (..),
  CollectionResult (..),
 )

spec :: Spec
spec = do
  describe "CloudLoggingCollectionAuditWriterT" $ do
    -- Must-23: service field is fixed "data-collector"
    describe "Must-23: buildLogContext service name" $ do
      it "sets service to data-collector" $ do
        let logContext = buildLogContext testIdentifier testTrace testSucceededEntry
        logContext.service `shouldBe` "data-collector"

    -- Must-23: result field
    describe "Must-23: result field" $ do
      it "sets result to 'success' for Succeeded" $ do
        let logContext = buildLogContext testIdentifier testTrace testSucceededEntry
        logContext.result `shouldBe` Just "success"

      it "sets result to 'failed' for Failed" $ do
        let logContext = buildLogContext testIdentifier testTrace testFailedEntry
        logContext.result `shouldBe` Just "failed"

    -- Must-23: reasonCode wire format (SCREAMING_SNAKE_CASE)
    describe "Must-23: reasonCode in SCREAMING_SNAKE_CASE" $ do
      it "is Nothing when entry has no reasonCode" $ do
        let logContext = buildLogContext testIdentifier testTrace testSucceededEntry
        logContext.reasonCode `shouldBe` Nothing

      it "is DATA_SOURCE_UNAVAILABLE for DataSourceUnavailable" $ do
        let entry = makeFailedEntry (Just DataSourceUnavailable)
            logContext = buildLogContext testIdentifier testTrace entry
        logContext.reasonCode `shouldBe` Just "DATA_SOURCE_UNAVAILABLE"

      it "is REQUEST_VALIDATION_FAILED for RequestValidationFailed" $ do
        let entry = makeFailedEntry (Just RequestValidationFailed)
            logContext = buildLogContext testIdentifier testTrace entry
        logContext.reasonCode `shouldBe` Just "REQUEST_VALIDATION_FAILED"

      it "is DATA_SCHEMA_INVALID for DataSchemaInvalid" $ do
        let entry = makeFailedEntry (Just DataSchemaInvalid)
            logContext = buildLogContext testIdentifier testTrace entry
        logContext.reasonCode `shouldBe` Just "DATA_SCHEMA_INVALID"

      it "is DEPENDENCY_TIMEOUT for DependencyTimeout" $ do
        let entry = makeFailedEntry (Just DependencyTimeout)
            logContext = buildLogContext testIdentifier testTrace entry
        logContext.reasonCode `shouldBe` Just "DEPENDENCY_TIMEOUT"

    -- Must-23: payloadSummary fields
    describe "Must-23: payloadSummary" $ do
      it "includes targetDate in payloadSummary" $ do
        let logContext = buildLogContext testIdentifier testTrace testSucceededEntry
        case logContext.payloadSummary of
          Nothing -> fail "expected payloadSummary"
          Just summaryMap ->
            HashMap.lookup "targetDate" summaryMap
              `shouldSatisfy` (\v -> v == Just (String "2026-01-15"))

      it "includes sourceStatus ok/ok when both sources succeed" $ do
        let entry = makeSucceededEntry (Just (SourceStatus Ok Ok))
            logContext = buildLogContext testIdentifier testTrace entry
        case logContext.payloadSummary of
          Nothing -> fail "expected payloadSummary"
          Just summaryMap ->
            HashMap.lookup "sourceStatus" summaryMap
              `shouldBe` Just (String "ok/ok")

      it "includes sourceStatus failed/ok when JP source fails" $ do
        let entry = makeSucceededEntry (Just (SourceStatus SourceFailed Ok))
            logContext = buildLogContext testIdentifier testTrace entry
        case logContext.payloadSummary of
          Nothing -> fail "expected payloadSummary"
          Just summaryMap ->
            HashMap.lookup "sourceStatus" summaryMap
              `shouldBe` Just (String "failed/ok")

      it "includes sourceStatus unknown when sourceStatus is Nothing" $ do
        let entry = makeSucceededEntry Nothing
            logContext = buildLogContext testIdentifier testTrace entry
        case logContext.payloadSummary of
          Nothing -> fail "expected payloadSummary"
          Just summaryMap ->
            HashMap.lookup "sourceStatus" summaryMap
              `shouldBe` Just (String "unknown")

    -- Must-23: identifier and trace are set
    describe "Must-23: identifier and trace fields" $ do
      it "sets identifier from collectionIdentifier" $ do
        let logContext = buildLogContext testIdentifier testTrace testSucceededEntry
        logContext.identifier `shouldSatisfy` isJust

      it "sets trace from traceValue" $ do
        let logContext = buildLogContext testIdentifier testTrace testSucceededEntry
        logContext.trace `shouldSatisfy` isJust

      it "eventType is Nothing (audit log does not emit eventType)" $ do
        let logContext = buildLogContext testIdentifier testTrace testSucceededEntry
        logContext.eventType `shouldBe` Nothing

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

testUlid :: ULID
testUlid = case ulidFromInteger 7 of
  Right ulid -> ulid
  Left _ -> error "test ulid"

testIdentifier :: MarketCollectionIdentifier
testIdentifier = MarketCollectionIdentifier{value = testUlid}

testTrace :: Trace
testTrace = Trace{value = testUlid}

testSucceededEntry :: CollectionAuditEntry
testSucceededEntry =
  CollectionAuditEntry
    { result = Succeeded
    , reasonCode = Nothing
    , targetDate = fromGregorian 2026 1 15
    , sourceStatus = Just (SourceStatus Ok Ok)
    }

testFailedEntry :: CollectionAuditEntry
testFailedEntry =
  CollectionAuditEntry
    { result = Failed
    , reasonCode = Just DataSourceUnavailable
    , targetDate = fromGregorian 2026 1 15
    , sourceStatus = Nothing
    }

makeFailedEntry :: Maybe ReasonCode -> CollectionAuditEntry
makeFailedEntry code =
  CollectionAuditEntry
    { result = Failed
    , reasonCode = code
    , targetDate = fromGregorian 2026 1 15
    , sourceStatus = Nothing
    }

makeSucceededEntry :: Maybe SourceStatus -> CollectionAuditEntry
makeSucceededEntry status =
  CollectionAuditEntry
    { result = Succeeded
    , reasonCode = Nothing
    , targetDate = fromGregorian 2026 1 15
    , sourceStatus = status
    }
