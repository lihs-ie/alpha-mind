{-# LANGUAGE OverloadedRecordDot #-}

{- | Cloud Logging implementation of 'CollectionAuditPort'.

Must-22: CloudLoggingCollectionAuditWriterT newtype wrapping ReaderT.
Must-23: writeCollectionAudit calls logInfoWith with structured context including
         service, trace, identifier, result, reasonCode, payloadSummary.
-}
module Infrastructure.Logging.CloudLoggingCollectionAuditWriter (
  -- * Environment
  CloudLoggingCollectionAuditWriterEnv (..),

  -- * Monad transformer
  CloudLoggingCollectionAuditWriterT (..),
  runCloudLoggingCollectionAuditWriterT,

  -- * Pure helpers (exported for tests — Must-23)
  buildLogContext,
) where

import Control.Monad.IO.Class (liftIO)
import Control.Monad.Trans.Reader (ReaderT (..), ask)
import Data.Aeson (Value)
import Data.Aeson qualified as Aeson
import Data.HashMap.Strict (HashMap)
import Data.HashMap.Strict qualified as HashMap
import Data.Text (Text)
import Data.Text qualified as Text
import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (
  MarketCollectionIdentifier (..),
  MarketSourceStatus (..),
  SourceStatus (..),
 )
import Infrastructure.Wire.ReasonCodeWire (reasonCodeToWire)
import Observability.Logging (LogContext (..), LogEnv, logInfoWith)
import UseCase.RecordCollectionAudit (
  CollectionAuditEntry (..),
  CollectionAuditPort (..),
  CollectionResult (..),
 )

-- ---------------------------------------------------------------------------
-- Environment
-- ---------------------------------------------------------------------------

newtype CloudLoggingCollectionAuditWriterEnv = CloudLoggingCollectionAuditWriterEnv
  { logEnv :: LogEnv
  }

-- ---------------------------------------------------------------------------
-- Monad transformer
-- ---------------------------------------------------------------------------

newtype CloudLoggingCollectionAuditWriterT m a = CloudLoggingCollectionAuditWriterT
  { unCloudLoggingCollectionAuditWriterT :: ReaderT CloudLoggingCollectionAuditWriterEnv m a
  }
  deriving newtype (Functor, Applicative, Monad)

runCloudLoggingCollectionAuditWriterT ::
  CloudLoggingCollectionAuditWriterEnv ->
  CloudLoggingCollectionAuditWriterT m a ->
  m a
runCloudLoggingCollectionAuditWriterT environment action =
  runReaderT (unCloudLoggingCollectionAuditWriterT action) environment

-- ---------------------------------------------------------------------------
-- CollectionAuditPort instance
-- Must-22 / Must-23
-- ---------------------------------------------------------------------------

instance CollectionAuditPort (CloudLoggingCollectionAuditWriterT IO) where
  writeCollectionAudit collectionIdentifier traceValue entry =
    CloudLoggingCollectionAuditWriterT $ do
      environment <- ask
      liftIO $ do
        let logContext = buildLogContext collectionIdentifier traceValue entry
        logInfoWith environment.logEnv logContext "collection.audit"

-- ---------------------------------------------------------------------------
-- Pure LogContext builder (exported for Must-23 contract tests)
-- ---------------------------------------------------------------------------

{- | Build the structured 'LogContext' for a collection audit entry.

Pure function exported for testing — callers can verify the service name,
reasonCode wire format, result text, and payloadSummary fields without
needing a live 'LogEnv'.
-}
buildLogContext ::
  MarketCollectionIdentifier ->
  Trace ->
  CollectionAuditEntry ->
  LogContext
buildLogContext collectionIdentifier traceValue entry =
  let resultText = collectionResultToText entry.result
      reasonCodeText = fmap reasonCodeToWire entry.reasonCode
      payloadSummaryMap = buildPayloadSummary entry
   in LogContext
        { service = "data-collector"
        , trace = Just (Text.pack (show traceValue.value))
        , identifier = Just (Text.pack (show collectionIdentifier.value))
        , eventType = Nothing
        , reasonCode = reasonCodeText
        , result = Just resultText
        , payloadSummary = Just payloadSummaryMap
        }

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

collectionResultToText :: CollectionResult -> Text
collectionResultToText Succeeded = "success"
collectionResultToText Failed = "failed"

buildPayloadSummary :: CollectionAuditEntry -> HashMap Text Value
buildPayloadSummary entry =
  let targetDateValue = Aeson.String (Text.pack (show entry.targetDate))
      sourceStatusValue = case entry.sourceStatus of
        Nothing -> Aeson.String "unknown"
        Just (SourceStatus jpStatus usStatus) ->
          Aeson.String
            ( marketSourceStatusToText jpStatus
                <> "/"
                <> marketSourceStatusToText usStatus
            )
   in HashMap.fromList
        [ ("targetDate", targetDateValue)
        , ("sourceStatus", sourceStatusValue)
        ]

marketSourceStatusToText :: MarketSourceStatus -> Text
marketSourceStatusToText Ok = "ok"
marketSourceStatusToText SourceFailed = "failed"
