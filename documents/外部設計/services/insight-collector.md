# insight-collector 外部設計書

最終更新日: 2026-02-28

## 1. サービス概要

- 役割: 定性データソースから投資インサイトを収集・構造化する。
- 主な責務: X/YouTube/論文/GitHubの収集、ノイズ除去、根拠付き要約、保存。
- 主な利用者: `agent-orchestrator`。

## 2. 採用技術と比較

| 項目 | 採用 | 比較対象 | 採用理由 |
|---|---|---|---|
| 収集方式 | Cloud Run Job + Skill実行 | 手作業収集 | 定期収集と再現実行を統一できる |
| 入力ソース | X/YouTube/論文/GitHub（許可制） | 単一ニュースのみ | 多角的情報で探索バイアスを下げる |
| 出力形式 | 構造化JSON + 根拠リンク | 自由文のみ | 下流で機械判定・再利用しやすい |

## 3. 外部インターフェース

### 3.1 購読イベント

- `insight.collect.requested`

### 3.2 発行イベント

- `insight.collected`
- `insight.collect.failed`

### 3.3 外部依存

- X API（または許可済み代替）
- YouTube Data API / 字幕取得API
- 論文・リポジトリ取得元
- Cloud Storage
- Firestore（skill_registry, source_policies, insight_records）

## 4. ユースケース

### UC-IC-01: 定性データの定時収集

- 事前条件: 収集対象ソースが許可リストに登録済み。
- トリガー: `insight.collect.requested` 受信。
- 成果: ソース別インサイトを保存し `insight.collected` を発行。

### UC-IC-02: 不許可ソース遮断

- 事前条件: 許可リスト外ソースが指定される。
- トリガー: 収集リクエスト実行。
- 成果: 収集を中断し `insight.collect.failed` を理由コード付きで発行。

### UC-IC-03: 利用規約違反ソースの遮断

- 事前条件: ソースが許可済みだが規約条件（再配布可否、API利用上限）が未充足。
- トリガー: 収集リクエスト実行。
- 成果: 収集を中断し `COMPLIANCE_SOURCE_UNAPPROVED` で失敗記録する。

## 5. 非機能要件

- 完了目標: 1サイクル `20分以内`。
- 品質: すべてのインサイトに `sourceUrl` `collectedAt` `evidenceSnippet` を保持。
- セキュリティ: 利用規約違反ソースを自動拒否。
- 監査: 収集Skill版、適用ソースポリシー版、除外理由を必須記録。

## 6. スコープ外

- 売買シグナル算出。
- 注文作成・執行。
