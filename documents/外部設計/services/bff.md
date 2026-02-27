# bff 外部設計書

最終更新日: 2026-02-24

## 1. サービス概要

- 役割: Webコンソールおよび運用者向けAPIの単一入口。
- 主な責務: 認証済みリクエスト受付、運用コマンド受付、参照データ提供、コンプライアンス制御設定管理。
- 主な責務: 認証済みリクエスト受付、運用コマンド受付、参照データ提供、コンプライアンス制御設定管理、インサイト/仮説運用API提供。
- 主な利用者: 運用者（単一ユーザー）。

## 2. 採用技術と比較

| 項目 | 採用 | 比較対象 | 採用理由 |
|---|---|---|---|
| 実行基盤 | Cloud Run | GKE, Cloud Functions | APIとBFFを同一コンテナで運用でき、低トラフィック時の固定費を抑えやすい |
| API契約 | OpenAPI | 独自仕様 | 外部設計段階で契約を固定し、フロントエンドと合意しやすい |
| 認証 | OIDC JWT（MVPは単一ユーザー） | 独自トークン | 標準方式で拡張時の連携先追加が容易 |

## 3. 外部インターフェース

### 3.1 同期API

- `GET /healthz`
- `GET /dashboard/summary`
- `GET /orders?status={status}`
- `GET /compliance/controls`
- `PUT /compliance/controls`
- `POST /operations/kill-switch`
- `POST /commands/run-cycle`
- `POST /commands/run-insight-cycle`
- `GET /insights`
- `POST /hypotheses/{identifier}/retest`
- `GET /hypotheses`

認証:
- `Authorization: Bearer <JWT>` 必須（`GET /healthz`を除く）。

主要レスポンス:
- `200`: 正常
- `400`: 入力不正
- `401/403`: 認証・認可エラー
- `409`: 状態競合（例: 実行中に再実行）
- `503`: 下流依存障害

### 3.2 非同期イベント

発行:
- `market.collect.requested`
- `operation.kill_switch.changed`
- `insight.collect.requested`
- `hypothesis.retest.requested`

購読:
- なし（MVPでは状態参照はFirestoreから取得）

## 4. ユースケース

### UC-API-01: 運用サイクル手動起動

- 事前条件: kill switchが無効。
- トリガー: 運用者が`POST /commands/run-cycle`を実行。
- 成果: `market.collect.requested`を発行し、受付結果を返却。

### UC-API-02: 緊急停止

- 事前条件: 認証済みユーザー。
- トリガー: `POST /operations/kill-switch`。
- 成果: 停止状態を保存し、`operation.kill_switch.changed`を発行。

## 5. 非機能要件

- 可用性目標: 月間`99.5%`（MVP暫定）。
- 応答目標: `p95 < 500ms`（参照API）。
- 監査: すべての更新系APIで`trace`を採番し、監査ログに記録。
- セキュリティ: JWT検証、HTTPS必須、Secret Manager経由で鍵管理。

## 6. スコープ外

- モデル計算ロジック。
- 約定判定ロジック。
- データ前処理ロジック。
