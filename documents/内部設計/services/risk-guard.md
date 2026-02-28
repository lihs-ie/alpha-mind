# risk-guard 内部設計書

最終更新日: 2026-02-28
JSON対応: `内部設計/json/risk-guard.json`

## 1. サービス概要

- サービスID: `risk-guard`
- 役割: 注文候補をリスク制約で検証し、承認または却下する。
- AI責務: なし

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run |
| Language | TypeScript |
| Exposure | private |

## 3. イベントIF

- Subscribe: `orders.proposed`, `operation.kill_switch.changed`
- Publish: `orders.approved`, `orders.rejected`

## 4. 依存関係

- Firestore: `settings`, `operations`, `compliance_controls`, `orders`, `idempotency_keys`, `audit_logs`
- Messaging: Pub/Sub

## 5. 処理フロー

1. `orders.proposed` 受信
2. kill switch状態確認
3. リスク制約評価
4. 承認/却下判定
5. 注文状態更新
6. 判定イベント発行

## 6. リスクルール

- `dailyLossLimit`
- `positionConcentrationLimit`
- `dailyOrderLimit`
- `killSwitchGuard`
- `restrictedSymbolsGuard`
- `blackoutWindowGuard`

## 7. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- failure mode: `fail-closed`

## 8. SLO・監視

- 判定遅延: p95 1000ms
- 成功率: 99.5%
- メトリクス: `risk_approved_total`, `risk_rejected_total`, `risk_evaluation_latency_ms`
