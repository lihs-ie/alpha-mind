module Domain.AuditLog.AuditRecordFactory (
  fromSourceEvent,
)
where

import Domain.AuditLog (Service)
import Domain.AuditLog.AuditRecord (
  AuditRecord,
  AuditRecordEvent,
  AuditRecordIdentifier,
  SourceEventSnapshot (..),
  acceptSourceEvent,
  extractReasonFromPayload,
  normalizeReason,
  normalizeResultFromEventType,
 )
import Domain.AuditLog.Error (DomainError)

{- | SourceEvent から AuditRecord を生成する。
  eventType に基づく result 正規化と payload に基づく reason 抽出を適用する。
-}
fromSourceEvent ::
  AuditRecordIdentifier ->
  SourceEventSnapshot ->
  Service ->
  Either DomainError (AuditRecord, [AuditRecordEvent])
fromSourceEvent recordIdentifier snapshot svc = do
  let initialResult = normalizeResultFromEventType snapshot.eventType
      (reason, reasonSource) = extractReasonFromPayload snapshot.payload
      (record, events) = acceptSourceEvent recordIdentifier snapshot svc initialResult
  normalizedRecord <- normalizeReason reason reasonSource record
  pure (normalizedRecord, events)
