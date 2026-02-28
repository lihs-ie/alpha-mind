# agent-orchestrator 外部設計書

最終更新日: 2026-02-27

## 1. サービス概要

- 役割: Skillを実行して定性/定量情報を仮説へ変換する。
- 主な責務: Skill選択、Markdown指示書適用、仮説生成、重複抑止、実行履歴管理。
- 主な利用者: `hypothesis-lab`。

## 2. 採用技術と比較

| 項目 | 採用 | 比較対象 | 採用理由 |
|---|---|---|---|
| 実行モデル | イベント駆動オーケストレーション | 手動バッチ実行 | 仮説生成を継続運用へ組み込める |
| 指示管理 | Markdownプロトコル | 自由入力 | 分析品質のばらつきを抑制できる |
| 重複対策 | 失敗知見DB照合 | 人手判断 | 近傍仮説の無駄な反復を減らせる |

## 3. 外部インターフェース

### 3.1 購読イベント

- `insight.collected`
- `hypothesis.retest.requested`

### 3.2 発行イベント

- `hypothesis.proposed`
- `hypothesis.proposal.failed`

### 3.3 外部依存

- Firestore（skill_registry, instruction_profiles, code_reference_templates, failure_knowledge）
- Cloud Storage（生成レポート）
- LLM実行基盤

## 4. ユースケース

### UC-AO-01: 仮説生成

- 事前条件: 対応Skillと指示書が有効。
- トリガー: `insight.collected` 受信。
- 成果: 仮説候補を生成して `hypothesis.proposed` を発行。

### UC-AO-02: 重複仮説の抑止

- 事前条件: 類似失敗仮説が一定閾値以上で一致。
- トリガー: 仮説生成処理。
- 成果: 仮説を棄却し `hypothesis.proposal.failed` を記録。

### UC-AO-03: 自作コード参照テンプレート適用

- 事前条件: `code_reference_templates` に対象戦略のテンプレートが登録済み。
- トリガー: 仮説生成処理。
- 成果: 生成プロンプトにテンプレートを適用し、再現可能な分析手順を出力する。

## 5. 非機能要件

- 完了目標: 1サイクル `10分以内`。
- 品質: 仮説に `identifier`, `sourceEvidence`, `skillVersion`, `instructionProfileVersion` を必須付与。
- 品質: 失敗知見はMarkdown要約（原因、再発防止、適用条件）として必須保存する。
- 安全性: 出力は原則人手承認を通過させる。昇格は無条件自動を禁止し、ETF低リスク条件のみ自動昇格を許可する。
- 監査: 実行プロンプトハッシュと結果を追跡可能にする。

## 6. スコープ外

- バックテスト計算。
- 発注・執行制御。
