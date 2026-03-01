# bff 内部設計書

最終更新日: 2026-02-28
JSON対応: `内部設計/json/bff.json`

## 1. サービス概要

- サービスID: `bff`
- 役割: Webコンソール向けBFF。認証、認可、画面向け集約API、コマンド受付を担当する。
- AI責務: なし

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run |
| Language | Haskell |
| Exposure | public |

## 3. 外部インターフェース

### 3.1 HTTP

- `GET /healthz`
- `POST /auth/login`
- `GET /dashboard/summary`
- `POST /operations/runtime`
- `GET /orders`
- `GET /orders/{identifier}`
- `POST /orders/{identifier}/approve`
- `POST /orders/{identifier}/reject`
- `POST /orders/{identifier}/retry`
- `POST /operations/kill-switch`
- `POST /commands/run-cycle`
- `POST /commands/run-insight-cycle`
- `GET /settings/strategy`
- `PUT /settings/strategy`
- `GET /compliance/controls`
- `PUT /compliance/controls`
- `GET /audit`
- `GET /audit/{identifier}`
- `GET /insights`
- `GET /insights/{identifier}`
- `POST /insights/{identifier}/hypothesize`
- `POST /insights/{identifier}/adopt`
- `POST /insights/{identifier}/reject`
- `GET /hypotheses`
- `GET /hypotheses/{identifier}`
- `POST /hypotheses/{identifier}/retest`
- `POST /hypotheses/{identifier}/promote`
- `POST /hypotheses/{identifier}/reject`
- `PUT /hypotheses/{identifier}/mnpi-self-declaration`
- `GET /models/validation`
- `GET /models/validation/{modelVersion}`
- `POST /models/validation/{modelVersion}/approve`
- `POST /models/validation/{modelVersion}/reject`

補足:
- `POST /orders/{identifier}/approve` / `POST /orders/{identifier}/reject` は `risk-guard` の内部コマンドAPIへ委譲する。
- `orders.approved` / `orders.rejected` の発行責務は `risk-guard` が持つ。

### 3.2 Events

- Publish: `market.collect.requested`, `operation.kill_switch.changed`, `insight.collect.requested`, `hypothesis.retest.requested`, `orders.proposed`
- Subscribe: なし

## 4. 依存関係

- Firestore: `operations`, `settings`, `compliance_controls`, `orders`, `model_registry`, `audit_logs`, `insight_records`, `hypothesis_registry`, `idempotency_keys`
- Messaging: Pub/Sub
- External: OIDC/JWT Provider, Secret Manager, risk-guard Private Command API

## 5. 処理フロー

1. HTTP受信
2. JWT検証
3. `trace` 付与
4. Firestore参照、イベント発行、またはrisk-guard内部コマンドAPI呼び出し
5. 画面向けDTO返却
6. 監査ログ記録

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- 再試行対象: `DEPENDENCY_TIMEOUT`, `DEPENDENCY_UNAVAILABLE`

## 7. SLO・監視

- 可用性: 99.5%/月
- レイテンシ: p95 500ms
- 主要メトリクス: `http_requests_total`, `http_errors_total`, `http_latency_p95_ms`
- 主要アラート: 5xx率 > 2%（5分）
