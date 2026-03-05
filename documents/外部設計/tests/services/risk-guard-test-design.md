# risk-guard API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: risk-guard

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/risk-guard.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml`（イベント）, `POST /internal/orders/{identifier}/approve|reject`（内部API） |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- `orders.proposed` / `operation.kill_switch.changed` 受信から `orders.approved` / `orders.rejected` 発行までを実装可能な粒度で検証する。
- fail-closed、理由コード整合、内部API認可を対象とする。

## 3. テスト対象API

| API-ID | 種別 | topic/path | 優先度 |
|---|---|---|---|
| RG-API-01 | Event購読 | `event-orders-proposed-v1` | P0 |
| RG-API-02 | Event購読 | `event-operation-kill-switch-changed-v1` | P0 |
| RG-API-03 | Event発行 | `event-orders-approved-v1` | P0 |
| RG-API-04 | Event発行 | `event-orders-rejected-v1` | P0 |
| RG-API-05 | HTTP内部 | `/internal/orders/{identifier}/approve|reject` | P1 |

## 4. テスト環境と前提

```bash
export BASE_URL="http://localhost:3006"
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
| RG-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| RG-IT-002 | 正常承認 | P0 | `orders.approved` |
| RG-IT-003 | kill-switch有効時拒否 | P0 | `orders.rejected` |
| RG-IT-004 | 入力欠損時fail-closed | P0 | `orders.rejected` + reasonCode |
| RG-IT-005 | 内部API認可 | P1 | 401/403 または許可主体のみ200 |

### RG-IT-001

```bash
curl -si "$BASE_URL/healthz"
```

### RG-IT-002

```bash
create_pull_sub sub-it-orders-approved event-orders-approved-v1

publish_event event-orders-proposed-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAS",
  "eventType":"orders.proposed",
  "occurredAt":"2026-03-05T02:00:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAS",
  "schemaVersion":"1.0.0",
  "payload":{"identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAS","orderCount":1,"orders":[{"identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAS","symbol":"AAPL","side":"BUY","qty":1}]}
}'

pull_one sub-it-orders-approved
```

### RG-IT-003

```bash
create_pull_sub sub-it-orders-rejected event-orders-rejected-v1

publish_event event-operation-kill-switch-changed-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAT",
  "eventType":"operation.kill_switch.changed",
  "occurredAt":"2026-03-05T02:01:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAT",
  "schemaVersion":"1.0.0",
  "payload":{"enabled":true,"reason":"integration-test"}
}'

publish_event event-orders-proposed-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAU",
  "eventType":"orders.proposed",
  "occurredAt":"2026-03-05T02:01:10Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAU",
  "schemaVersion":"1.0.0",
  "payload":{"identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAU","orderCount":1,"orders":[{"identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAU","symbol":"AAPL","side":"BUY","qty":1}]}
}'

pull_one sub-it-orders-rejected
```

### RG-IT-004

```bash
publish_event event-orders-proposed-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAV",
  "eventType":"orders.proposed",
  "occurredAt":"2026-03-05T02:02:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAV",
  "schemaVersion":"1.0.0",
  "payload":{"orderCount":1}
}'
```

確認点:
- `orders.rejected` が発行され、`reasonCode` が付与される。

### RG-IT-005

```bash
curl -si -X POST "$BASE_URL/internal/orders/01ARZ3NDEKTSV4RRFFQ69G5FAV/approve" \
  -H 'content-type: application/json' \
  -d '{"actionReasonCode":"MANUAL_OPERATION"}'
```

確認点:
- 認可設計どおりに 401/403 または許可主体のみ200。

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/risk-guard/{yyyyMMdd}/`

## 7. エントリ/イグジット基準

エントリ:
- リスク設定/kill-switch状態が既知

イグジット:
- P0成功率100%
- 重大欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
