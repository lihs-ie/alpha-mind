# 外部設計ドキュメント一覧

最終更新日: 2026-02-28

## 目的

- マイクロサービスごとに外部設計書を分離し、責務・契約・運用要件を明確化する。
- 内部実装は記述せず、利用者・連携先・運用者に必要な仕様のみを定義する。

## 共通ガイド

- `外部設計/外部設計書_作成ガイド.md`

## サービス別外部設計

- `外部設計/services/bff.md`
- `外部設計/services/data-collector.md`
- `外部設計/services/feature-engineering.md`
- `外部設計/services/signal-generator.md`
- `外部設計/services/portfolio-planner.md`
- `外部設計/services/risk-guard.md`
- `外部設計/services/execution.md`
- `外部設計/services/audit-log.md`
- `外部設計/services/insight-collector.md`
- `外部設計/services/agent-orchestrator.md`
- `外部設計/services/hypothesis-lab.md`

## 画面別外部設計

- `外部設計/screens/画面外部設計_共通.md`
- `外部設計/screens/SCR-000_認証.md`
- `外部設計/screens/SCR-001_ダッシュボード.md`
- `外部設計/screens/SCR-002_戦略設定.md`
- `外部設計/screens/SCR-003_注文管理.md`
- `外部設計/screens/SCR-004_監査ログ.md`
- `外部設計/screens/SCR-005_モデル検証.md`
- `外部設計/screens/SCR-006_インサイト管理.md`
- `外部設計/screens/SCR-007_仮説ラボ.md`

## API設計

- `外部設計/api/README.md`
- `外部設計/api/openapi.yaml`
- `外部設計/api/asyncapi.yaml`

## 状態遷移設計

- `外部設計/state/状態遷移設計.md`

## DB設計

- `外部設計/db/firestore設計.md`
- `外部設計/db/firestore.indexes.json`
- `外部設計/db/firestore.rules`

## エラー設計

- `外部設計/error/エラーコード設計.md`
- `外部設計/error/error-codes.json`

## 認証・認可設計

- `外部設計/security/認証認可設計.md`
- `外部設計/security/条件付き自動昇格設計.md`
- `外部設計/security/authz-matrix.json`

## 運用設計

- `外部設計/operations/運用設計.md`
- `外部設計/operations/STG環境構築設計.md`
- `外部設計/operations/フロントエンドインフラ設計_Sol.md`
- `外部設計/operations/slo-catalog.json`
- `外部設計/operations/監視クエリ設計.md`
- `外部設計/operations/slo-query-spec.json`
- `外部設計/operations/Terraform監視設定設計.md`
- `外部設計/operations/terraform-monitoring-blueprint.json`

## 次の更新対象

- Terraformモジュール雛形（`.tf`）の作成
- 補助モニタ（`MON-001`〜`MON-003`）の実測メトリクス送信実装
- OpenAPI/AsyncAPI 互換性テストの自動化
