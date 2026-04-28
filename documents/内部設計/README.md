# 内部設計ドキュメント一覧

最終更新日: 2026-03-01

## 1. 目的

- 外部設計で定義した責務・契約を、実装可能な粒度へ分解する。
- 内部設計では、処理フロー、データモデル、エラー処理、冪等性、監視項目を定義する。

## 2. 関連ドキュメント

- 要件定義: `investment-ai-requirements.md`
- 機能仕様: `機能仕様書.md`
- 外部設計: `外部設計/README.md`

## 3. 共通設計

- `内部設計/内部設計書_作成ガイド.md`
- `内部設計/共通設計.md`
- `内部設計/Python共通モジュール設計.md`
- `内部設計/Haskell共通モジュール設計.md`
- `内部設計/haskell-common/README.md`
- `内部設計/haskell-common/App.Bootstrap.md`
- `内部設計/haskell-common/App.Health.md`
- `内部設計/haskell-common/Config.Env.md`
- `内部設計/haskell-common/Messaging.CloudEvent.md`
- `内部設計/haskell-common/Messaging.PubSub.md`
- `内部設計/haskell-common/Persistence.Firestore.md`
- `内部設計/haskell-common/Persistence.Idempotency.md`
- `内部設計/haskell-common/Observability.Logging.md`
- `内部設計/haskell-common/Observability.Metrics.md`
- `内部設計/haskell-common/Resilience.Retry.md`
- `内部設計/haskell-common/Auth.InternalJwt.md`
- `内部設計/haskell-common/Storage.GCS.md`
- `内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `内部設計/md/bff_ドメインモデル設計.md`
- `内部設計/md/data-collector_ドメインモデル設計.md`
- `内部設計/md/execution_ドメインモデル設計.md`
- `内部設計/md/feature-engineering_ドメインモデル設計.md`
- `内部設計/md/hypothesis-lab_ドメインモデル設計.md`
- `内部設計/md/insight-collector_ドメインモデル設計.md`
- `内部設計/md/portfolio-planner_ドメインモデル設計.md`
- `内部設計/md/risk-guard_ドメインモデル設計.md`
- `内部設計/md/signal-generator_ドメインモデル設計.md`
- `内部設計/md/audit-log_ドメインモデル設計.md`
- `内部設計/md/agent-orchestrator_ドメインモデル設計.md`
- `内部設計/md/frontend/README.md`
- `内部設計/md/frontend/frontend-sol_ドメインモデル設計.md`
- `内部設計/md/frontend/hypothesis-lab-frontend_ドメインモデル設計.md`

補足:
- ドメインモデル設計は「業務ルールを持つサービス（core/supporting）」を優先し、横断ルールを担う generic（例: `audit-log`）も対象に含める。

## 4. サービス別内部設計

- `内部設計/services/bff.md`
- `内部設計/services/data-collector.md`
- `内部設計/services/feature-engineering.md`
- `内部設計/services/signal-generator.md`
- `内部設計/services/portfolio-planner.md`
- `内部設計/services/risk-guard.md`
- `内部設計/services/execution.md`
- `内部設計/services/audit-log.md`
- `内部設計/services/insight-collector.md`
- `内部設計/services/agent-orchestrator.md`
- `内部設計/services/hypothesis-lab.md`

## 5. サービス定義JSON

- `内部設計/json/services.json`
- `内部設計/json/bff.json`
- `内部設計/json/data-collector.json`
- `内部設計/json/feature-engineering.json`
- `内部設計/json/signal-generator.json`
- `内部設計/json/portfolio-planner.json`
- `内部設計/json/risk-guard.json`
- `内部設計/json/execution.json`
- `内部設計/json/audit-log.json`
- `内部設計/json/insight-collector.json`
- `内部設計/json/agent-orchestrator.json`
- `内部設計/json/hypothesis-lab.json`
