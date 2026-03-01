# data-collector 内部設計書

最終更新日: 2026-02-28
JSON対応: `内部設計/json/data-collector.json`

## 1. サービス概要

- サービスID: `data-collector`
- 役割: 市場データを取得し、正規化して保存し、後続処理イベントを発行する。
- AI責務: なし

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run Job |
| Language | Haskell |
| Exposure | private |

## 3. イベントIF

- Subscribe: `market.collect.requested`
- Publish: `market.collected`, `market.collect.failed`

## 4. 依存関係

- Cloud Storage: `raw_market_data`
- Firestore: `audit_logs`, `idempotency_keys`
- External: J-Quants API, Alpaca Market Data API, 日商金Web, Secret Manager

## 5. 処理フロー

1. `market.collect.requested` 受信
2. 冪等性チェック
3. 日米データ取得
4. 日商金データ取得（逆日歩CSV）
5. スキーマ正規化・逆日歩クレンジング
6. Cloud Storage保存
7. `market.collected` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- 再試行対象: `DATA_SOURCE_TIMEOUT`, `DATA_SOURCE_UNAVAILABLE`, `DEPENDENCY_TIMEOUT`
- 非再試行: `REQUEST_VALIDATION_FAILED`, `DATA_SCHEMA_INVALID`

## 7. SLO・監視

- 1ジョブ完了: 10分以内
- 成功率: 99.0%
- メトリクス: `collect_success_total`, `collect_failure_total`, `source_latency_ms`
- メトリクス: `collect_success_total`, `collect_failure_total`, `source_latency_ms`, `nisshokin_fetch_success_total`
