# audit-log API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: audit-log

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/audit-log.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- 全業務イベントの監査記録取り込みを実装可能な粒度で検証する。
- 必須属性、冪等性、trace検索復元、記録遅延を対象とする。

## 3. テスト対象API（イベント契約）

| API-ID | 種別 | 契約 | 優先度 |
|---|---|---|---|
| AU-API-01 | Event購読 | 全業務イベント（24種） | P0 |
| AU-API-02 | DB保存 | Firestore `audit_logs` | P0 |
| AU-API-03 | Event発行 | `event-audit-recorded-v1`（任意） | P1 |

## 4. テスト環境と前提

```bash
export BASE_URL="http://localhost:3008"
export PUBSUB_URL="http://localhost:8085"
export PROJECT_ID="alpha-mind-local"
export FIRESTORE_URL="http://localhost:8080/v1/projects/$PROJECT_ID/databases/(default)/documents"
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
```

## 5. 詳細テストケース

| TC-ID | 観点 | 優先度 | 期待結果 |
|---|---|---|---|
| AU-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| AU-IT-002 | イベント記録 | P0 | `audit_logs` に保存 |
| AU-IT-003 | 必須属性 | P0 | 必須項目が保存される |
| AU-IT-004 | 重複受信 | P0 | 二重記録なし |
| AU-IT-005 | trace検索 | P0 | traceで時系列復元可能 |

### AU-IT-001

```bash
curl -si "$BASE_URL/healthz"
```

### AU-IT-002

```bash
publish_event event-orders-proposed-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAW",
  "eventType":"orders.proposed",
  "occurredAt":"2026-03-05T02:20:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAW",
  "schemaVersion":"1.0.0",
  "payload":{"identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAW","orderCount":1,"orders":[{"identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAW","symbol":"AAPL","side":"BUY","qty":1}]}
}'

sleep 2
curl -sS "$FIRESTORE_URL/audit_logs?pageSize=50" | jq .
```

### AU-IT-003

```bash
curl -sS "$FIRESTORE_URL/audit_logs?pageSize=200" | \
  jq '.documents[] | {eventType:.fields.eventType.stringValue,trace:.fields.trace.stringValue,identifier:.fields.identifier.stringValue}'
```

確認点:
- `identifier`,`eventType`,`occurredAt`,`trace`,`service`,`result` が存在。

### AU-IT-004

- 同一identifierのイベントを再publishし、監査記録が重複しないことを確認する。

### AU-IT-005

```bash
TRACE="01ARZ3NDEKTSV4RRFFQ69G5FAW"
curl -sS "$FIRESTORE_URL/audit_logs?pageSize=200" | \
  jq --arg t "$TRACE" '.documents[] | select(.fields.trace.stringValue==$t)'
```

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/audit-log/{yyyyMMdd}/`

## 7. エントリ/イグジット基準

エントリ:
- Firestore emulator稼働中

イグジット:
- P0成功率100%
- 重大欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
