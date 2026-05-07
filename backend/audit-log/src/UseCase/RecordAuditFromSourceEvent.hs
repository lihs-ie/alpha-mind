module UseCase.RecordAuditFromSourceEvent (
  -- * Result
  RecordAuditResult (..),

  -- * Port
  AuditEventPublisher (..),

  -- * Use case
  recordAuditFromSourceEvent,

  -- * Helpers
  buildPayloadDigest,
)
where

import Control.Monad (when)
import Data.Aeson (Value (..))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Time (UTCTime)
import Domain.AuditLog (Service)
import Domain.AuditLog.AuditIngestion (
  AuditIngestion,
  AuditIngestionIdentifier,
  AuditIngestionRepository (..),
  DispatchDecision (..),
  TargetEventType (..),
  decideDispatch,
  isDuplicate,
  markFailed,
  markProcessed,
  startIngestion,
 )
import Domain.AuditLog.AuditRecord (
  AuditArchive (..),
  AuditArchiveRepository (..),
  AuditRecord,
  AuditRecordIdentifier,
  AuditRecordRepository (..),
  PayloadDigest (..),
  PayloadSummaryValue (..),
  SourceEventSnapshot (..),
  markRecorded,
  summarizePayload,
 )
import Domain.AuditLog.AuditRecordFactory qualified as Factory
import Domain.AuditLog.Error (DomainError)
import Domain.AuditLog.ReasonCode (ReasonCode (..))
import Domain.AuditLog.Specification (
  RawSourceEvent,
  isEligibleForPublication,
  validateSourceEventEnvelope,
 )

-- ---------------------------------------------------------------------
-- Result
-- ---------------------------------------------------------------------

data RecordAuditResult
  = Recorded
  | Duplicate
  | SchemaInvalid DomainError
  | WriteFailed Text
  | RecordAuditDomainError DomainError
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Port
-- ---------------------------------------------------------------------

class (Monad m) => AuditEventPublisher m where
  publishAuditRecorded :: AuditRecord -> m ()

-- ---------------------------------------------------------------------
-- Use case
-- ---------------------------------------------------------------------

-- | UC-AU-01: 業務イベントを監査レコードとして正規化・永続化する。
recordAuditFromSourceEvent ::
  ( AuditRecordRepository m
  , AuditIngestionRepository m
  , AuditArchiveRepository m
  , AuditEventPublisher m
  ) =>
  UTCTime ->
  AuditRecordIdentifier ->
  AuditIngestionIdentifier ->
  RawSourceEvent ->
  Service ->
  m RecordAuditResult
recordAuditFromSourceEvent currentTime recordIdentifier ingestionIdentifier rawEvent service =
  case validateSourceEventEnvelope rawEvent of
    Left domainError -> pure (SchemaInvalid domainError)
    Right snapshot -> processValidatedEvent currentTime recordIdentifier ingestionIdentifier snapshot service

processValidatedEvent ::
  ( AuditRecordRepository m
  , AuditIngestionRepository m
  , AuditArchiveRepository m
  , AuditEventPublisher m
  ) =>
  UTCTime ->
  AuditRecordIdentifier ->
  AuditIngestionIdentifier ->
  SourceEventSnapshot ->
  Service ->
  m RecordAuditResult
processValidatedEvent currentTime recordIdentifier ingestionIdentifier snapshot service = do
  -- RULE-AU-002: 冪等性チェック
  existingIngestion <- Domain.AuditLog.AuditIngestion.find ingestionIdentifier
  case existingIngestion of
    Just existing | isDuplicate existing -> pure Duplicate
    _ -> do
      -- 冪等キーの作成
      let ingestion = startIngestion ingestionIdentifier snapshot.trace
      Domain.AuditLog.AuditIngestion.persist ingestion
      -- RULE-AU-003, RULE-AU-004: 監査レコード生成・正規化
      case Factory.fromSourceEvent recordIdentifier snapshot service of
        Left domainError -> do
          handleIngestionFailure ingestion DataSchemaInvalid
          pure (SchemaInvalid domainError)
        Right (record, _events) ->
          recordAndArchive currentTime ingestion record

recordAndArchive ::
  ( AuditRecordRepository m
  , AuditIngestionRepository m
  , AuditArchiveRepository m
  , AuditEventPublisher m
  ) =>
  UTCTime ->
  AuditIngestion ->
  AuditRecord ->
  m RecordAuditResult
recordAndArchive currentTime ingestion record = do
  -- payload 要約
  let digest = buildPayloadDigest record.sourceEventSnapshot.payload
  case summarizePayload digest record of
    Left domainError -> pure (RecordAuditDomainError domainError)
    Right summarized ->
      -- INV-AU-001: recorded 状態へ遷移
      case markRecorded currentTime summarized of
        Left domainError -> pure (RecordAuditDomainError domainError)
        Right (recorded, _events) -> do
          Domain.AuditLog.AuditRecord.persist recorded
          -- Cloud Logging アーカイブ（best-effort）
          persistArchive (toAuditArchive recorded)
          -- 冪等キーを処理済みに遷移
          case markProcessed currentTime ingestion of
            Left domainError -> pure (RecordAuditDomainError domainError)
            Right processedIngestion -> do
              -- RULE-AU-005: 発行判定
              let decision = buildDispatchDecision recorded
              case decideDispatch decision processedIngestion of
                Left _ -> do
                  Domain.AuditLog.AuditIngestion.persist processedIngestion
                  pure Recorded
                Right dispatchedIngestion -> do
                  Domain.AuditLog.AuditIngestion.persist dispatchedIngestion
                  -- audit.recorded 発行（best-effort）
                  when (isEligibleForPublication recorded && decision.shouldPublish) $
                    publishAuditRecorded recorded
                  pure Recorded

-- ---------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------

handleIngestionFailure ::
  (AuditIngestionRepository m) =>
  AuditIngestion ->
  ReasonCode ->
  m ()
handleIngestionFailure ingestion code =
  case markFailed code ingestion of
    Right failedIngestion -> Domain.AuditLog.AuditIngestion.persist failedIngestion
    Left _ -> pure ()

buildDispatchDecision :: AuditRecord -> DispatchDecision
buildDispatchDecision record
  | isEligibleForPublication record =
      DispatchDecision
        { shouldPublish = True
        , targetEventType = Just AuditRecorded
        , reasonCode = Nothing
        }
  | otherwise =
      DispatchDecision
        { shouldPublish = False
        , targetEventType = Nothing
        , reasonCode = record.reasonCode
        }

toAuditArchive :: AuditRecord -> AuditArchive
toAuditArchive record =
  AuditArchive
    { trace = record.trace
    , identifier = record.identifier
    , eventType = record.eventType
    , payloadSummary = record.payloadSummary
    }

-- | payload の JSON 値からトップレベルキーを抽出し PayloadDigest を構築する。
buildPayloadDigest :: Value -> PayloadDigest
buildPayloadDigest (Object keyMap) =
  let keys = map Key.toText (KeyMap.keys keyMap)
      summaryMap = Map.fromList (concatMap (extractSummaryEntry keyMap) keys)
   in PayloadDigest
        { fieldCount = KeyMap.size keyMap
        , topLevelKeys = keys
        , summary = summaryMap
        }
buildPayloadDigest _ =
  PayloadDigest
    { fieldCount = 0
    , topLevelKeys = []
    , summary = Map.empty
    }

extractSummaryEntry :: KeyMap.KeyMap Value -> Text -> [(Text, PayloadSummaryValue)]
extractSummaryEntry keyMap key =
  case KeyMap.lookup (Key.fromText key) keyMap of
    Just (String s) -> [(key, SummaryString s)]
    Just (Number n) -> [(key, SummaryNumber (realToFrac n))]
    Just (Bool b) -> [(key, SummaryBool b)]
    _ -> []
