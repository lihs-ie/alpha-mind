{-# LANGUAGE OverloadedRecordDot #-}

{- | data-collector 専用の冪等性キー連携バインディング。

Must-17: `idempotency_keys` コレクションを使用した全イベント処理の冪等性保証。
  - service は "data-collector" 固定。
  - docId は共有 `Persistence.Idempotency` が "data-collector:{identifier}" として構築する。
  - 実際の reserve/complete 呼び出し（Pub/Sub ハンドラ境界への配線）は Issue #28 presentation 層で行う。
-}
module Infrastructure.Idempotency.CollectionIdempotency (
  reserveCollectionIdempotency,
  completeCollectionIdempotency,
) where

import Domain.MarketCollection (Trace (..))
import Domain.MarketCollection.Aggregate (MarketCollectionIdentifier (..))
import Persistence.Firestore (FirestoreContext)
import Persistence.Idempotency (
  IdempotencyError,
  ReserveResult,
  completeIdempotency,
  reserveIdempotency,
 )

{- | data-collector サービスの冪等性キーを予約する。

内部で @Persistence.Idempotency.reserveIdempotency context "data-collector" identifier.value trace.value@ を呼ぶ。
Issue #28 の Pub/Sub ハンドラ境界がこの関数を呼び出す。
-}
reserveCollectionIdempotency ::
  FirestoreContext ->
  MarketCollectionIdentifier ->
  Trace ->
  IO (Either IdempotencyError ReserveResult)
reserveCollectionIdempotency context marketCollectionIdentifier trace =
  reserveIdempotency
    context
    "data-collector"
    marketCollectionIdentifier.value
    trace.value

{- | data-collector サービスの冪等性キーを完了状態にする。

内部で @Persistence.Idempotency.completeIdempotency context "data-collector" identifier.value@ を呼ぶ。
Issue #28 の Pub/Sub ハンドラ境界がこの関数を呼び出す。
-}
completeCollectionIdempotency ::
  FirestoreContext ->
  MarketCollectionIdentifier ->
  IO (Either IdempotencyError ())
completeCollectionIdempotency context marketCollectionIdentifier =
  completeIdempotency
    context
    "data-collector"
    marketCollectionIdentifier.value
