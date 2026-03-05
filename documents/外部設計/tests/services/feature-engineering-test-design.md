# feature-engineering API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: feature-engineering

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/feature-engineering.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- `market.collected` 受信から `features.generated` / `features.generation.failed` 発行までを実装可能な粒度で検証する。
- 定性×定量融合、単位同期、時系列健全性、失敗通知を対象とする。

## 3. テスト対象API（イベント契約）

| API-ID | 種別 | topic | 優先度 |
|---|---|---|---|
| FE-API-01 | Event購読 | `event-market-collected-v1` | P0 |
| FE-API-02 | Event発行 | `event-features-generated-v1` | P0 |
| FE-API-03 | Event発行 | `event-features-generation-failed-v1` | P0 |

## 4. テスト環境と前提

```bash
export BASE_URL="http://localhost:3003"
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
| FE-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| FE-IT-002 | 正常特徴量生成 | P0 | `features.generated` 受信 |
| FE-IT-003 | 入力欠損 | P0 | `features.generation.failed` 受信 |
| FE-IT-004 | 冪等性 | P0 | 二重生成なし |
| FE-IT-005 | trace伝播 | P0 | 同一trace |

### FE-IT-001

```bash
curl -si "$BASE_URL/healthz"
```

### FE-IT-002

```bash
create_pull_sub sub-it-features-generated event-features-generated-v1

publish_event event-market-collected-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAA",
  "eventType":"market.collected",
  "occurredAt":"2026-03-05T00:10:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAA",
  "schemaVersion":"1.0.0",
  "payload":{"targetDate":"2026-03-05","storagePath":"gs://alpha-mind-local/market/2026-03-05.parquet","sourceStatus":{"jp":"ok","us":"ok"}}
}'

pull_one sub-it-features-generated
```

### FE-IT-003

```bash
create_pull_sub sub-it-features-failed event-features-generation-failed-v1

publish_event event-market-collected-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAB",
  "eventType":"market.collected",
  "occurredAt":"2026-03-05T00:11:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAB",
  "schemaVersion":"1.0.0",
  "payload":{"targetDate":"2026-03-05","sourceStatus":{"jp":"ok","us":"ok"}}
}'

pull_one sub-it-features-failed
```

### FE-IT-004

- 同一 `identifier` の `market.collected` を2回 publish し、`features.generated` が重複しないことを確認する。

### FE-IT-005

- `pull_one` の結果イベントで `trace` が入力と一致すること。

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/feature-engineering/{yyyyMMdd}/`

## 7. エントリ/イグジット基準

エントリ:
- Pub/Sub / Firestore / GCS emulator稼働中

イグジット:
- P0成功率100%
- 重大欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
