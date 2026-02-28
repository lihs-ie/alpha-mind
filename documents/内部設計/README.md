# 内部設計ドキュメント一覧

最終更新日: 2026-02-28

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
- `内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `内部設計/md/hypothesis-lab_ドメインモデル設計.md`
- `内部設計/md/risk-guard_ドメインモデル設計.md`

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
