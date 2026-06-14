{- | Must-16 RULE-EX-002 INV-EX-003: ExecutionIdempotencyPolicy — ドメインサービス（純粋）。
既処理 identifier 集合から重複発注を判定する。外部 API を触らない。
重複処理防止キーの永続化は 'IdempotencyKeyRepository'（Port）に委ねる。
-}
module Domain.OrderExecution.ExecutionIdempotencyPolicy (
  -- * Idempotency Key
  IdempotencyKey (..),

  -- * Policy (pure)
  isDuplicateDispatch,

  -- * Repository Port
  IdempotencyKeyRepository (..),
) where

import Data.Set (Set)
import Data.Set qualified as Set
import Domain.OrderExecution.Aggregate (OrderExecutionIdentifier)

{- | 重複処理防止キー。idempotency_keys/{identifier}。
execution では注文 identifier 単位で外部発注の一意性を担保する。
-}
newtype IdempotencyKey = IdempotencyKey {value :: OrderExecutionIdentifier}
  deriving stock (Eq, Ord, Show)

{- | Must-16: 既処理 identifier 集合に対象が含まれるか（重複発注か）を判定する純粋関数。
True のとき外部発注を再実行してはならない（INV-EX-003 は冪等扱い）。
-}
isDuplicateDispatch :: Set OrderExecutionIdentifier -> OrderExecutionIdentifier -> Bool
isDuplicateDispatch processed orderIdentifier = Set.member orderIdentifier processed

{- | Must-13: IdempotencyKeyRepository 型クラス Port（実装は infra 層）。
§4.5.1 命名規則: Find / Persist / Terminate。
-}
class (Monad m) => IdempotencyKeyRepository m where
  find :: OrderExecutionIdentifier -> m (Maybe IdempotencyKey)
  persist :: IdempotencyKey -> m ()
  terminate :: OrderExecutionIdentifier -> m ()
