module Domain.OrderExecution.Error (
  DomainError (..),
)
where

import Data.Text (Text)

-- | execution ドメイン層のコマンド拒否・不変条件違反を表す。
data DomainError
  = -- | 状態遷移が不正 (現状態, 試行コマンド)。
    InvalidStateTransition Text Text
  | -- | 必須項目欠損。
    MissingRequiredFields [Text]
  | -- | 不変条件違反 (対象, 詳細)。
    InvariantViolation Text Text
  | -- | 既に処理済み (冪等扱い)。
    AlreadyProcessed
  deriving stock (Eq, Show)
