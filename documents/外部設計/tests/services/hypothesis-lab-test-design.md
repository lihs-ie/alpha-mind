# hypothesis-lab API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: hypothesis-lab

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連設計 | `documents/外部設計/services/hypothesis-lab.md` |
| API契約 | `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- `hypothesis.proposed` / `hypothesis.demo.completed` 受信から `hypothesis.backtested` / `hypothesis.promoted` / `hypothesis.rejected` 発行までを実装可能な粒度で検証する。
- 昇格制約、自己申告、失敗知見登録、trace伝播を対象とする。

## 3. テスト対象API（イベント契約）

| API-ID | 種別 | topic | 優先度 |
|---|---|---|---|
| HL-API-01 | Event購読 | `event-hypothesis-proposed-v1` | P0 |
| HL-API-02 | Event購読 | `event-hypothesis-demo-completed-v1` | P0 |
| HL-API-03 | Event発行 | `event-hypothesis-backtested-v1` | P0 |
| HL-API-04 | Event発行 | `event-hypothesis-promoted-v1` | P0 |
| HL-API-05 | Event発行 | `event-hypothesis-rejected-v1` | P0 |

## 4. テスト環境と前提

```bash
export BASE_URL="http://localhost:3011"
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
| HL-IT-001 | ヘルスチェック | P1 | `/healthz` = 200 |
| HL-IT-002 | 仮説バックテスト | P0 | `hypothesis.backtested` |
| HL-IT-003 | 昇格可条件 | P0 | `hypothesis.promoted` |
| HL-IT-004 | 昇格不可条件 | P0 | `hypothesis.rejected` |
| HL-IT-005 | 必須監査属性 | P0 | 判定属性保持 |

### HL-IT-001

```bash
curl -si "$BASE_URL/healthz"
```

### HL-IT-002

```bash
create_pull_sub sub-it-hypothesis-backtested event-hypothesis-backtested-v1

publish_event event-hypothesis-proposed-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAP",
  "eventType":"hypothesis.proposed",
  "occurredAt":"2026-03-05T01:40:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAP",
  "schemaVersion":"1.0.0",
  "payload":{
    "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAP",
    "symbol":"1306.T",
    "instrumentType":"ETF",
    "title":"rebound hypothesis",
    "sourceEvidence":["insight-1"],
    "skillVersion":"skill-v1",
    "instructionProfileVersion":"profile-v1"
  }
}'

pull_one sub-it-hypothesis-backtested
```

### HL-IT-003

```bash
create_pull_sub sub-it-hypothesis-promoted event-hypothesis-promoted-v1

publish_event event-hypothesis-demo-completed-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAQ",
  "eventType":"hypothesis.demo.completed",
  "occurredAt":"2026-03-05T01:41:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAQ",
  "schemaVersion":"1.0.0",
  "payload":{
    "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAQ",
    "demoRun":"demo-1","symbol":"1306.T","instrumentType":"ETF","insiderRisk":"low",
    "startedAt":"2026-01-01T00:00:00Z","endedAt":"2026-03-01T00:00:00Z","demoPeriodDays":60,
    "promotable":true,"requiresComplianceReview":false,"mnpiSelfDeclared":true
  }
}'

pull_one sub-it-hypothesis-promoted
```

### HL-IT-004

```bash
create_pull_sub sub-it-hypothesis-rejected event-hypothesis-rejected-v1

publish_event event-hypothesis-demo-completed-v1 '{
  "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAR",
  "eventType":"hypothesis.demo.completed",
  "occurredAt":"2026-03-05T01:42:00Z",
  "trace":"01ARZ3NDEKTSV4RRFFQ69G5FAR",
  "schemaVersion":"1.0.0",
  "payload":{
    "identifier":"01ARZ3NDEKTSV4RRFFQ69G5FAR",
    "demoRun":"demo-2","symbol":"7203.T","instrumentType":"STOCK","insiderRisk":"medium",
    "startedAt":"2026-01-01T00:00:00Z","endedAt":"2026-03-01T00:00:00Z","demoPeriodDays":60,
    "promotable":false,"requiresComplianceReview":true,"mnpiSelfDeclared":false
  }
}'

pull_one sub-it-hypothesis-rejected
```

### HL-IT-005

- 出力イベントに `trace` と判定根拠属性が含まれることを確認する。

## 6. 証跡取得

保存先:
- `documents/外部設計/tests/evidence/hypothesis-lab/{yyyyMMdd}/`

## 7. エントリ/イグジット基準

エントリ:
- 検証データ/判定ルール投入済み

イグジット:
- P0成功率100%
- 重大欠陥0件

## 8. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（コマンド/証跡）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |
