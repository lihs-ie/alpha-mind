# execution 内部設計書

最終更新日: 2026-02-28
JSON対応: `内部設計/json/execution.json`

## 1. サービス概要

- サービスID: `execution`
- 役割: 承認済み注文をブローカーへ送信し、執行結果を記録・通知する。
- AI責務: なし

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run |
| Language | TypeScript |
| Exposure | private |

## 3. イベントIF

- Subscribe: `orders.approved`
- Publish: `orders.executed`, `orders.execution.failed`, `hypothesis.demo.completed`（デモ運用モード時）

## 4. 依存関係

- Firestore: `orders`, `audit_logs`, `idempotency_keys`, `demo_trade_runs`
- External: Broker Order API, Secret Manager

## 5. 処理フロー

1. `orders.approved` 受信
2. 重複発注防止チェック
3. ブローカー発注
4. 執行結果保存
5. 結果イベント発行
6. （デモ運用時）期間完了で `hypothesis.demo.completed` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- ガード: 同一identifierで外部発注を再実行しない
- リトライ: 最大3回、指数バックオフ
- 非再試行: `insufficient_funds`, `broker_rejected`, `market_closed`

## 7. SLO・監視

- 受信から執行完了: 30秒以内
- 成功率: 99.0%
- メトリクス: `execution_success_total`, `execution_failure_total`, `broker_api_latency_ms`
