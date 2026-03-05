# data-collector API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: data-collector

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/data-collector.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- `market.collect.requested` 受信から `market.collected` / `market.collect.failed` 発行までを実装可能な粒度で検証する。
- 対象はイベント契約整合、外部依存障害時の失敗制御、冪等性、監査追跡。

## 3. テスト対象API（イベント契約）

| API-ID | 種別 | topic | 優先度 | 主要リスク |
|---|---|---|---|---|
| DC-API-01 | Event購読 | `event-market-collect-requested-v1` | P0 | トリガー未処理 |
| DC-API-02 | Event発行 | `event-market-collected-v1` | P0 | 正常結果不整合 |
| DC-API-03 | Event発行 | `event-market-collect-failed-v1` | P0 | 障害通知漏れ |

## 4. テスト環境と前提

```bash
cd docker
make up

export BASE_URL="http://localhost:3002"
export PUBSUB_URL="http://localhost:8085"
export PROJECT_ID="alpha-mind-local"
export TRACE_ID="01ARZ3NDEKTSV4RRFFQ69G5FAV"
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
| DC-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| DC-IT-002 | 正常収集イベント | P0 | `market.collected` を受信 |
| DC-IT-003 | 不正入力イベント | P0 | `market.collect.failed` を受信 |
| DC-IT-004 | 冪等性 | P0 | 同一identifierで二重保存しない |
| DC-IT-005 | trace伝播 | P0 | 入出力で同一traceを確認 |

### DC-IT-001 ヘルスチェック

```bash
curl -si "$BASE_URL/healthz"
```

### DC-IT-002 正常収集イベント

```bash
create_pull_sub sub-it-market-collected event-market-collected-v1

publish_event event-market-collect-requested-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAV",
  "eventType":"market.collect.requested",
  "occurredAt":"2026-03-05T00:00:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAV",
  "schemaVersion":"1.0.0",
  "payload":{"targetDate":"2026-03-05","requestedBy":"scheduler","mode":"daily"}
}'

pull_one sub-it-market-collected
```

### DC-IT-003 不正入力イベント（targetDate欠落）

```bash
create_pull_sub sub-it-market-failed event-market-collect-failed-v1

publish_event event-market-collect-requested-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FBX",
  "eventType":"market.collect.requested",
  "occurredAt":"2026-03-05T00:01:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FBX",
  "schemaVersion":"1.0.0",
  "payload":{"requestedBy":"scheduler"}
}'

pull_one sub-it-market-failed
```

### DC-IT-004 冪等性（同一identifier再送）

```bash
publish_event event-market-collect-requested-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FZZ",
  "eventType":"market.collect.requested",
  "occurredAt":"2026-03-05T00:02:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FZZ",
  "schemaVersion":"1.0.0",
  "payload":{"targetDate":"2026-03-05","requestedBy":"scheduler"}
}'

publish_event event-market-collect-requested-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FZZ",
  "eventType":"market.collect.requested",
  "occurredAt":"2026-03-05T00:02:10Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FZZ",
  "schemaVersion":"1.0.0",
  "payload":{"targetDate":"2026-03-05","requestedBy":"scheduler"}
}'
```

確認点:
- 出力件数が意図せず増えない。

### DC-IT-005 trace伝播

- `pull_one` で取得したイベント本文に `trace=入力trace` が含まれること。

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/data-collector/{yyyyMMdd}/`

必須証跡:
- publishリクエスト
- pullレスポンス
- trace相関結果

## 7. エントリ/イグジット基準

エントリ:
- `make up` 完了
- Pub/Sub emulator疎通確認済み

イグジット:
- P0成功率100%
- Critical/High欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
