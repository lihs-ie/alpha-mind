# risk-guard ドメインモデル設計

最終更新日: 2026-02-28
対象Bounded Context: `risk-guard`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: 注文候補に対するリスク/コンプライアンス判定を、再現可能な業務ルールとして定義する。
- スコープ内:
1. `orders.proposed` 受信時の承認/却下判定
2. `operation.kill_switch.changed` 反映
3. `orders.approved` / `orders.rejected` 発行
4. 判定結果の監査記録と冪等性制御
- スコープ外:
1. 注文候補生成（`portfolio-planner`）
2. 注文執行（`execution`）
3. UI操作・認可判定（`bff`）

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Order Risk Decision`
- ミッション: `PROPOSED` 注文を安全制約で評価し、`APPROVED` または `REJECTED` へ遷移させる。
- コア/支援/汎用サブドメイン区分: `core`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Order Proposal | 審査対象の注文候補 | `orders.proposed` | 注文確定（executed）と混同しない |
| Risk Evaluation | リスク上限・停止状態・コンプライアンス制約の判定 | `risk-guard` | 部分判定で承認しない |
| Compliance Controls | 制限銘柄/ブラックアウト等の制約設定 | `compliance_controls` | 参照専用。risk-guardで編集しない |
| Kill Switch | 発注系停止フラグ | `operations.runtime` / `operation.kill_switch.changed` | 有効時は fail-closed |
| Decision | 承認または却下の最終判断 | `orders.approved/rejected` | 根拠なし決定を禁止 |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `portfolio-planner` | Upstream (`Customer-Supplier`) | `orders.proposed` | 提案payloadを審査対象へ正規化 |
| `bff` | Upstream (`Customer-Supplier`) | `POST /orders/{identifier}/approve`, `POST /orders/{identifier}/reject`, `POST /operations/kill-switch` | APIコマンドを審査/停止状態へ反映 |
| `execution` | Downstream (`OHS+PL`) | `orders.approved` | 承認済み注文のみ公開 |
| `audit-log` | Downstream (`OHS+PL`) | `orders.approved`, `orders.rejected` | `trace`, `reasonCode` を必須伝播 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-RG-001` | `status=PROPOSED` の注文のみ審査できる | must | inside |
| `RULE-RG-002` | kill switch有効時は必ず却下（`KILL_SWITCH_ENABLED`）する | must | inside |
| `RULE-RG-003` | リスク上限違反時は却下（`RISK_LIMIT_EXCEEDED`）する | must | inside |
| `RULE-RG-004` | `restrictedSymbols` または `partnerRestrictedSymbols` 該当時は却下（`COMPLIANCE_RESTRICTED_SYMBOL`）する | must | inside |
| `RULE-RG-005` | ブラックアウト期間該当時は却下（`COMPLIANCE_BLACKOUT_ACTIVE`）する | must | inside |
| `RULE-RG-006` | 判定不能時は fail-closed で却下する | must | inside |
| `RULE-RG-007` | 同一イベント `identifier` は1回のみ処理する | must | outside |
| `RULE-RG-008` | 判定結果は `trace`, `identifier`, `reasonCode` を監査保存する | must | outside |
| `RULE-RG-009` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: risk-guard order screening
  Rule: kill switch有効時は承認しない
    Example: kill switch有効で却下
      Given status が PROPOSED の注文が存在する
      And killSwitchEnabled が true
      When orders.proposed を受信する
      Then 注文は REJECTED になる
      And reasonCode は KILL_SWITCH_ENABLED になる
      And orders.rejected が発行される
```

```gherkin
Feature: risk-guard order screening
  Rule: コンプライアンス制約違反は却下する
    Example: 制限銘柄で却下
      Given status が PROPOSED の注文が存在する
      And symbol が restrictedSymbols に含まれる
      When orders.proposed を受信する
      Then 注文は REJECTED になる
      And reasonCode は COMPLIANCE_RESTRICTED_SYMBOL になる
```

```gherkin
Feature: risk-guard order screening
  Rule: 全制約を満たす注文は承認する
    Example: 承認
      Given status が PROPOSED の注文が存在する
      And killSwitchEnabled が false
      And リスク上限・コンプライアンス制約をすべて満たす
      When orders.proposed を受信する
      Then 注文は APPROVED になる
      And orders.approved が発行される
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-RG-001` | `SCN-RG-001` | `OrderRiskAssessment` | `orders.proposed` | `TST-RG-001` |
| `RULE-RG-002` | `SCN-RG-002` | `OrderRiskAssessment` | `orders.proposed`, `operation.kill_switch.changed` | `TST-RG-002` |
| `RULE-RG-003` | `SCN-RG-003` | `OrderRiskAssessment` | `orders.proposed` | `TST-RG-003` |
| `RULE-RG-004` | `SCN-RG-004` | `OrderRiskAssessment` | `orders.proposed`, `GET/PUT /compliance/controls` | `TST-RG-004` |
| `RULE-RG-005` | `SCN-RG-005` | `OrderRiskAssessment` | `orders.proposed` | `TST-RG-005` |
| `RULE-RG-007` | `SCN-RG-006` | `OrderRiskAssessment` | `orders.proposed` | `TST-RG-006` |
| `RULE-RG-008` | `SCN-RG-007` | `OrderRiskAssessment` | `orders.approved/rejected` | `TST-RG-007` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `OrderRiskAssessment` | `OrderRiskAssessment` | 1注文の審査結果を確定する | `orders/{identifier}` | 二重決定禁止、決定理由必須 |

#### Aggregate詳細: `OrderRiskAssessment`

- root: `OrderRiskAssessment`
- 参照先集約: なし（`settings/operations/compliance_controls` は参照モデル）
- 生成コマンド: `AcceptOrderProposal`
- 更新コマンド: `EvaluateOrderRisk`, `SyncKillSwitchState`
- 削除/無効化コマンド: `TerminateAssessment`
- 不変条件:
1. 決定は `approved` または `rejected` のいずれか1回のみ確定できる。
2. `decision=rejected` のとき `reasonCode` は `KILL_SWITCH_ENABLED` / `RISK_LIMIT_EXCEEDED` / `COMPLIANCE_RESTRICTED_SYMBOL` / `COMPLIANCE_BLACKOUT_ACTIVE` / `RISK_EVALUATION_UNAVAILABLE` のいずれか。
3. `status!=PROPOSED` の注文に対して審査コマンドを適用してはならない。
4. `identifier` は不変。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 注文識別子（`orders/{identifier}`） | `1` |
| `proposal` | `OrderProposal` | 審査対象注文 | `1` |
| `orderStatus` | `enum(PROPOSED, APPROVED, REJECTED, EXECUTED, FAILED)` | 注文状態の現在値 | `1` |
| `decision` | `enum(approved, rejected)` | 審査の最終判定 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 判定理由コード（却下時必須） | `0..1` |
| `actionReasonCode` | `enum(OperatorActionReasonCode)` | 手動操作理由コード | `0..1` |
| `trace` | `string` | 追跡識別子 | `1` |
| `evaluatedAt` | `datetime` | 判定時刻 | `0..1` |
| `killSwitchEnabled` | `boolean` | 審査時点の停止状態 | `1` |
| `settingsVersion` | `integer` | 審査に使った設定版 | `0..1` |
| `complianceUpdatedAt` | `datetime` | 審査に使ったコンプライアンス設定の更新時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `riskLimits` | `RiskLimits` | リスク上限設定のスナップショット | `1` |
| `compliancePolicy` | `CompliancePolicy` | コンプライアンス制約のスナップショット | `1` |
| `riskExposure` | `RiskExposure` | 評価時点のリスク指標 | `1` |
| `decisionRecord` | `DecisionRecord` | 判定結果と根拠 | `0..1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `OrderRiskAssessment` | `identifier` | `PROPOSED -> APPROVED/REJECTED` | `evaluate`, `approve`, `reject` |
| `OrderProposal` | `identifier` | `received -> screened` | `validatePayload`, `resolveSymbol` |

#### Entity詳細: `OrderRiskAssessment`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 注文識別子 | `1` |
| `orderStatus` | `enum(PROPOSED, APPROVED, REJECTED, EXECUTED, FAILED)` | 注文状態 | `1` |
| `decision` | `enum(approved, rejected)` | 審査判定 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 判定理由（却下時必須） | `0..1` |
| `actionReasonCode` | `enum(OperatorActionReasonCode)` | 手動操作理由 | `0..1` |
| `trace` | `string` | トレース情報 | `1` |

#### Entity詳細: `OrderProposal`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 提案対象注文の識別子 | `1` |
| `symbol` | `string` | 銘柄コード | `1` |
| `side` | `enum(BUY, SELL)` | 売買区分 | `1` |
| `qty` | `number` | 注文数量 | `1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `RiskLimits` | `dailyLossLimit`, `positionConcentrationLimit`, `dailyOrderLimit` | 値比較 | immutable |
| `CompliancePolicy` | `restrictedSymbols`, `partnerRestrictedSymbols`, `blackoutWindows` | 値比較 | immutable |
| `RiskExposure` | `dailyLossRate`, `positionConcentrationRate`, `dailyOrderCount` | 値比較 | immutable |
| `DecisionRecord` | `decision`, `reasonCode`, `actionReasonCode`, `evaluatedAt`, `trace` | 値比較 | immutable |
| `BlackoutWindow` | `symbol`, `startAt`, `endAt`, `reasonCode` | 値比較 | immutable |

#### Value Object詳細: `RiskLimits`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `dailyLossLimit` | `number` | 1日損失上限（%） | `1` |
| `positionConcentrationLimit` | `number` | 1銘柄集中上限（%） | `1` |
| `dailyOrderLimit` | `integer` | 1日注文上限件数 | `1` |

#### Value Object詳細: `CompliancePolicy`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `restrictedSymbols` | `array<string>` | 制限銘柄 | `0..n` |
| `partnerRestrictedSymbols` | `array<string>` | 取引先関連制限銘柄 | `0..n` |
| `blackoutWindows` | `array<BlackoutWindow>` | ブラックアウト期間 | `0..n` |

#### Value Object詳細: `RiskExposure`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `dailyLossRate` | `number` | 当日損失率（%） | `1` |
| `positionConcentrationRate` | `number` | 対象銘柄の集中率（%） | `1` |
| `dailyOrderCount` | `integer` | 当日注文件数 | `1` |

#### Value Object詳細: `DecisionRecord`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `decision` | `enum(approved, rejected)` | 判定結果 | `1` |
| `reasonCode` | `enum(ReasonCode)` | 判定理由（`decision=rejected` 時は必須） | `0..1` |
| `actionReasonCode` | `enum(OperatorActionReasonCode)` | 手動操作理由 | `0..1` |
| `evaluatedAt` | `datetime` | 判定時刻 | `1` |
| `trace` | `string` | トレース情報 | `1` |

#### Value Object詳細: `BlackoutWindow`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `symbol` | `string` | 対象銘柄 | `1` |
| `startAt` | `datetime` | 開始日時 | `1` |
| `endAt` | `datetime` | 終了日時 | `1` |
| `reasonCode` | `string` | 設定理由 | `1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `RiskScreeningPolicy` | domain | リスク/コンプライアンス判定の合成評価 | Firestoreアクセス |
| `KillSwitchPolicy` | domain | kill switch判定 | IO処理 |
| `OrderScreeningService` | application | 受信イベント/APIコマンドのオーケストレーション | 業務ルール本体 |
| `AuditTrailWriter` | application | 判定監査ログ出力 | 判定ロジック |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `OrderRiskAssessmentRepository` | 審査結果永続化 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `IdempotencyKeyRepository` | 重複処理防止 | `Find`, `Persist`, `Terminate` |
| Factory | `OrderRiskAssessmentFactory` | 提案注文から審査集約生成 | `fromOrdersProposed` |
| Specification | `ProposedStatusSpecification` | `PROPOSED` 状態確認 | `isSatisfiedBy(order)` |
| Specification | `RiskLimitSpecification` | リスク上限判定 | `isSatisfiedBy(exposure)` |
| Specification | `ComplianceSpecification` | 制限銘柄/ブラックアウト判定 | `isSatisfiedBy(order)` |

#### 4.5.1 interface signature

| 役割 | 命名規則 | 用途 |
| - | - | - |
| 永続化 | Persist | 集約・エンティティを永続化する |
| 削除 | Terminate | 集約・エンティティを削除する |
| Identifierによる単一取得 | Find | 識別子を指定して集約・エンティティを単体で取得する |
| Identifier以外の要素による単一取得 | FindBy{XXX} | 識別子以外の要素を指定して集約・エンティティを単体で取得する |
| 複数取得 | Search | 検索条件（Criteria）を受け取り条件に合致する集約・エンティティを全て取得する |

## 5. 状態遷移と不変条件

### 5.1 状態遷移

| 現在状態 | コマンド | 次状態 | ガード条件 | 失敗時reasonCode |
|---|---|---|---|---|
| `PROPOSED` | `EvaluateOrderRisk` | `APPROVED` | kill switch無効 + リスク制約OK + コンプライアンス制約OK | - |
| `PROPOSED` | `EvaluateOrderRisk` | `REJECTED` | kill switch有効 | `KILL_SWITCH_ENABLED` |
| `PROPOSED` | `EvaluateOrderRisk` | `REJECTED` | リスク上限違反 | `RISK_LIMIT_EXCEEDED` |
| `PROPOSED` | `EvaluateOrderRisk` | `REJECTED` | 制限銘柄/取引先関連制限銘柄該当 | `COMPLIANCE_RESTRICTED_SYMBOL` |
| `PROPOSED` | `EvaluateOrderRisk` | `REJECTED` | ブラックアウト期間該当 | `COMPLIANCE_BLACKOUT_ACTIVE` |
| `PROPOSED` | `EvaluateOrderRisk` | `REJECTED` | 判定コンテキスト取得失敗（fail-closed） | `RISK_EVALUATION_UNAVAILABLE` |
| `APPROVED` | `EvaluateOrderRisk` | `APPROVED` | 同一identifierの重複受信 | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `REJECTED` | `EvaluateOrderRisk` | `REJECTED` | 同一identifierの重複受信 | `IDEMPOTENCY_DUPLICATE_EVENT` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-RG-001` | `OrderRiskAssessment` | `status=PROPOSED` のときのみ審査可 | コマンド拒否 |
| `INV-RG-002` | `OrderRiskAssessment` | `decision` 確定後に再判定しない（冪等重複を除く） | 副作用なし終了 |
| `INV-RG-003` | `OrderRiskAssessment` | `decision=rejected` の場合、`reasonCode` 必須 | コマンド拒否 |
| `INV-RG-004` | `OrderRiskAssessment` | kill switch有効時は必ず `rejected` | コマンド拒否 |
| `INV-RG-005` | `OrderRiskAssessment` | 制限銘柄/ブラックアウト該当時は必ず `rejected` | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `order.risk.evaluated` | `OrderRiskAssessment` | 判定確定後 | `identifier`, `decision`, `reasonCode?`, `actionReasonCode?`, `trace`, `evaluatedAt` | `identifier` |
| `order.risk.rejected` | `OrderRiskAssessment` | 却下確定後 | `identifier`, `reasonCode`, `trace` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `orders.approved` | `execution`, `audit-log`, `bff` | AsyncAPI（`actionReasonCode` optional, `reasonCode` optional） | eventual consistency | max3 + DLQ |
| `orders.rejected` | `audit-log`, `bff` | AsyncAPI（`reasonCode` required） | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 提案注文審査 | `EvaluateOrderRisk` | なし | `orders.proposed`（受信） | 主フロー |
| 手動承認 | `EvaluateOrderRisk` | `POST /orders/{identifier}/approve` | `orders.approved`（発行） | `PROPOSED` のみ |
| 手動却下 | `RejectOrder` | `POST /orders/{identifier}/reject` | `orders.rejected`（発行） | 理由コード必須 |
| kill switch反映 | `SyncKillSwitchState` | `POST /operations/kill-switch` | `operation.kill_switch.changed`（受信） | 審査ガード更新 |
| 制約設定反映 | `LoadCompliancePolicy` | `GET/PUT /compliance/controls` | なし | 参照モデル更新 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `OrderRiskAssessment` | `risk-guard` | `orders` | 単一集約 | `trace`, `identifier`, `reasonCode` |
| `IdempotencyKey` | `risk-guard` | `idempotency_keys` | 単一ドキュメント | `trace`, `identifier`, `service` |
| `RiskDecisionAudit` | `risk-guard` | `audit_logs` | 判定確定後の別Tx | `trace`, `identifier`, `reasonCode`, `symbol` |
| `RiskLimits/CompliancePolicy` | `bff`（参照のみ） | `settings`, `operations`, `compliance_controls` | 読み取り専用 | `updatedAt`, `updatedBy` |

- 他集約更新は同一Txで行わない。
- `orders` 更新成功後に `orders.approved/rejected` を発行する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-RG-001` | acceptance | `RULE-RG-001` | `status!=PROPOSED` の審査拒否 |
| `TST-RG-002` | acceptance | `RULE-RG-002` | kill switch有効時に必ず却下 |
| `TST-RG-003` | acceptance | `RULE-RG-003` | リスク上限違反で却下 |
| `TST-RG-004` | acceptance | `RULE-RG-004` | 制限銘柄/取引先関連銘柄で却下 |
| `TST-RG-005` | acceptance | `RULE-RG-005` | ブラックアウト期間で却下 |
| `TST-RG-006` | idempotency | `RULE-RG-007` | 同一identifier重複で副作用なし |
| `TST-RG-007` | audit | `RULE-RG-008` | 監査項目の欠損なし |
| `TST-RG-008` | contract | `RULE-RG-009` | OpenAPI/AsyncAPIの識別子命名整合 |

- 受け入れ: Gherkinの `Given/When/Then`
- ドメイン: 不変条件・状態遷移・イベント発行
- 契約: OpenAPI/AsyncAPI lint + schema検証

## 10. 実装規約（このプロジェクト向け）

- ドメイン設計（Aggregate/Entity/Value Object/Domain Event）にも `Identifier` 命名規約を適用する。
- `Id` は使わず `identifier` を使う。
- 当該関心ごとの識別子は `identifier`。
- 他関心ごとの識別子は `{entity}`（例: `user`）。
- 集約外参照はID参照のみ（オブジェクト参照禁止）。
- 識別子生成は `ULID` を使用する。
- `UUIDv4` はトークン等、推測耐性のために高いランダム性が必要な用途でのみ利用する。
- イベントエンベロープ `identifier` は `ULID` を使用する。

## 11. レビュー観点

- 判定ルール（kill switch / リスク上限 / コンプライアンス）の優先順位が実装と一致しているか。
- fail-closedの理由コードが監査/運用Runbookと整合しているか。
- `orders.approved/rejected` 発行が `orders` 更新後になっているか。
- 冪等処理が `idempotency_keys` で担保されているか。
- Rule→Scenario→Model→Contract→Test のトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/risk-guard.md`
- `documents/内部設計/services/risk-guard.md`
- `documents/外部設計/api/openapi.yaml`
- `documents/外部設計/api/asyncapi.yaml`
- `documents/外部設計/state/状態遷移設計.md`
- `documents/外部設計/security/認証認可設計.md`
- `documents/外部設計/db/firestore設計.md`
- `documents/外部設計/error/error-codes.json`
