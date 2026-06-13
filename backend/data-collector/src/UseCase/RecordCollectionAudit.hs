module UseCase.RecordCollectionAudit (
  -- * Port
  CollectionAuditPort (..),

  -- * Value Objects
  CollectionResult (..),
  CollectionAuditEntry (..),

  -- * Use case
  recordCollectionAudit,
) where

import Data.Time (Day)
import Domain.MarketCollection (Trace)
import Domain.MarketCollection.Aggregate (MarketCollectionIdentifier, SourceStatus)
import Domain.MarketCollection.ReasonCode (ReasonCode)

-- ---------------------------------------------------------------------
-- Port (Must-06)
-- ---------------------------------------------------------------------

{- | CollectionAuditPort: 収集監査ログの書き込みを抽象化する Port。
実装は infra/Cloud Logging 層（#26）に委ねる。
-}
class (Monad m) => CollectionAuditPort m where
  writeCollectionAudit :: MarketCollectionIdentifier -> Trace -> CollectionAuditEntry -> m ()

-- ---------------------------------------------------------------------
-- Value Objects
-- ---------------------------------------------------------------------

-- | 収集結果の2値。
data CollectionResult
  = Succeeded
  | Failed
  deriving stock (Eq, Show)

{- | 収集監査エントリ（Cloud Logging の logFields 仕様に準拠）。
設計判断: result/reasonCode/targetDate/sourceStatus の4項目。
-}
data CollectionAuditEntry = CollectionAuditEntry
  { result :: CollectionResult
  , reasonCode :: Maybe ReasonCode
  , targetDate :: Day
  , sourceStatus :: Maybe SourceStatus
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case (Must-03)
-- ---------------------------------------------------------------------

{- | UC-DC-02: 収集結果を監査ログへ記録する。
業務ルール判定ロジックを持たない（オーケストレーションのみ）。
-}
recordCollectionAudit ::
  (CollectionAuditPort m) =>
  MarketCollectionIdentifier ->
  Trace ->
  CollectionAuditEntry ->
  m ()
recordCollectionAudit = writeCollectionAudit
