# risk-guard 外部設計書

最終更新日: 2026-02-28

## 1. サービス概要

- 役割: 注文候補の発注可否を判定する安全ゲート。
- 主な責務: 損失上限、集中度、売買上限、kill switch、コンプライアンス制約（制限銘柄/ブラックアウト）を検証し承認/却下する。
- 主な利用者: `execution`, `bff`（内部コマンド委譲）。

## 2. 採用技術と比較

| 項目 | 採用 | 比較対象 | 採用理由 |
|---|---|---|---|
| 実行方式 | イベント駆動 | API直結で執行サービスに内包 | リスク判定を独立責務として監査しやすい |
| 状態管理 | Firestore | インメモリのみ | 判定履歴と設定版を永続化し再現可能 |
| 停止機能 | kill switch（運用API連動） | 手動運用のみ | 緊急時に自動で執行停止できる |

## 3. 外部インターフェース

### 3.1 購読イベント

- `orders.proposed`
- `operation.kill_switch.changed`

### 3.2 発行イベント

- `orders.approved`
- `orders.rejected`

### 3.3 内部コマンドAPI（BFF委譲用）

- `POST /internal/orders/{identifier}/approve`
- `POST /internal/orders/{identifier}/reject`

注記:
- 上記は内部通信専用（Service Account認可）であり、公開APIではない。
- BFFの `POST /orders/{identifier}/approve|reject` は本内部APIへ委譲される。

### 3.4 外部依存

- Firestore（リスク設定、停止状態、判定履歴）

## 4. ユースケース

### UC-RG-01: 注文承認

- 事前条件: kill switch無効、全制約を満たす。
- トリガー: `orders.proposed`受信 または `POST /internal/orders/{identifier}/approve`。
- 成果: `orders.approved`発行。

### UC-RG-02: 注文却下

- 事前条件: いずれかの制約違反、またはkill switch有効。
- トリガー: `orders.proposed`受信 または `POST /internal/orders/{identifier}/reject`。
- 成果: `orders.rejected`を理由コード付きで発行。

### UC-RG-03: コンプライアンス制約による拒否

- 事前条件: 制限銘柄またはブラックアウト期間に該当。
- トリガー: `orders.proposed`受信。
- 成果: `COMPLIANCE_RESTRICTED_SYMBOL` または `COMPLIANCE_BLACKOUT_ACTIVE` で `orders.rejected` を発行。

## 5. 非機能要件

- 判定遅延目標: `p95 < 1s`。
- 安全性: 判定失敗時はデフォルト拒否（fail closed）。
- 判定コンテキスト取得失敗時は `RISK_EVALUATION_UNAVAILABLE` で拒否する。
- 監査: 判定理由コード、設定バージョン、`trace`を必須記録。
- 監査: コンプライアンス判定結果（`symbol`, `policy`, `reasonCode`）を必須記録。

## 6. スコープ外

- 注文数量最適化アルゴリズムの内部実装。
- 約定後評価。
