# svc-bff 内部設計書

最終更新日: 2026-02-24
JSON対応: `内部設計/json/svc-bff.json`

## 1. サービス概要

- サービスID: `svc-bff`
- 役割: Webコンソール向けBFF。認証、認可、画面向け集約API、コマンド受付を担当する。
- AI責務: なし

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run |
| Language | TypeScript |
| Exposure | public |

## 3. 外部インターフェース

### 3.1 HTTP

- `GET /healthz`
- `GET /dashboard/summary`
- `GET /orders`
- `POST /operations/kill-switch`
- `POST /commands/run-cycle`
- `POST /commands/run-insight-cycle`
- `GET /settings/strategy`
- `PUT /settings/strategy`
- `GET /compliance/controls`
- `PUT /compliance/controls`
- `GET /audit`
- `GET /insights`
- `GET /hypotheses`
- `POST /hypotheses/{hypothesisId}/retest`
- `GET /models/validation`
- `POST /models/validation/{modelVersion}/approve`
- `POST /models/validation/{modelVersion}/reject`

### 3.2 Events

- Publish: `market.collect.requested`, `operation.kill_switch.changed`, `insight.collect.requested`, `hypothesis.retest.requested`
- Subscribe: なし

## 4. 依存関係

- Firestore: `operations`, `settings`, `compliance_controls`, `orders`, `model_registry`, `audit_logs`, `insight_records`, `hypothesis_registry`
- Messaging: Pub/Sub
- External: OIDC/JWT Provider, Secret Manager

## 5. 処理フロー

1. HTTP受信
2. JWT検証
3. `traceId` 付与
4. Firestore参照またはイベント発行
5. 画面向けDTO返却
6. 監査ログ記録

## 6. 冪等性・リトライ

- 冪等性: `requestId` / `traceId` ベース
- リトライ: 最大3回、指数バックオフ
- 再試行対象: 依存先タイムアウト、依存先5xx

## 7. SLO・監視

- 可用性: 99.5%/月
- レイテンシ: p95 500ms
- 主要メトリクス: `http_requests_total`, `http_errors_total`, `http_latency_p95_ms`
- 主要アラート: 5xx率 > 2%（5分）
