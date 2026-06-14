{- | insight-collector 専用の冪等性キー連携バインディング。

Must-INFRA-018: idempotency_keys コレクションを使用した全イベント処理の冪等性保証。
  - service は "insight-collector" 固定。
  - docId は共有 Persistence.Idempotency が "insight-collector:{identifier}" として構築する。
  - 実際の reserve/complete 呼び出し（Pub/Sub ハンドラ境界への配線）は Issue #54 presentation 層で行う。
-}
module Infrastructure.Idempotency.InsightIdempotency (
  reserveInsightIdempotency,
  completeInsightIdempotency,
) where

import Domain.InsightCollection (Trace (..))
import Domain.InsightCollection.Aggregate (InsightCollectionIdentifier (..))
import Persistence.Firestore (FirestoreContext)
import Persistence.Idempotency (
  IdempotencyError,
  ReserveResult,
  completeIdempotency,
  reserveIdempotency,
 )

{- | insight-collector サービスの冪等性キーを予約する。

内部で @Persistence.Idempotency.reserveIdempotency context "insight-collector" identifier.value trace.value@ を呼ぶ。
Issue #54 の Pub/Sub ハンドラ境界がこの関数を呼び出す。
-}
reserveInsightIdempotency ::
  FirestoreContext ->
  InsightCollectionIdentifier ->
  Trace ->
  IO (Either IdempotencyError ReserveResult)
reserveInsightIdempotency context collectionIdentifier trace =
  reserveIdempotency
    context
    "insight-collector"
    collectionIdentifier.value
    trace.value

{- | insight-collector サービスの冪等性キーを完了状態にする。

内部で @Persistence.Idempotency.completeIdempotency context "insight-collector" identifier.value@ を呼ぶ。
Issue #54 の Pub/Sub ハンドラ境界がこの関数を呼び出す。
-}
completeInsightIdempotency ::
  FirestoreContext ->
  InsightCollectionIdentifier ->
  IO (Either IdempotencyError ())
completeInsightIdempotency context collectionIdentifier =
  completeIdempotency
    context
    "insight-collector"
    collectionIdentifier.value
