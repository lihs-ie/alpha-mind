module UseCase.RecordInsightAudit (
  -- * Port
  InsightAuditPort (..),

  -- * Value Objects
  InsightAuditResult (..),
  InsightAuditEntry (..),

  -- * Use case
  recordInsightAudit,
) where

import Data.Time (Day)
import Domain.InsightCollection (Trace)
import Domain.InsightCollection.Aggregate (InsightCollectionIdentifier, SourceCollectionStatus)
import Domain.InsightCollection.ReasonCode (ReasonCode)

-- ---------------------------------------------------------------------
-- Port (UC-11)
-- ---------------------------------------------------------------------

{- | InsightAuditPort: インサイト収集監査ログの書き込みを抽象化する Port。
実装は infra/Cloud Logging 層（Issue #54）に委ねる。
-}
class (Monad m) => InsightAuditPort m where
  writeInsightAudit :: InsightCollectionIdentifier -> Trace -> InsightAuditEntry -> m ()

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

-- | 監査結果の2値。
data InsightAuditResult
  = Succeeded
  | Failed
  deriving stock (Eq, Show)

{- | インサイト収集監査エントリ（Cloud Logging の logFields 仕様に準拠）。
UC-11: trace/identifier/result/reasonCode（失敗時）を含める。
-}
data InsightAuditEntry = InsightAuditEntry
  { result :: InsightAuditResult
  , reasonCode :: Maybe ReasonCode
  , targetDate :: Day
  , sourceStatus :: Maybe [SourceCollectionStatus]
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case (UC-11)
-- ---------------------------------------------------------------------

{- | UC-IC-02: インサイト収集結果を監査ログへ記録する。
業務ルール判定ロジックを持たない（オーケストレーションのみ）。
監査記録の失敗は全体フローを失敗させない（best-effort、呼び出し側で catch する）。
-}
recordInsightAudit ::
  (InsightAuditPort m) =>
  InsightCollectionIdentifier ->
  Trace ->
  InsightAuditEntry ->
  m ()
recordInsightAudit = writeInsightAudit
