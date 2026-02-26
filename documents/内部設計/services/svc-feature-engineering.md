# svc-feature-engineering 内部設計書

最終更新日: 2026-02-12
JSON対応: `内部設計/json/svc-feature-engineering.json`

## 1. サービス概要

- サービスID: `svc-feature-engineering`
- 役割: 市場データから学習・推論用特徴量を生成し、バージョン管理して保存する。
- AI責務: あり（特徴量生成）

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run Job |
| Language | Python |
| Exposure | private |

## 3. イベントIF

- Subscribe: `market.collected`
- Publish: `features.generated`, `features.generation.failed`

## 4. 依存関係

- Cloud Storage: `raw_market_data`, `feature_store`
- Firestore: `idempotency_keys`, `audit_logs`
- Messaging: Pub/Sub

## 5. 処理フロー

1. `market.collected` 受信
2. 入力データ読込
3. 時点整合チェック
4. 特徴量計算
5. `featureVersion` 採番
6. 保存
7. `features.generated` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `eventId`
- リトライ: 最大3回、指数バックオフ
- 非再試行: `future_data_leak_detected`, `invalid_input_schema`

## 7. 品質ゲート

- 将来情報リークなし
- 必須特徴量欠損率が閾値以内

## 8. SLO・監視

- 1ジョブ完了: 15分以内
- 成功率: 99.0%
- メトリクス: `feature_job_success_total`, `feature_job_failure_total`, `feature_generation_duration_ms`

