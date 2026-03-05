# execution API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: execution

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/execution.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- `orders.approved` 受信から `orders.executed` / `orders.execution.failed` / `hypothesis.demo.completed` 発行までを実装可能な粒度で検証する。
- 外部ブローカー障害時の失敗制御、冪等性、状態整合を対象とする。

## 3. テスト対象API（イベント契約）

| API-ID | 種別 | topic | 優先度 |
|---|---|---|---|
| EX-API-01 | Event購読 | `event-orders-approved-v1` | P0 |
| EX-API-02 | Event発行 | `event-orders-executed-v1` | P0 |
| EX-API-03 | Event発行 | `event-orders-execution-failed-v1` | P0 |
| EX-API-04 | Event発行 | `event-hypothesis-demo-completed-v1` | P1 |

## 4. テスト環境と前提

```bash
export BASE_URL="http://localhost:3007"
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
| EX-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| EX-IT-002 | 承認注文の正常執行 | P0 | `orders.executed` 受信 |
| EX-IT-003 | 入力不備 | P0 | `orders.execution.failed` 受信 |
| EX-IT-004 | 冪等性 | P0 | 二重執行なし |
| EX-IT-005 | デモ完了通知 | P1 | `hypothesis.demo.completed` 受信 |

### EX-IT-001

```bash
curl -si "$BASE_URL/healthz"
```

### EX-IT-002

```bash
create_pull_sub sub-it-orders-executed event-orders-executed-v1

publish_event event-orders-approved-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAG",
  "eventType":"orders.approved",
  "occurredAt":"2026-03-05T00:40:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAG",
  "schemaVersion":"1.0.0",
  "payload":{"identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAG","decision":"approved","actionReasonCode":"MANUAL_OPERATION"}
}'

pull_one sub-it-orders-executed
```

### EX-IT-003

```bash
create_pull_sub sub-it-orders-exec-failed event-orders-execution-failed-v1

publish_event event-orders-approved-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAH",
  "eventType":"orders.approved",
  "occurredAt":"2026-03-05T00:41:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAH",
  "schemaVersion":"1.0.0",
  "payload":{"decision":"approved"}
}'

pull_one sub-it-orders-exec-failed
```

### EX-IT-004

- 同一identifierを連続投入し、出力が二重にならないことを確認する。

### EX-IT-005

- デモモード入力条件で `hypothesis.demo.completed` が発行されることを確認する。

```bash
create_pull_sub sub-it-hypothesis-demo-completed event-hypothesis-demo-completed-v1
# デモモード条件のorders.approvedイベントを投入（運用設定に依存）
pull_one sub-it-hypothesis-demo-completed
```

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/execution/{yyyyMMdd}/`

## 7. エントリ/イグジット基準

エントリ:
- ブローカー接続先（stub/実体）が準備済み

イグジット:
- P0成功率100%
- 重大欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
