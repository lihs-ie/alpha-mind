# signal-generator API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: signal-generator

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/signal-generator.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- `features.generated` 受信から `signal.generated` / `signal.generation.failed` 発行までを実装可能な粒度で検証する。
- モデル品質ゲート、冪等性、監査属性を対象とする。

## 3. テスト対象API（イベント契約）

| API-ID | 種別 | topic | 優先度 |
|---|---|---|---|
| SG-API-01 | Event購読 | `event-features-generated-v1` | P0 |
| SG-API-02 | Event発行 | `event-signal-generated-v1` | P0 |
| SG-API-03 | Event発行 | `event-signal-generation-failed-v1` | P0 |

## 4. テスト環境と前提

```bash
export BASE_URL="http://localhost:3004"
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
| SG-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| SG-IT-002 | 正常推論 | P0 | `signal.generated` 受信 |
| SG-IT-003 | 入力欠損 | P0 | `signal.generation.failed` 受信 |
| SG-IT-004 | 冪等性 | P0 | 重複出力なし |
| SG-IT-005 | 監査属性 | P0 | modelVersion/featureVersion/trace 保持 |

### SG-IT-001

```bash
curl -si "$BASE_URL/healthz"
```

### SG-IT-002

```bash
create_pull_sub sub-it-signal-generated event-signal-generated-v1

publish_event event-features-generated-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAC",
  "eventType":"features.generated",
  "occurredAt":"2026-03-05T00:20:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAC",
  "schemaVersion":"1.0.0",
  "payload":{"targetDate":"2026-03-05","featureVersion":"feature-v1","storagePath":"gs://alpha-mind-local/features/feature-v1.parquet"}
}'

pull_one sub-it-signal-generated
```

### SG-IT-003

```bash
create_pull_sub sub-it-signal-failed event-signal-generation-failed-v1

publish_event event-features-generated-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAD",
  "eventType":"features.generated",
  "occurredAt":"2026-03-05T00:21:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAD",
  "schemaVersion":"1.0.0",
  "payload":{"targetDate":"2026-03-05","storagePath":"gs://alpha-mind-local/features/feature-v1.parquet"}
}'

pull_one sub-it-signal-failed
```

### SG-IT-004

- 同一 `identifier` を再送し、出力重複が起きないことを確認する。

### SG-IT-005

- `signal.generated.payload` に `modelVersion` と `featureVersion` があることを確認する。

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/signal-generator/{yyyyMMdd}/`

## 7. エントリ/イグジット基準

エントリ:
- 推論依存（モデル参照先）が疎通可能

イグジット:
- P0成功率100%
- 重大欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
