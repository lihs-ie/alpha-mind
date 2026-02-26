# svc-data-collector 外部設計書

最終更新日: 2026-02-12

## 1. サービス概要

- 役割: 市場データ取得の標準入口。
- 主な責務: 日本・米国データの取得、正規化、保存、取得結果イベント発行。
- 主な利用者: 他マイクロサービス（直接UI利用なし）。

## 2. 採用技術と比較

| 項目 | 採用 | 比較対象 | 採用理由 |
|---|---|---|---|
| 実行基盤 | Cloud Run Job/Service | VM cron, GKE Job | 定時起動とイベント起動の両方を低運用で扱える |
| データ保存 | Cloud Storage(Parquet) | Firestore直保存 | 時系列大容量を低コスト保存できる |
| データ取得元 | J-Quants + Alpaca Basic | 複数有料API同時導入 | 初期固定費を抑えつつ日米データを確保 |

## 3. 外部インターフェース

### 3.1 購読イベント

- `market.collect.requested`

### 3.2 発行イベント

- `market.collected`
- `market.collect.failed`

### 3.3 外部依存

- J-Quants API
- Alpaca Market Data API
- Cloud Storage
- Secret Manager

イベント共通属性:
- `eventId`, `eventType`, `occurredAt`, `traceId`, `schemaVersion`, `payload`

## 4. ユースケース

### UC-DC-01: 日次データ収集

- 事前条件: APIキーが有効。
- トリガー: `market.collect.requested`受信。
- 成果: 正規化データを保存し、`market.collected`発行。

### UC-DC-02: データ欠損時の失敗通知

- 事前条件: 取得対象市場のいずれかが応答不正。
- トリガー: データ検証失敗。
- 成果: `market.collect.failed`を発行し、後続処理を停止。

## 5. 非機能要件

- 完了目標: 1サイクル`10分以内`。
- 再試行: 指数バックオフで最大`3回`。
- 可観測性: 成功件数、欠損件数、APIレイテンシをメトリクス化。
- セキュリティ: 外部APIキーはSecret Managerから取得。

## 6. スコープ外

- 特徴量計算。
- 売買シグナル計算。
- 注文執行。

