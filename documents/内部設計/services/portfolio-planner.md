# portfolio-planner 内部設計書

最終更新日: 2026-02-28
JSON対応: `内部設計/json/portfolio-planner.json`

## 1. サービス概要

- サービスID: `portfolio-planner`
- 役割: シグナルと保有状態から注文候補を生成する。
- AI責務: なし

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run |
| Language | TypeScript |
| Exposure | private |

## 3. イベントIF

- Subscribe: `signal.generated`
- Publish: `orders.proposed`, `orders.proposal.failed`

## 4. 依存関係

- Firestore: `positions`, `settings`, `orders`, `idempotency_keys`, `audit_logs`
- External: Broker Account API（参照のみ）

## 5. 処理フロー

1. `signal.generated` 受信
2. 保有状態取得
3. 運用設定取得
4. 注文候補計算
5. `orders` 保存
6. `orders.proposed` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- 非再試行: `REQUEST_VALIDATION_FAILED`

## 7. SLO・監視

- 1ジョブ完了: 5分以内
- 成功率: 99.0%
- メトリクス: `proposal_success_total`, `proposal_failure_total`, `proposal_duration_ms`
