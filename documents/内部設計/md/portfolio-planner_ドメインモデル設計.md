# portfolio-planner ドメインモデル設計

最終更新日: 2026-03-03
対象Bounded Context: `portfolio-planner`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: `signal.generated` を注文候補へ変換し、`orders.proposed` を一貫した業務ルールで生成する。
- スコープ内:
1. `signal.generated` 受信時の入力検証と提案計算
2. `orders` への `PROPOSED` 保存
3. `orders.proposed` / `orders.proposal.failed` 発行
4. 冪等性制御と監査保存
- スコープ外:
1. シグナル生成（`signal-generator`）
2. リスク承認判定（`risk-guard`）
3. 執行（`execution`）

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Order Proposal Planning`
- ミッション: 市場シグナルと運用設定から、審査可能な `PROPOSED` 注文候補を確定する。
- コア/支援/汎用サブドメイン区分: `core`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Signal Snapshot | `signal.generated` 由来の入力スナップショット | AsyncAPI payload | 部分項目欠損のまま計算しない |
| Order Proposal | 提案された単一注文 | `orders` | 承認済み注文（`APPROVED`）と混同しない |
| Proposal Dispatch | 1回の提案配信処理（バッチ） | `idempotency_keys` | 同一イベント二重配信を禁止 |
| Strategy Setting | 注文計算に使う運用設定 | `settings` | 未ロード状態で提案しない |
| Account Snapshot | 残高・余力など参照情報 | Broker Account API | staleデータで提案しない |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `signal-generator` | Upstream (`Customer-Supplier`) | `signal.generated` | シグナルpayloadを `SignalSnapshot` へ正規化 |
| `risk-guard` | Downstream (`OHS+PL`) | `orders.proposed` | `PROPOSED` 注文のみ公開 |
| `audit-log` | Downstream (`OHS+PL`) | `orders.proposed`, `orders.proposal.failed` | `trace`, `identifier`, `reasonCode` を必須伝播 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-PP-001` | `signal.generated` の必須項目（`signalVersion`, `modelVersion`, `featureVersion`, `storagePath`, `modelDiagnostics`）欠損時は提案を作らない | must | inside |
| `RULE-PP-002` | `modelDiagnostics.requiresComplianceReview=true` の場合は fail-closed で `orders.proposal.failed` を発行する | must | inside |
| `RULE-PP-003` | 同一イベント `identifier`（event envelope）は1回のみ処理する | must | outside |
| `RULE-PP-004` | 保存する注文は `status=PROPOSED` かつ `qty>0` を満たす | must | inside |
| `RULE-PP-005` | `orderCount` は `orders` の件数と一致させる | must | outside |
| `RULE-PP-006` | `orders` 保存成功後にのみ `orders.proposed` を発行する | must | outside |
| `RULE-PP-007` | 依存取得失敗時は `orders.proposal.failed` を発行し、`orders.proposed` を発行しない | must | outside |
| `RULE-PP-008` | すべての結果イベントに `trace` と `identifier` を含める | must | outside |
| `RULE-PP-009` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: portfolio-planner proposal planning
  Rule: 有効なsignalから注文候補を生成する
    Example: 正常提案
      Given signal.generated の必須項目が揃っている
      And modelDiagnostics.requiresComplianceReview が false
      And 運用設定と残高情報が取得できる
      When signal.generated を受信する
      Then status=PROPOSED の orders が保存される
      And orders.proposed が発行される
```

```gherkin
Feature: portfolio-planner proposal planning
  Rule: コンプライアンスレビュー要求時は提案を停止する
    Example: requiresComplianceReview=true
      Given signal.generated の modelDiagnostics.requiresComplianceReview が true
      When signal.generated を受信する
      Then orders.proposal.failed が発行される
      And reasonCode は COMPLIANCE_REVIEW_REQUIRED になる
```

```gherkin
Feature: portfolio-planner proposal planning
  Rule: 同一イベントidentifierは重複処理しない
    Example: 重複受信
      Given 同一イベントidentifierが既に処理済みである
      When signal.generated を受信する
      Then 新しい orders は保存されない
      And orders.proposed は再発行されない
```

```gherkin
Feature: portfolio-planner proposal planning
  Rule: 依存取得失敗時は失敗イベントを返す
    Example: 口座情報取得タイムアウト
      Given signal.generated の必須項目が揃っている
      And Broker Account API 呼び出しが timeout する
      When signal.generated を受信する
      Then orders.proposal.failed が発行される
      And reasonCode は DEPENDENCY_TIMEOUT になる
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-PP-001` | `SCN-PP-001` | `OrderProposal` | `signal.generated` | `TST-PP-001` |
| `RULE-PP-002` | `SCN-PP-002` | `ProposalDispatch` | `signal.generated`, `orders.proposal.failed` | `TST-PP-002` |
| `RULE-PP-003` | `SCN-PP-003` | `ProposalDispatch` | `signal.generated` | `TST-PP-003` |
| `RULE-PP-004` | `SCN-PP-001` | `OrderProposal` | `orders.proposed` | `TST-PP-004` |
| `RULE-PP-005` | `SCN-PP-001` | `ProposalDispatch` | `orders.proposed` | `TST-PP-005` |
| `RULE-PP-006` | `SCN-PP-001` | `ProposalDispatch` | `orders.proposed` | `TST-PP-006` |
| `RULE-PP-007` | `SCN-PP-004` | `ProposalDispatch` | `orders.proposal.failed` | `TST-PP-007` |
| `RULE-PP-008` | `SCN-PP-001` | `ProposalDispatch` | `orders.proposed`, `orders.proposal.failed` | `TST-PP-008` |
| `RULE-PP-009` | `SCN-PP-009` | `OrderProposal` | OpenAPI/AsyncAPI/Domain Model | `TST-PP-009` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `OrderProposal` | `OrderProposal` | 単一注文候補の整合を確定する | `orders/{identifier}` | `status=PROPOSED`, `qty>0`, `identifier` 不変 |
| `ProposalDispatch` | `ProposalDispatch` | 提案配信の重複防止と結果確定を行う | `idempotency_keys/{identifier}` | 同一イベントの二重配信禁止、`orderCount` 整合 |

#### Aggregate詳細: `OrderProposal`

- root: `OrderProposal`
- 参照先集約: `ProposalDispatch`（`identifier` 参照のみ）
- 生成コマンド: `CreateOrderProposal`
- 更新コマンド: `AttachProposalContext`
- 削除/無効化コマンド: `TerminateOrderProposal`
- 不変条件:
1. 生成時の `status` は必ず `PROPOSED`。
2. `qty` は正数。
3. `identifier` は生成後に変更不可。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 注文識別子（ULID） | `1` |
| `symbol` | `string` | 銘柄コード | `1` |
| `side` | `enum(BUY, SELL)` | 売買区分 | `1` |
| `qty` | `number` | 注文数量 | `1` |
| `status` | `enum(PROPOSED, APPROVED, REJECTED, EXECUTED, FAILED)` | 注文状態 | `1` |
| `trace` | `string` | トレース識別子 | `1` |
| `createdAt` | `datetime` | 提案作成時刻 | `1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `signalSnapshot` | `SignalSnapshot` | 入力シグナルのスナップショット | `1` |
| `positionSnapshot` | `PositionSnapshot` | 保有状況スナップショット | `0..1` |
| `strategySnapshot` | `StrategySnapshot` | 設定スナップショット | `1` |

#### Aggregate詳細: `ProposalDispatch`

- root: `ProposalDispatch`
- 参照先集約: `OrderProposal`（`identifier` リスト参照のみ）
- 生成コマンド: `StartDispatch`
- 更新コマンド: `CompleteDispatch`, `FailDispatch`
- 削除/無効化コマンド: `TerminateDispatch`
- 不変条件:
1. 同一イベント `identifier` は1回のみ `completed` へ遷移できる。
2. `dispatchStatus=completed` のとき `orderCount` は `orders` 件数と一致する。
3. `dispatchStatus=failed` のとき `reasonCode` 必須。

#### 4.1.1 Aggregate Rootフィールド定義（ProposalDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子（ULID） | `1` |
| `dispatchStatus` | `enum(pending, completed, failed)` | 配信処理状態 | `1` |
| `orderCount` | `integer` | 発行対象注文数 | `0..1` |
| `orders` | `array<string>` | 発行対象注文識別子 | `0..n` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由コード | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |
| `processedAt` | `datetime` | 処理完了時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（ProposalDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `signalSnapshot` | `SignalSnapshot` | 受信シグナルの要約 | `1` |
| `accountSnapshot` | `AccountSnapshot` | 余力情報の要約 | `0..1` |
| `dispatchDecision` | `DispatchDecision` | 成否と根拠 | `1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `OrderProposal` | `identifier` | `created -> proposed` | `create`, `validateQuantity` |
| `ProposalDispatch` | `identifier` | `pending -> completed/failed` | `start`, `complete`, `fail` |

#### Entity詳細: `OrderProposal`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 注文識別子 | `1` |
| `symbol` | `string` | 銘柄コード | `1` |
| `side` | `enum(BUY, SELL)` | 売買区分 | `1` |
| `qty` | `number` | 注文数量 | `1` |
| `status` | `enum(PROPOSED, APPROVED, REJECTED, EXECUTED, FAILED)` | 注文状態 | `1` |
| `trace` | `string` | トレース識別子 | `1` |

#### Entity詳細: `ProposalDispatch`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子 | `1` |
| `dispatchStatus` | `enum(pending, completed, failed)` | 配信状態 | `1` |
| `orderCount` | `integer` | 発行注文件数 | `0..1` |
| `orders` | `array<string>` | 発行注文識別子 | `0..n` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `SignalSnapshot` | `signalVersion`, `modelVersion`, `featureVersion`, `storagePath`, `degradationFlag`, `requiresComplianceReview` | 値比較 | immutable |
| `PositionSnapshot` | `symbol`, `holdingQty`, `asOf` | 値比較 | immutable |
| `StrategySnapshot` | `maxOrderCount`, `maxSingleOrderQty`, `rebalanceThreshold` | 値比較 | immutable |
| `AccountSnapshot` | `availableCash`, `asOf` | 値比較 | immutable |
| `DispatchDecision` | `dispatchStatus`, `reasonCode`, `detail` | 値比較 | immutable |

#### Value Object詳細: `SignalSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `signalVersion` | `string` | シグナル版 | `1` |
| `modelVersion` | `string` | モデル版 | `1` |
| `featureVersion` | `string` | 特徴量版 | `1` |
| `storagePath` | `string` | シグナル格納先 | `1` |
| `degradationFlag` | `enum(normal, warn, block)` | 劣化フラグ | `1` |
| `requiresComplianceReview` | `boolean` | コンプライアンスレビュー要否 | `1` |

#### Value Object詳細: `PositionSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `symbol` | `string` | 対象銘柄 | `1` |
| `holdingQty` | `number` | 保有数量 | `1` |
| `asOf` | `datetime` | 取得時刻 | `1` |

#### Value Object詳細: `StrategySnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `maxOrderCount` | `integer` | 1回の最大提案件数 | `1` |
| `maxSingleOrderQty` | `number` | 1注文の上限数量 | `1` |
| `rebalanceThreshold` | `number` | 提案生成閾値 | `1` |

#### Value Object詳細: `AccountSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `availableCash` | `number` | 利用可能余力 | `1` |
| `asOf` | `datetime` | 取得時刻 | `1` |

#### Value Object詳細: `DispatchDecision`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `dispatchStatus` | `enum(pending, completed, failed)` | 成否状態 | `1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由コード | `0..1` |
| `detail` | `string` | 補足情報 | `0..1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `ProposalEligibilityPolicy` | domain | シグナル利用可否（レビュー要否・欠損）判定 | IO処理 |
| `OrderSizingPolicy` | domain | 数量計算と上限適用 | Firestoreアクセス |
| `PortfolioPlanningService` | application | 入力取得から提案保存/発行までのオーケストレーション | 業務ルール本体 |
| `ProposalAuditWriter` | application | 監査ログ記録 | 提案判定ロジック |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `OrderProposalRepository` | 注文候補永続化 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `ProposalDispatchRepository` | 配信状態永続化 | `Find`, `Persist`, `Terminate` |
| Repository | `IdempotencyKeyRepository` | 重複処理防止 | `Find`, `Persist`, `Terminate` |
| Factory | `OrderProposalFactory` | シグナルから注文候補生成 | `fromSignalSnapshot` |
| Factory | `ProposalDispatchFactory` | 入力イベントから配信集約生成 | `fromSignalGeneratedEvent` |
| Specification | `SignalIntegritySpecification` | 必須項目整合判定 | `isSatisfiedBy(signal)` |
| Specification | `ComplianceReviewGateSpecification` | `requiresComplianceReview` 判定 | `isSatisfiedBy(signal)` |
| Specification | `ProposalBatchConsistencySpecification` | `orderCount` と `orders` 件数整合判定 | `isSatisfiedBy(dispatch)` |

#### 4.5.1 interface signature

| 役割 | 命名規則 | 用途 |
| - | - | - |
| 永続化 | Persist | 集約・エンティティを永続化する |
| 削除 | Terminate | 集約・エンティティを削除する |
| Identifierによる単一取得 | Find | 識別子を指定して集約・エンティティを単体で取得する |
| Identifier以外の要素による取得 | FindBy{XXX} | 識別子以外の要素を指定して集約・エンティティを取得する（単一/複数はI/F定義で明記） |
| 複数取得 | Search | 検索条件（Criteria）を受け取り条件に合致する集約・エンティティを全て取得する |

## 5. 状態遷移と不変条件

### 5.1 状態遷移

| 現在状態 | コマンド | 次状態 | ガード条件 | 失敗時reasonCode |
|---|---|---|---|---|
| なし | `CreateOrderProposal` | `PROPOSED` | `qty>0` かつ必須項目あり | `REQUEST_VALIDATION_FAILED` |
| `PROPOSED` | `CreateOrderProposal` | `PROPOSED` | 同一イベントidentifier重複受信 | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `pending` | `CompleteDispatch` | `completed` | `orderCount == len(orders)` | - |
| `pending` | `FailDispatch` | `failed` | `requiresComplianceReview=true` | `COMPLIANCE_REVIEW_REQUIRED` |
| `pending` | `FailDispatch` | `failed` | 依存取得失敗 | `DEPENDENCY_TIMEOUT` / `DEPENDENCY_UNAVAILABLE` |
| `completed` | `CompleteDispatch` | `completed` | 同一イベントidentifier重複処理 | `IDEMPOTENCY_DUPLICATE_EVENT` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-PP-001` | `OrderProposal` | `status=PROPOSED` で生成される | コマンド拒否 |
| `INV-PP-002` | `OrderProposal` | `qty>0` | コマンド拒否 |
| `INV-PP-003` | `ProposalDispatch` | 同一イベント `identifier` は1回のみ完了 | 冪等扱い |
| `INV-PP-004` | `ProposalDispatch` | `dispatchStatus=completed` 時に `orderCount` と件数一致 | コマンド拒否 |
| `INV-PP-005` | `ProposalDispatch` | `dispatchStatus=failed` 時に `reasonCode` 必須 | コマンド拒否 |
| `INV-PP-006` | `OrderProposal` | `trace` なしで統合イベントを発行しない | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `order.proposal.created` | `OrderProposal` | 注文候補保存後 | `identifier`, `symbol`, `side`, `qty`, `trace` | `identifier` |
| `proposal.dispatch.completed` | `ProposalDispatch` | 配信完了確定時 | `identifier`, `orderCount`, `orders`, `trace` | `identifier` |
| `proposal.dispatch.failed` | `ProposalDispatch` | 配信失敗確定時 | `identifier`, `reasonCode`, `trace` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `orders.proposed` | `risk-guard`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `orders.proposal.failed` | `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 注文候補生成 | `GenerateOrderProposals` | なし（イベント駆動） | `signal.generated`（受信） | 入力は `SignalGeneratedPayload` |
| 提案結果通知 | `PublishOrdersProposed` | なし | `orders.proposed`（発行） | 保存後に発行 |
| 提案失敗通知 | `PublishOrdersProposalFailed` | なし | `orders.proposal.failed`（発行） | fail-closed |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `OrderProposal` | `portfolio-planner` | `Firestore:orders` | `orders/{identifier}` 単位 | `trace`, `identifier`, `symbol`, `qty` |
| `ProposalDispatch` | `portfolio-planner` | `Firestore:idempotency_keys` | `identifier` 単位 | `trace`, `identifier`, `processedAt` |
| `PlanningAudit` | `portfolio-planner` | `Cloud Logging` | 別Tx（状態確定後） | `trace`, `identifier`, `result`, `reasonCode` |
| `PositionSnapshot` | `portfolio-planner` | `Firestore:positions`（参照） | 読み取り専用 | `trace`, `symbol`, `asOf` |
| `StrategySnapshot` | `portfolio-planner` | `Firestore:settings`（参照） | 読み取り専用 | `trace`, `settingsVersion` |

- 他集約更新は同一Txで行わない。
- 集約間整合は `orders.*` イベントで実現する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-PP-001` | acceptance | `RULE-PP-001` | 必須項目欠損で提案生成しない |
| `TST-PP-002` | acceptance | `RULE-PP-002` | `requiresComplianceReview=true` で fail-closed |
| `TST-PP-003` | invariant | `RULE-PP-003` | 同一identifier重複処理防止 |
| `TST-PP-004` | invariant | `RULE-PP-004` | `status=PROPOSED` と `qty>0` を保証 |
| `TST-PP-005` | domain event | `RULE-PP-005` | `orderCount` と件数一致 |
| `TST-PP-006` | domain event | `RULE-PP-006` | 保存後に `orders.proposed` 発行 |
| `TST-PP-007` | acceptance | `RULE-PP-007` | 依存失敗時に `orders.proposal.failed` 発行 |
| `TST-PP-008` | contract | `RULE-PP-008` | AsyncAPI payloadに `trace`,`identifier` を含む |
| `TST-PP-009` | contract | `RULE-PP-009` | OpenAPI/AsyncAPI/Domain Modelで `identifier` 命名統一 |

- 受け入れ: Gherkinの `Given/When/Then`
- ドメイン: 不変条件・状態遷移・イベント発行
- 契約: AsyncAPI schema検証 + サンプル検証

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

- `signal.generated` の必須項目欠損を fail-closed にできているか。
- `requiresComplianceReview` を見落として提案していないか。
- `orders` 保存と `orders.proposed` 発行順序が保証されるか。
- 同一イベント `identifier` の重複処理を防止できるか。
- Rule→Scenario→Model→Contract→Testのトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/portfolio-planner.md`
- `documents/内部設計/services/portfolio-planner.md`
- `documents/内部設計/json/portfolio-planner.json`
- `documents/外部設計/state/状態遷移設計.md`
- `documents/外部設計/api/asyncapi.yaml`
