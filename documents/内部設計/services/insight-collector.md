# insight-collector 内部設計書

最終更新日: 2026-02-27
JSON対応: `内部設計/json/insight-collector.json`

## 1. サービス概要

- サービスID: `insight-collector`
- 役割: 定性データソースを収集し、根拠付きインサイトへ構造化する。
- AI責務: あり（要約・タグ付け）

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run Job |
| Language | TypeScript |
| Exposure | private |

## 3. イベントIF

- Subscribe: `insight.collect.requested`
- Publish: `insight.collected`, `insight.collect.failed`

## 4. 依存関係

- Firestore: `skill_registry`, `source_policies`, `insight_records`, `idempotency_keys`, `audit_logs`
- Cloud Storage: `insight_raw`, `insight_processed`
- External: X API, YouTube API, Paper/GitHub source API

## 5. 処理フロー

1. `insight.collect.requested` 受信
2. 収集Skill解決
3. 許可ソース/利用規約検証
4. 収集・正規化・要約
5. 根拠付きインサイト保存
6. `insight.collected` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- 非再試行: `source_not_allowed`, `source_terms_not_allowed`, `invalid_source_payload`

## 7. 品質ゲート

- `source_policies` 一致必須
- `sourceUrl` 欠損禁止
- `evidenceSnippet` 欠損禁止

## 8. SLO・監視

- 1ジョブ完了: 20分以内
- 根拠リンク付きレコード率: 99.0%以上
- メトリクス: `insight_collect_success_total`, `insight_collect_failure_total`, `insight_missing_evidence_total`
