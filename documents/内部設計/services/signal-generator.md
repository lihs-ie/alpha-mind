# signal-generator 内部設計書

最終更新日: 2026-02-28
JSON対応: `内部設計/json/signal-generator.json`

## 1. サービス概要

- サービスID: `signal-generator`
- 役割: 承認済みモデルを使って銘柄シグナルを推論し、注文計画へ渡す。
- AI責務: あり（推論）

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run Job |
| Language | Python |
| Exposure | private |

## 3. イベントIF

- Subscribe: `features.generated`
- Publish: `signal.generated`, `signal.generation.failed`

## 4. 依存関係

- Cloud Storage: `feature_store`, `signal_store`
- Firestore: `model_registry`, `idempotency_keys`, `audit_logs`
- External: MLflow Model Registry

## 5. 処理フロー

1. `features.generated` 受信
2. `approved` モデル解決
3. 特徴量読込
4. 推論実行
5. `signalVersion` 採番
6. 結果保存
7. `signal.generated` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- 非再試行: `MODEL_NOT_APPROVED`, `REQUEST_VALIDATION_FAILED`

## 7. 品質ゲート

- approvedモデルのみ利用
- 推論件数がユニバース件数と一致
- `signal.generated.payload.modelDiagnostics.requiresComplianceReview` を必須で伝播

## 8. SLO・監視

- 1ジョブ完了: 10分以内
- 成功率: 99.0%
- メトリクス: `signal_generation_success_total`, `signal_generation_failure_total`, `signal_generation_duration_ms`
