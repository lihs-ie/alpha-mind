# svc-hypothesis-lab 内部設計書

最終更新日: 2026-02-24
JSON対応: `内部設計/json/svc-hypothesis-lab.json`

## 1. サービス概要

- サービスID: `svc-hypothesis-lab`
- 役割: 仮説のバックテスト/デモトレードを実行し、昇格可否を判定する。
- AI責務: なし

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run Job |
| Language | Python |
| Exposure | private |

## 3. イベントIF

- Subscribe: `hypothesis.proposed`, `hypothesis.demo.completed`
- Publish: `hypothesis.backtested`, `hypothesis.promoted`, `hypothesis.rejected`

## 4. 依存関係

- Firestore: `hypothesis_registry`, `backtest_runs`, `demo_trade_runs`, `failure_knowledge`, `idempotency_keys`, `audit_logs`
- Cloud Storage: `backtest_artifacts`, `demo_artifacts`

## 5. 処理フロー

1. 仮説受信
2. バックテスト実行（Walk-forward/DSR/PBO）
3. コスト控除評価
4. 合格時はデモ運用へ遷移
5. デモ結果で昇格/却下判定
6. 結果イベント発行

## 6. 冪等性・リトライ

- 冪等性キー: `eventId`
- リトライ: 最大2回（長時間ジョブのため）
- 非再試行: `invalid_hypothesis_payload`, `insufficient_backtest_data`

## 7. 品質ゲート

- コスト控除後指標が閾値以上
- `requiresComplianceReview=true` は昇格拒否
- 失敗時は `failure_knowledge` 登録を必須化

## 8. SLO・監視

- 仮説受信から7日以内の検証完了率: 95%以上
- バックテストジョブ成功率: 99.0%
- メトリクス: `hypothesis_backtest_success_total`, `hypothesis_promotion_total`, `hypothesis_rejected_total`
