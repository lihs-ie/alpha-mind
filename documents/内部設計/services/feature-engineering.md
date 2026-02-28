# feature-engineering 内部設計書

最終更新日: 2026-02-28
JSON対応: `内部設計/json/feature-engineering.json`

## 1. サービス概要

- サービスID: `feature-engineering`
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
- Firestore: `idempotency_keys`, `audit_logs`, `insight_records`
- Messaging: Pub/Sub

## 5. 処理フロー

1. `market.collected` 受信
2. 入力データ読込
3. 定性インサイト読込
4. 時点整合チェック（定量/定性）
5. 定性×定量特徴量計算
6. `featureVersion` 採番
7. 保存
8. `features.generated` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- 再試行対象: `DEPENDENCY_UNAVAILABLE`
- 非再試行: `REQUEST_VALIDATION_FAILED`, `DATA_QUALITY_LEAK_DETECTED`, `DATA_SCHEMA_INVALID`

## 7. 品質ゲート

- 将来情報リークなし
- `insight_records` は `collectedAt <= targetDate` のみ採用
- 必須特徴量欠損率が閾値以内
- 定性特徴量の根拠リンク欠損率が閾値以内

## 8. SLO・監視

- 1ジョブ完了: 15分以内
- 成功率: 99.0%
- メトリクス: `feature_job_success_total`, `feature_job_failure_total`, `feature_generation_duration_ms`
