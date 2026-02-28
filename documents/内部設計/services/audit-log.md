# audit-log 内部設計書

最終更新日: 2026-02-28
JSON対応: `内部設計/json/audit-log.json`

## 1. サービス概要

- サービスID: `audit-log`
- 役割: 全イベントを監査記録として永続化し、追跡可能性を提供する。
- AI責務: なし

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run |
| Language | Haskell |
| Exposure | private |

## 3. イベントIF

- Subscribe: `market.collect.requested`, `market.collected`, `market.collect.failed`, `features.generated`, `features.generation.failed`, `signal.generated`, `signal.generation.failed`, `orders.proposed`, `orders.proposal.failed`, `orders.approved`, `orders.rejected`, `orders.executed`, `orders.execution.failed`, `operation.kill_switch.changed`, `insight.collect.requested`, `insight.collected`, `insight.collect.failed`, `hypothesis.retest.requested`, `hypothesis.proposed`, `hypothesis.proposal.failed`, `hypothesis.demo.completed`, `hypothesis.backtested`, `hypothesis.promoted`, `hypothesis.rejected`
- Publish: `audit.recorded`（任意）

## 4. 依存関係

- Firestore: `audit_logs`, `idempotency_keys`
- Cloud Logging
- Messaging: Pub/Sub

## 5. 処理フロー

1. 業務イベント受信
2. イベント検証
3. 監査レコード生成
4. Firestore保存
5. Cloud Logging出力
6. `audit.recorded` 発行（任意、保存成功時のみ）

## 6. 冪等性・リトライ

- 冪等性キー: 受信イベントエンベロープ `identifier`
- リトライ: 最大3回、指数バックオフ
- 非再試行: `DATA_SCHEMA_INVALID`
- 再試行対象: `AUDIT_WRITE_FAILED`

## 7. SLO・監視

- 記録遅延: 5秒以内
- 欠損率: 0.1%未満
- 保持期間: Firestore 90日、Cloud Logging 7年（2555日）
- メトリクス: `audit_record_success_total`, `audit_record_failure_total`, `audit_record_delay_ms`
