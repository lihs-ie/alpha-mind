# audit-log 外部設計書

最終更新日: 2026-02-28

## 1. サービス概要

- 役割: 全業務イベントの監査記録を一元管理する。
- 主な責務: イベント受信、監査ストア永続化、検索用メタデータ整備。
- 主な利用者: `bff`（監査参照API）, 運用者, 障害対応担当。

## 2. 採用技術と比較

| 項目 | 採用 | 比較対象 | 採用理由 |
|---|---|---|---|
| 収集方式 | Pub/Sub購読 | 各サービス個別ログ参照 | 監査情報をサービス横断で統一できる |
| 保存先 | Firestore + Cloud Logging | ファイル出力のみ | UI参照と長期調査の両立がしやすい |
| 相関キー | `trace`必須 | 相関キーなし | 事象追跡と責任境界の確認を容易化 |

## 3. 外部インターフェース

### 3.1 購読イベント

- `market.collect.requested`
- `market.collected`
- `market.collect.failed`
- `features.generated`
- `features.generation.failed`
- `signal.generated`
- `signal.generation.failed`
- `orders.proposed`
- `orders.proposal.failed`
- `orders.approved`
- `orders.rejected`
- `orders.executed`
- `orders.execution.failed`
- `operation.kill_switch.changed`
- `insight.collect.requested`
- `insight.collected`
- `insight.collect.failed`
- `hypothesis.retest.requested`
- `hypothesis.proposed`
- `hypothesis.proposal.failed`
- `hypothesis.demo.completed`
- `hypothesis.backtested`
- `hypothesis.promoted`
- `hypothesis.rejected`

### 3.2 発行イベント

- `audit.recorded`（任意・MVPでは省略可）

### 3.3 外部依存

- Firestore（`audit_logs`, `idempotency_keys`）
- Cloud Logging（長期保管）

## 4. ユースケース

### UC-AU-01: イベント監査記録

- 事前条件: 業務イベントが発行される。
- トリガー: 各イベント受信。
- 成果: 監査レコードを保存し検索可能化。

### UC-AU-02: 障害調査

- 事前条件: 運用者が失敗事象を検知。
- トリガー: `trace`指定検索。
- 成果: 当該サイクルの時系列イベントを復元。

## 5. 非機能要件

- 記録遅延目標: 受信から`5秒以内`。
- 欠損許容: 監査イベント欠損率`0.1%未満`。
- 品質: 監査レコードは `identifier`, `eventType`, `occurredAt`, `trace`, `service`, `result` を必須化する。
- 保持期間: Firestore短期（90日）、Cloud Logging長期（7年）。

## 6. スコープ外

- 業務意思決定。
- 注文執行制御。
- モデル評価計算。
