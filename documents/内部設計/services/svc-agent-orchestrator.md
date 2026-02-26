# svc-agent-orchestrator 内部設計書

最終更新日: 2026-02-24
JSON対応: `内部設計/json/svc-agent-orchestrator.json`

## 1. サービス概要

- サービスID: `svc-agent-orchestrator`
- 役割: Skillと指示書を適用して仮説を生成・管理する。
- AI責務: あり（仮説生成）

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run |
| Language | TypeScript |
| Exposure | private |

## 3. イベントIF

- Subscribe: `insight.collected`, `hypothesis.retest.requested`
- Publish: `hypothesis.proposed`, `hypothesis.proposal.failed`

## 4. 依存関係

- Firestore: `skill_registry`, `instruction_profiles`, `failure_knowledge`, `hypothesis_registry`, `idempotency_keys`, `audit_logs`
- Cloud Storage: `hypothesis_reports`
- External: LLM Runtime

## 5. 処理フロー

1. インサイトイベント受信
2. Skill/指示書を解決
3. 失敗知見との類似照合
4. 仮説生成
5. 仮説台帳へ保存
6. `hypothesis.proposed` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `eventId`
- リトライ: 最大3回、指数バックオフ
- 非再試行: `skill_not_found`, `instruction_profile_invalid`

## 7. 品質ゲート

- `hypothesisId` 必須
- `sourceEvidence` 必須
- `skillVersion` と `instructionProfileVersion` 必須

## 8. SLO・監視

- 1サイクル完了: 10分以内
- 仮説重複率: 5%未満
- メトリクス: `hypothesis_proposed_total`, `hypothesis_duplicate_blocked_total`, `hypothesis_proposal_failed_total`
