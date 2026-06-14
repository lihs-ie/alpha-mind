module Domain.HypothesisOrchestration.Error (
  DomainError (..),
) where

import Data.Text (Text)
import Domain.HypothesisOrchestration.ReasonCode (ReasonCode)

-- | Must-35: ドメイン層エラー型。ReasonCode フィールドを持つ構造。
data DomainError
  = -- | 不正な状態遷移。(現在状態ラベル, コマンド名, 理由コード)
    InvalidStateTransition Text Text ReasonCode
  | -- | 必須フィールド欠損。欠損フィールド名リスト。
    MissingRequiredFields [Text] ReasonCode
  | -- | 集約の不変条件違反。(集約名, 不変条件説明)
    InvariantViolation Text Text ReasonCode
  | -- | 既に処理済み（冪等性）
    AlreadyProcessed ReasonCode
  deriving stock (Eq, Show)
