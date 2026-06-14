{- | ProposalAuditWriter — MUST-11, MUST-12, MUST-13, MUST-14.
Orchestration only: no business rule logic, no eligibility check.
-}
module UseCase.ProposalAuditWriter (
  -- * Port
  ProposalAuditPort (..),

  -- * Value objects
  ProposalAuditRecord (..),
  ProposalAuditResult (..),

  -- * Use case
  recordProposalAudit,
) where

import Data.Time (UTCTime)
import Domain.OrderProposal (Trace)
import Domain.OrderProposal.ProposalDispatch (ProposalDispatchIdentifier)
import Domain.OrderProposal.ReasonCode (ReasonCode)

-- ---------------------------------------------------------------------
-- Port (MUST-11, MUST-12)
-- ---------------------------------------------------------------------

{- | ProposalAuditPort: 提案監査ログの書き込みを抽象化する Port。
実装は infra / Cloud Logging 層に委ねる。
業務ルール判定ロジックを持たない (MUST-12)。
-}
class (Monad m) => ProposalAuditPort m where
  writeProposalAudit :: ProposalAuditRecord -> m ()

-- ---------------------------------------------------------------------
-- Value objects (MUST-14)
-- ---------------------------------------------------------------------

-- | ProposalAuditResult — 提案監査結果の 2 値。
data ProposalAuditResult
  = AuditSucceeded
  | AuditFailed
  deriving stock (Eq, Show)

{- | ProposalAuditRecord — 監査ログエントリ。
MUST-14: identifier / result / reasonCode (失敗時) / trace の 4 項目を必ず含む。
-}
data ProposalAuditRecord = ProposalAuditRecord
  { identifier :: ProposalDispatchIdentifier
  , result :: ProposalAuditResult
  , reasonCode :: Maybe ReasonCode
  , trace :: Trace
  , processedAt :: UTCTime
  }
  deriving stock (Eq, Show)

-- ---------------------------------------------------------------------
-- Use case (MUST-11, MUST-13)
-- ---------------------------------------------------------------------

{- | recordProposalAudit — 提案結果を監査ログへ記録する。
MUST-12: 業務ルール判定ロジックを持たない純粋なオーケストレーションのみ。
MUST-13: 呼び出し元 (PortfolioPlanningService) がドメイン状態確定後に呼び出す責務を持つ。
         このモジュール自体は受け取ったレコードをそのままポートへ委譲するのみ。
-}
recordProposalAudit :: (ProposalAuditPort m) => ProposalAuditRecord -> m ()
recordProposalAudit = writeProposalAudit
