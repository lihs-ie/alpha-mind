# hypothesis-lab 外部設計書

最終更新日: 2026-02-27

## 1. サービス概要

- 役割: 仮説の検証（バックテスト/デモトレード）と採否判定を管理する。
- 主な責務: 検証ジョブ実行、コスト控除評価、デモ成績評価、失敗知見登録。
- 主な利用者: 運用者、`signal-generator`。

## 2. 採用技術と比較

| 項目 | 採用 | 比較対象 | 採用理由 |
|---|---|---|---|
| 検証方式 | Walk-forward + DSR/PBO + デモトレード | 単純Holdout | 過剰適合と実運用乖離を抑制できる |
| 状態管理 | 仮説ライフサイクル管理 | 単発結果保存 | 昇格判断と再検証が追跡しやすい |
| 知見管理 | 失敗知見DBへの強制登録 | 成功結果のみ保存 | 探索効率と再発防止を高める |

## 3. 外部インターフェース

### 3.1 購読イベント

- `hypothesis.proposed`
- `hypothesis.demo.completed`

### 3.2 発行イベント

- `hypothesis.backtested`
- `hypothesis.promoted`
- `hypothesis.rejected`

### 3.3 外部依存

- Cloud Storage（検証データ、レポート）
- Firestore（hypothesis_registry, backtest_runs, demo_trade_runs, failure_knowledge）

## 4. ユースケース

### UC-HL-01: バックテスト検証

- 事前条件: 仮説定義と必要データが存在。
- トリガー: `hypothesis.proposed` 受信。
- 成果: 指標算出後に `hypothesis.backtested` を発行。

### UC-HL-02: デモトレード昇格判定

- 事前条件: バックテスト合格、デモ期間（1〜2か月）終了。
- トリガー: `hypothesis.demo.completed` 受信。
- 成果: 合格時 `hypothesis.promoted`、不合格時 `hypothesis.rejected` を発行。

## 5. 非機能要件

- 検証再現性: 入力データ版、Skill版、評価コード版を必須保存。
- 合格基準: コスト控除後指標とリスク指標を同時に満たす。
- 安全性: `requiresComplianceReview=true` は昇格禁止。
- 監査: 失敗時は原因分類を必須入力し、Markdown要約付きで `failure_knowledge` へ保存。

## 6. スコープ外

- インサイト収集。
- リアル注文執行。
