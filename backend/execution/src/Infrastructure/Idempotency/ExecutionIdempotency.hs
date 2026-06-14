{-# LANGUAGE OverloadedRecordDot #-}

{- | execution サービス専用の冪等性キー連携バインディング。

  - service は "execution" 固定。
  - docId は共有 'Persistence.Idempotency' が "execution:{identifier}" として構築する。
  - 実際の reserve/complete 呼び出し（Pub/Sub ハンドラ境界への配線）は Issue #49 presentation 層で行う。
-}
module Infrastructure.Idempotency.ExecutionIdempotency (
  reserveExecutionIdempotency,
  completeExecutionIdempotency,
) where

import Domain.OrderExecution (Trace (..))
import Domain.OrderExecution.Aggregate (OrderExecutionIdentifier (..))
import Persistence.Firestore (FirestoreContext)
import Persistence.Idempotency (
  IdempotencyError,
  ReserveResult,
  completeIdempotency,
  reserveIdempotency,
 )

{- | execution サービスの冪等性キーを予約する。

内部で @Persistence.Idempotency.reserveIdempotency context "execution" identifier.value trace.value@ を呼ぶ。
Issue #49 の Pub/Sub ハンドラ境界がこの関数を呼び出す。
-}
reserveExecutionIdempotency ::
  FirestoreContext ->
  OrderExecutionIdentifier ->
  Trace ->
  IO (Either IdempotencyError ReserveResult)
reserveExecutionIdempotency context executionIdentifier trace =
  reserveIdempotency
    context
    "execution"
    executionIdentifier.value
    trace.value

{- | execution サービスの冪等性キーを完了状態にする。

内部で @Persistence.Idempotency.completeIdempotency context "execution" identifier.value@ を呼ぶ。
Issue #49 の Pub/Sub ハンドラ境界がこの関数を呼び出す。
-}
completeExecutionIdempotency ::
  FirestoreContext ->
  OrderExecutionIdentifier ->
  IO (Either IdempotencyError ())
completeExecutionIdempotency context executionIdentifier =
  completeIdempotency
    context
    "execution"
    executionIdentifier.value
