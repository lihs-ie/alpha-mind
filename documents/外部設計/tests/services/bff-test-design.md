# bff API統合テスト設計書

最終更新日: 2026-03-05  
文書バージョン: v0.3  
対象サービス: bff

## 1. 文書情報

| 項目 | 内容 |
|---|---|
| 作成者 | Codex |
| 関連要件 | `documents/機能仕様書.md` |
| 関連設計 | `documents/外部設計/services/bff.md` |
| API契約 | `documents/外部設計/api/openapi.yaml`, `documents/外部設計/api/asyncapi.yaml` |
| 適用リリース | `2026.03` |

## 2. 目的と適用範囲

- BFF公開APIの統合テストを実装可能な粒度で定義する。
- 対象はAPI契約整合、認証認可、下流委譲、イベント発行、監査追跡。
- 対象環境は `local` と `stg`。UI受入テストは対象外。

注記:
- 本設計は OpenAPI/AsyncAPI 契約基準である。未実装APIは先行してケースを定義する。

## 3. テスト対象API（優先度付き）

| API-ID | method | path | 優先度 | 主要リスク |
|---|---|---|---|---|
| BFF-API-01 | GET | /healthz | P1 | 監視誤検知 |
| BFF-API-02 | POST | /auth/login | P0 | 認証不備 |
| BFF-API-03 | POST | /commands/run-cycle | P0 | 重複実行 |
| BFF-API-04 | POST | /commands/run-insight-cycle | P0 | 不正入力/誤配信 |
| BFF-API-05 | POST | /operations/runtime | P0 | 状態競合 |
| BFF-API-06 | POST | /operations/kill-switch | P0 | 停止制御不備 |
| BFF-API-07 | GET/PUT | /settings/strategy | P0 | 不正更新 |
| BFF-API-08 | GET/PUT | /compliance/controls | P0 | コンプライアンス違反 |
| BFF-API-09 | GET/POST | /orders* | P0 | 誤承認/委譲不整合 |
| BFF-API-10 | GET | /audit* | P0 | 監査追跡不能 |
| BFF-API-11 | GET/POST | /insights* | P1 | 状態遷移不整合 |
| BFF-API-12 | GET/POST/PUT | /hypotheses* | P0 | 昇格制御逸脱 |
| BFF-API-13 | GET/POST | /models/validation* | P1 | 未承認モデル運用 |

## 4. テスト環境と前提

### 4.1 ローカル起動

```bash
cd docker
make up
make ps
```

### 4.2 実行用環境変数

```bash
export BASE_URL="http://localhost:3001"
export PUBSUB_URL="http://localhost:8085"
export PROJECT_ID="alpha-mind-local"
export ACCESS_TOKEN="$(curl -sS -X POST "$BASE_URL/auth/login" \
  -H 'content-type: application/json' \
  -d '{"email":"user@example.com","password":"P@ssw0rd123!"}' | jq -r '.accessToken')"
```

### 4.3 テストデータ前提（初期シード）

`docker/scripts/seed-data.json` を基準とする。

| データID | コレクション/文書 | 用途 |
|---|---|---|
| BFF-TD-01 | `settings/strategy` | 設定取得・更新 |
| BFF-TD-02 | `operations/runtime` | runtime/kill-switch |
| BFF-TD-03 | `compliance_controls/trading` | 制御設定取得・更新 |

補助ID（ケース内で利用）:
- `VALID_ID=01ARZ3NDEKTSV4RRFFQ69G5FAV`
- `INVALID_ID=invalid-id`

## 5. 実行手順（ベースライン）

1. `make up` で依存を起動する。  
2. `/healthz` と `/auth/login` で疎通確認する。  
3. P0ケースを先に実行する。  
4. 失敗時は `HTTPヘッダ + body + trace` を必ず採取する。  
5. 最後に P1 ケースを実行し、証跡を保存する。  

## 6. 詳細テストケース

### 6.1 ケース一覧

| TC-ID | API-ID | 観点 | 優先度 | 期待ステータス |
|---|---|---|---|---|
| BFF-IT-001 | BFF-API-01 | ヘルスチェック | P1 | 200 |
| BFF-IT-002 | BFF-API-02 | ログイン成功 | P0 | 200 |
| BFF-IT-003 | BFF-API-03 | JWT必須 | P0 | 401 |
| BFF-IT-004 | BFF-API-03 | run-cycle受付 + イベント | P0 | 202 |
| BFF-IT-005 | BFF-API-04 | run-insight-cycle入力境界 | P0 | 400 |
| BFF-IT-006 | BFF-API-06 | kill-switch切替 | P0 | 200 |
| BFF-IT-007 | BFF-API-05 | runtime状態競合 | P0 | 409 |
| BFF-IT-008 | BFF-API-07 | strategy更新正常 | P0 | 200 |
| BFF-IT-009 | BFF-API-07 | strategy更新バリデーション | P0 | 400 |
| BFF-IT-010 | BFF-API-08 | compliance更新バリデーション | P0 | 400 |
| BFF-IT-011 | BFF-API-09 | order approve委譲 | P0 | 200 |
| BFF-IT-012 | BFF-API-09 | order reject必須項目 | P0 | 400 |
| BFF-IT-013 | BFF-API-09 | order retry受付 + イベント | P0 | 202 |
| BFF-IT-014 | BFF-API-10 | audit trace形式バリデーション | P0 | 400 |
| BFF-IT-015 | BFF-API-12 | hypothesis promote自己申告制約 | P0 | 400/422 |
| BFF-IT-016 | BFF-API-13 | model approve正常 | P1 | 200 |

### 6.2 ケース別コマンド（実装用）

#### BFF-IT-001 ヘルスチェック

```bash
curl -si "$BASE_URL/healthz"
```

確認点:
- status code = `200`
- body = `ok` または `HealthResponse` 契約準拠

#### BFF-IT-002 ログイン成功

```bash
curl -si -X POST "$BASE_URL/auth/login" \
  -H 'content-type: application/json' \
  -d '{"email":"user@example.com","password":"P@ssw0rd123!"}'
```

確認点:
- status code = `200`
- `accessToken`, `tokenType`, `expiresIn`, `user` が存在

#### BFF-IT-003 JWT必須（未付与）

```bash
curl -si -X POST "$BASE_URL/commands/run-cycle" \
  -H 'content-type: application/json' \
  -d '{"mode":"manual"}'
```

確認点:
- status code = `401`
- `content-type: application/problem+json`
- body に `reasonCode` を含む

#### BFF-IT-004 run-cycle受付 + イベント発行

事前にテスト用pull subscriptionを作成:

```bash
curl -sS -X PUT "$PUBSUB_URL/v1/projects/$PROJECT_ID/subscriptions/sub-it-market-collect-requested" \
  -H 'content-type: application/json' \
  -d '{"topic":"projects/alpha-mind-local/topics/event-market-collect-requested-v1","ackDeadlineSeconds":60}'
```

API実行:

```bash
curl -si -X POST "$BASE_URL/commands/run-cycle" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"mode":"manual"}'
```

イベント確認:

```bash
curl -sS -X POST "$PUBSUB_URL/v1/projects/$PROJECT_ID/subscriptions/sub-it-market-collect-requested:pull" \
  -H 'content-type: application/json' \
  -d '{"maxMessages":1}' | jq .
```

確認点:
- API status code = `202`
- `accepted=true`
- pull結果に1件以上のメッセージ

#### BFF-IT-005 run-insight-cycle入力境界（maxItemsPerSource上限超過）

```bash
curl -si -X POST "$BASE_URL/commands/run-insight-cycle" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"mode":"manual","targetDate":"2026-03-03","sourceTypes":["x"],"options":{"maxItemsPerSource":2001}}'
```

確認点:
- status code = `400`
- `reasonCode=REQUEST_VALIDATION_FAILED`

#### BFF-IT-006 kill-switch切替

```bash
curl -si -X POST "$BASE_URL/operations/kill-switch" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"enabled":true,"actionReasonCode":"MANUAL_OPERATION","comment":"manual stop"}'
```

確認点:
- status code = `200`
- `success=true`
- `trace` が26桁ULID形式

#### BFF-IT-007 runtime状態競合

```bash
curl -si -X POST "$BASE_URL/operations/runtime" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"action":"START","reason":"integration-test"}'
```

同一条件で連続実行して競合確認:

```bash
curl -si -X POST "$BASE_URL/operations/runtime" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"action":"START","reason":"integration-test"}'
```

確認点:
- 2回目が `409`
- `application/problem+json`

#### BFF-IT-008 strategy更新正常

```bash
curl -si -X PUT "$BASE_URL/settings/strategy" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"market":"JP","rebalanceFrequency":"daily","symbols":["1306.T"],"dailyLossLimit":5,"positionConcentrationLimit":20,"dailyOrderLimit":10}'
```

確認点:
- status code = `200`
- 直後の `GET /settings/strategy` で反映確認

#### BFF-IT-009 strategy更新バリデーション（dailyOrderLimit=0）

```bash
curl -si -X PUT "$BASE_URL/settings/strategy" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"market":"JP","rebalanceFrequency":"daily","symbols":["1306.T"],"dailyLossLimit":5,"positionConcentrationLimit":20,"dailyOrderLimit":0}'
```

確認点:
- status code = `400`
- `reasonCode=REQUEST_VALIDATION_FAILED`

#### BFF-IT-010 compliance更新バリデーション（maxCommentLength下限未満）

```bash
curl -si -X PUT "$BASE_URL/compliance/controls" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"restrictedSymbols":[],"partnerRestrictedSymbols":[],"blackoutWindows":[],"sourcePolicies":[],"maxCommentLength":10,"autoPromotionEnabled":false}'
```

確認点:
- status code = `400`
- `reasonCode=REQUEST_VALIDATION_FAILED`

#### BFF-IT-011 order approve委譲

```bash
curl -si -X POST "$BASE_URL/orders/$VALID_ID/approve" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"actionReasonCode":"MANUAL_OPERATION","comment":"approve by operator"}'
```

確認点:
- status code = `200`
- risk-guard委譲成功を返却

#### BFF-IT-012 order reject必須項目欠落

```bash
curl -si -X POST "$BASE_URL/orders/$VALID_ID/reject" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{}'
```

確認点:
- status code = `400`
- `reasonCode=REQUEST_VALIDATION_FAILED`

#### BFF-IT-013 order retry受付 + イベント発行

```bash
curl -sS -X PUT "$PUBSUB_URL/v1/projects/$PROJECT_ID/subscriptions/sub-it-orders-proposed" \
  -H 'content-type: application/json' \
  -d '{"topic":"projects/alpha-mind-local/topics/event-orders-proposed-v1","ackDeadlineSeconds":60}'

curl -si -X POST "$BASE_URL/orders/$VALID_ID/retry" \
  -H "authorization: Bearer $ACCESS_TOKEN"

curl -sS -X POST "$PUBSUB_URL/v1/projects/$PROJECT_ID/subscriptions/sub-it-orders-proposed:pull" \
  -H 'content-type: application/json' \
  -d '{"maxMessages":1}' | jq .
```

確認点:
- API status code = `202`
- `accepted=true`
- `orders.proposed` のメッセージ取得

#### BFF-IT-014 audit trace形式バリデーション

```bash
curl -si "$BASE_URL/audit?trace=invalid-trace" \
  -H "authorization: Bearer $ACCESS_TOKEN"
```

確認点:
- status code = `400`
- `reasonCode=REQUEST_VALIDATION_FAILED`

#### BFF-IT-015 hypothesis promote自己申告制約

```bash
curl -si -X POST "$BASE_URL/hypotheses/$VALID_ID/promote" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"actionReasonCode":"MODEL_REVIEW_DECISION","mnpiSelfDeclared":false,"comment":"invalid self declaration"}'
```

確認点:
- status code = `400` または `422`
- `reasonCode` に昇格制約系コードが設定される

#### BFF-IT-016 model approve正常

```bash
curl -si -X POST "$BASE_URL/models/validation/model-v1/approve" \
  -H "authorization: Bearer $ACCESS_TOKEN" \
  -H 'content-type: application/json' \
  -d '{"actionReasonCode":"MANUAL_OPERATION","comment":"approve for rollout"}'
```

確認点:
- status code = `200`
- `success=true`

## 7. 証跡取得ルール

- 各ケースで以下を保存する。
- リクエスト（method, URL, header, body）
- レスポンス（status, header, body）
- `trace` 値
- 連携イベント確認結果（pullレスポンス）

保存先:
- `documents/外部設計/tests/evidence/bff/{yyyyMMdd}/`

## 8. エントリ/イグジット基準

エントリ:
- OpenAPI/AsyncAPI が `main` と一致している。
- `docker make up` が完了し BFF が `healthy`。
- 認証トークン取得手段が確立している。

イグジット:
- P0ケース成功率 `100%`。
- Critical/High欠陥 `0件`。
- `application/problem+json` が異常系で一貫。

## 9. CI実行ポリシー

- PR時に以下を必須実行する。
- OpenAPI lint
- BFF統合テスト（P0）
- mainマージ時に P0 + P1 を実行する。

## 10. 変更履歴

| 日付 | 版 | 変更内容 |
|---|---|---|
| 2026-03-05 | v0.3 | 実装レベル（手順・データ・コマンド）へ詳細化 |
| 2026-03-05 | v0.2 | API統合テスト設計へ全面更新 |

## 11. 参考

- `documents/外部設計/tests/API統合テスト設計書テンプレート.md`
- `documents/外部設計/tests/WebAPI統合テスト設計ベストプラクティス.md`
