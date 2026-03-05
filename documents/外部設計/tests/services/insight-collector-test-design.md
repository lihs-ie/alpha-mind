# insight-collector API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: insight-collector

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/insight-collector.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- `insight.collect.requested` 受信から `insight.collected` / `insight.collect.failed` 発行までを実装可能な粒度で検証する。
- ソース許可制御、部分失敗、規約違反時の拒否、trace伝播を対象とする。

## 3. テスト対象API（イベント契約）

| API-ID | 種別 | topic | 優先度 |
|---|---|---|---|
| IC-API-01 | Event購読 | `event-insight-collect-requested-v1` | P0 |
| IC-API-02 | Event発行 | `event-insight-collected-v1` | P0 |
| IC-API-03 | Event発行 | `event-insight-collect-failed-v1` | P0 |

## 4. テスト環境と前提

```bash
export BASE_URL="http://localhost:3009"
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
| IC-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| IC-IT-002 | 正常収集 | P0 | `insight.collected` 受信 |
| IC-IT-003 | 不許可/不正入力 | P0 | `insight.collect.failed` 受信 |
| IC-IT-004 | 部分失敗 | P0 | `partialFailure=true` |
| IC-IT-005 | trace伝播 | P0 | 同一trace |

### IC-IT-001

```bash
curl -si "$BASE_URL/healthz"
```

### IC-IT-002

```bash
create_pull_sub sub-it-insight-collected event-insight-collected-v1

publish_event event-insight-collect-requested-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAJ",
  "eventType":"insight.collect.requested",
  "occurredAt":"2026-03-05T01:00:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAJ",
  "schemaVersion":"1.0.0",
  "payload":{
    "targetDate":"2026-03-05",
    "requestedBy":"scheduler",
    "sourceTypes":["x","youtube"],
    "options":{"forceRecollect":false,"dryRun":false,"maxItemsPerSource":50}
  }
}'

pull_one sub-it-insight-collected
```

### IC-IT-003

```bash
create_pull_sub sub-it-insight-failed event-insight-collect-failed-v1

publish_event event-insight-collect-requested-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAK",
  "eventType":"insight.collect.requested",
  "occurredAt":"2026-03-05T01:01:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAK",
  "schemaVersion":"1.0.0",
  "payload":{"requestedBy":"scheduler"}
}'

pull_one sub-it-insight-failed
```

### IC-IT-004

- 一部ソース失敗条件で実行し、`insight.collected.payload.partialFailure=true` を確認する。

### IC-IT-005

- 出力イベントの `trace` が入力と一致すること。

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/insight-collector/{yyyyMMdd}/`

## 7. エントリ/イグジット基準

エントリ:
- source policyシード投入済み

イグジット:
- P0成功率100%
- 重大欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
