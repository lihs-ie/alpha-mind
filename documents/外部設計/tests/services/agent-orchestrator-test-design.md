# agent-orchestrator API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: agent-orchestrator

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/agent-orchestrator.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- `insight.collected` / `hypothesis.retest.requested` 受信から `hypothesis.proposed` / `hypothesis.proposal.failed` 発行までを実装可能な粒度で検証する。
- 必須属性付与、重複抑止、テンプレート適用、trace伝播を対象とする。

## 3. テスト対象API（イベント契約）

| API-ID | 種別 | topic | 優先度 |
|---|---|---|---|
| AO-API-01 | Event購読 | `event-insight-collected-v1` | P0 |
| AO-API-02 | Event購読 | `event-hypothesis-retest-requested-v1` | P0 |
| AO-API-03 | Event発行 | `event-hypothesis-proposed-v1` | P0 |
| AO-API-04 | Event発行 | `event-hypothesis-proposal-failed-v1` | P0 |

## 4. テスト環境と前提

```bash
export BASE_URL="http://localhost:3010"
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
| AO-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| AO-IT-002 | insight入力で仮説生成 | P0 | `hypothesis.proposed` 受信 |
| AO-IT-003 | retest入力 | P0 | `hypothesis.proposed` または `failed` |
| AO-IT-004 | 入力欠損 | P0 | `hypothesis.proposal.failed` |
| AO-IT-005 | 必須属性 | P0 | payload必須項目を保持 |

### AO-IT-001

```bash
curl -si "$BASE_URL/healthz"
```

### AO-IT-002

```bash
create_pull_sub sub-it-hypothesis-proposed event-hypothesis-proposed-v1

publish_event event-insight-collected-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAL",
  "eventType":"insight.collected",
  "occurredAt":"2026-03-05T01:20:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAL",
  "schemaVersion":"1.0.0",
  "payload":{
    "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAL",
    "count":10,
    "storagePath":"gs://alpha-mind-local/insight/2026-03-05.json",
    "sourceStatus":[{"sourceType":"x","status":"success","collectedCount":10}],
    "partialFailure":false
  }
}'

pull_one sub-it-hypothesis-proposed
```

### AO-IT-003

```bash
publish_event event-hypothesis-retest-requested-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAM",
  "eventType":"hypothesis.retest.requested",
  "occurredAt":"2026-03-05T01:21:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAM",
  "schemaVersion":"1.0.0",
  "payload":{"identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAM"}
}'
```

### AO-IT-004

```bash
create_pull_sub sub-it-hypothesis-proposal-failed event-hypothesis-proposal-failed-v1

publish_event event-insight-collected-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAN",
  "eventType":"insight.collected",
  "occurredAt":"2026-03-05T01:22:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAN",
  "schemaVersion":"1.0.0",
  "payload":{"count":0}
}'

pull_one sub-it-hypothesis-proposal-failed
```

### AO-IT-005

- `hypothesis.proposed.payload` に `identifier`,`symbol`,`instrumentType`,`title`,`sourceEvidence`,`skillVersion`,`instructionProfileVersion` があることを確認する。

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/agent-orchestrator/{yyyyMMdd}/`

## 7. エントリ/イグジット基準

エントリ:
- skill_registry / failure_knowledge シード済み

イグジット:
- P0成功率100%
- 重大欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
