# portfolio-planner API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: portfolio-planner

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/portfolio-planner.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- `signal.generated` 受信から `orders.proposed` / `orders.proposal.failed` 発行までを実装可能な粒度で検証する。
- 残高参照失敗時の停止、冪等性、提案根拠保存を対象とする。

## 3. テスト対象API（イベント契約）

| API-ID | 種別 | topic | 優先度 |
|---|---|---|---|
| PP-API-01 | Event購読 | `event-signal-generated-v1` | P0 |
| PP-API-02 | Event発行 | `event-orders-proposed-v1` | P0 |
| PP-API-03 | Event発行 | `event-orders-proposal-failed-v1` | P0 |

## 4. テスト環境と前提

```bash
export BASE_URL="http://localhost:3005"
export PUBSUB_URL="http://localhost:8085"
export PROJECT_ID="alpha-mind-local"
```

補助関数:

```bash
publish_event() {
  topic="$1"
  json="$2"
  data=$(printf '%s' "$json" | base64 | tr -d '\n')
  curl -sS -X POST "$PUBSUB_URL/v1/projects/$PROJECT_ID/topics/$topic:publish" \
    -H 'content-type: application/json' \
    -d "{\"messages\":[{\"data\":\"$data\"}]}" | jq .
}

create_pull_sub() {
  sub="$1"; topic="$2"
  curl -sS -X PUT "$PUBSUB_URL/v1/projects/$PROJECT_ID/subscriptions/$sub" \
    -H 'content-type: application/json' \
    -d "{\"topic\":\"projects/$PROJECT_ID/topics/$topic\",\"ackDeadlineSeconds\":60}" | jq .
}

pull_one() {
  sub="$1"
  curl -sS -X POST "$PUBSUB_URL/v1/projects/$PROJECT_ID/subscriptions/$sub:pull" \
    -H 'content-type: application/json' \
    -d '{"maxMessages":1}' | jq .
}
```

## 5. 詳細テストケース

| TC-ID | 観点 | 優先度 | 期待結果 |
|---|---|---|---|
| PP-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| PP-IT-002 | 正常提案 | P0 | `orders.proposed` 受信 |
| PP-IT-003 | 入力欠損 | P0 | `orders.proposal.failed` 受信 |
| PP-IT-004 | 冪等性 | P0 | 重複提案なし |
| PP-IT-005 | trace伝播 | P0 | 同一trace |

### PP-IT-001

```bash
curl -si "$BASE_URL/healthz"
```

### PP-IT-002

```bash
create_pull_sub sub-it-orders-proposed event-orders-proposed-v1

publish_event event-signal-generated-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAE",
  "eventType":"signal.generated",
  "occurredAt":"2026-03-05T00:30:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAE",
  "schemaVersion":"1.0.0",
  "payload":{
    "signalVersion":"signal-v1",
    "modelVersion":"model-v1",
    "featureVersion":"feature-v1",
    "storagePath":"gs://alpha-mind-local/signal/signal-v1.parquet",
    "modelDiagnostics":{"degradationFlag":"normal","requiresComplianceReview":false}
  }
}'

pull_one sub-it-orders-proposed
```

### PP-IT-003

```bash
create_pull_sub sub-it-orders-proposal-failed event-orders-proposal-failed-v1

publish_event event-signal-generated-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAF",
  "eventType":"signal.generated",
  "occurredAt":"2026-03-05T00:31:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAF",
  "schemaVersion":"1.0.0",
  "payload":{
    "signalVersion":"signal-v1",
    "featureVersion":"feature-v1",
    "storagePath":"gs://alpha-mind-local/signal/signal-v1.parquet"
  }
}'

pull_one sub-it-orders-proposal-failed
```

### PP-IT-004

- 同一identifierイベントの再送で `orders.proposed` が重複しないことを確認する。

### PP-IT-005

- 出力イベントの `trace` が入力イベントと一致することを確認する。

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/portfolio-planner/{yyyyMMdd}/`

## 7. エントリ/イグジット基準

エントリ:
- Firestoreシード済み

イグジット:
- P0成功率100%
- 重大欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
