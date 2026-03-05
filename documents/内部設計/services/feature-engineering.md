# feature-engineering 内部設計書

最終更新日: 2026-03-03
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
- Firestore: `idempotency_keys`, `insight_records`, `feature_generations`, `feature_dispatches`
- Messaging: Pub/Sub

## 5. 処理フロー

1. `market.collected` 受信
2. 入力データ読込
3. 定性インサイト読込
4. 時点整合チェック（定量/定性）
5. 財務指標の単位同期（調整係数適用）
6. 定性×定量特徴量計算
7. `featureVersion` 採番
8. 保存
9. `features.generated` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- 再試行対象: `DEPENDENCY_UNAVAILABLE`
- 非再試行: `REQUEST_VALIDATION_FAILED`, `DATA_QUALITY_LEAK_DETECTED`, `DATA_SCHEMA_INVALID`

## 7. 品質ゲート

- 将来情報リークなし
- `insight_records` は `collectedAt <= targetDate` のみ採用
- 財務指標（BPS等）は価格系列と同一調整係数を適用
- 株式分割跨ぎ期間での単純 `forward fill` を禁止
- 必須特徴量欠損率が閾値以内
- 定性特徴量の根拠リンク欠損率が閾値以内

## 8. SLO・監視

- 1ジョブ完了: 15分以内
- 成功率: 99.0%
- メトリクス: `feature_job_success_total`, `feature_job_failure_total`, `feature_generation_duration_ms`, `feature_unit_sync_failed_total`

## 9. 財務指標同期仕様（PBR/BPS）

### 9.1 目的

- 株式分割・併合発生時に、価格と財務指標の単位ミスマッチで PBR が異常化する事象を防止する。

### 9.2 ルール

1. `data-collector` が出力する `adjustmentCumFactor` を正本として利用する。
2. BPSなどの per-share 財務指標は、価格系列と同一係数で同日付へ調整する。
3. 財務指標の欠損補完は「決算開示日以降のみ forward fill」を許可し、分割イベントを跨ぐ単純 forward fill を禁止する。
4. 補完後の単位整合チェック（`priceUnitVersion == financialUnitVersion`）に失敗した行は除外し、閾値超過時は `DATA_SCHEMA_INVALID` とする。

### 9.3 監査項目

- `financialAdjustmentApplied`（boolean）
- `financialSourceAsOf`（date）
- `unitSyncCheckPassed`（boolean）
