# execution ドメインモデル設計

最終更新日: 2026-03-03
対象Bounded Context: `execution`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: 承認済み注文を安全かつ冪等に執行し、執行結果を監査可能な形で確定する。
- スコープ内:
1. `orders.approved` 受信後の執行判定・発注・結果確定
2. リトライ制御（最大3回、指数バックオフ）
3. `orders.executed` / `orders.execution.failed` 発行
4. デモ運用完了時の `hypothesis.demo.completed` 発行
- スコープ外:
1. 注文承認/却下判定（`risk-guard`）
2. 注文候補生成（`portfolio-planner`）
3. 仮説昇格判定（`hypothesis-lab`）

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Order Execution`
- ミッション: `APPROVED` 注文をブローカーへ送信し、`EXECUTED` または `FAILED` に遷移させる。
- コア/支援/汎用サブドメイン区分: `core`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Approved Order | リスク審査で承認済みの注文 | `orders.approved` | `PROPOSED` と混同しない |
| Execution Attempt | ブローカーへ送信する1回の試行 | `execution` 内部 | 無限リトライ禁止 |
| Broker Order | ブローカー側の注文識別子 | `order_executions.brokerOrder` | 内部 `identifier` と混同しない |
| Execution Result | 執行成功/失敗の確定結果 | `orders.executed/failed` | 未確定状態で公開しない |
| Demo Run Completion | デモ運用の評価完了通知 | `hypothesis.demo.completed` | 昇格判定そのものではない |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |
| Trace | 追跡識別子 | 監査ログ・イベント | 欠損状態で発行しない |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `risk-guard` | Upstream (`Customer-Supplier`) | `orders.approved` | 対象 `identifier` を執行対象へ正規化 |
| `bff` | Upstream (`Customer-Supplier`) | `POST /orders/{identifier}/retry`（再送で `orders.proposed`） | `FAILED` 再送時は新しい承認イベント待ち |
| `audit-log` | Downstream (`OHS+PL`) | `orders.executed`, `orders.execution.failed`, `hypothesis.demo.completed` | `trace`, `identifier`, `reasonCode` を必須伝播 |
| `hypothesis-lab` | Downstream (`OHS+PL`) | `hypothesis.demo.completed` | デモ完了情報を検証結果入力へ変換 |
| `broker` | External System | Broker Order API | 外部エラーを標準 `ReasonCode` へ変換 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-EX-001` | `status=APPROVED` の注文のみ執行できる | must | inside |
| `RULE-EX-002` | 同一注文 `identifier`（payload.identifier）の外部発注は1回のみ許可する | must | outside |
| `RULE-EX-003` | リトライ可能エラーは最大3回まで再試行する | must | inside |
| `RULE-EX-004` | 非再試行エラーは即時 `FAILED` で確定する | must | inside |
| `RULE-EX-005` | 成功時は `brokerOrder`, `executedAt` 保存後に `orders.executed` を発行する | must | inside |
| `RULE-EX-006` | 失敗時は `reasonCode` 保存後に `orders.execution.failed` を発行する | must | inside |
| `RULE-EX-007` | デモ期間完了通知は同一イベント `identifier`（event envelope）で重複発行しない | must | outside |
| `RULE-EX-008` | すべての結果イベントに `trace` と `identifier` を含める | must | outside |
| `RULE-EX-009` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: execution dispatch
  Rule: APPROVED注文のみ執行する
    Example: 承認済み注文が成功執行される
      Given status が APPROVED の注文が存在する
      And 同一注文identifierの処理履歴がない
      When orders.approved を受信する
      Then 注文は EXECUTED になる
      And orders.executed が発行される
```

```gherkin
Feature: execution dispatch
  Rule: 非再試行エラーは即時失敗にする
    Example: market closed で失敗
      Given status が APPROVED の注文が存在する
      And ブローカー応答が EXECUTION_MARKET_CLOSED である
      When orders.approved を受信する
      Then 注文は FAILED になる
      And reasonCode は EXECUTION_MARKET_CLOSED になる
      And orders.execution.failed が発行される
```

```gherkin
Feature: execution dispatch
  Rule: リトライ可能エラーは最大3回まで再試行する
    Example: timeout が継続して上限到達
      Given status が APPROVED の注文が存在する
      And ブローカー応答が timeout を返し続ける
      When orders.approved を受信する
      Then 再試行は3回で停止する
      And 注文は FAILED になる
      And reasonCode は EXECUTION_BROKER_TIMEOUT になる
```

```gherkin
Feature: demo completion publish
  Rule: デモ期間完了時に1回だけ通知する
    Example: デモ完了通知
      Given デモ運用が完了条件を満たしている
      And 同一イベントidentifierで完了通知履歴がない
      When デモ評価ジョブが完了する
      Then hypothesis.demo.completed が1回発行される
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-EX-001` | `SCN-EX-001` | `OrderExecution` | `orders.approved` | `TST-EX-001` |
| `RULE-EX-002` | `SCN-EX-002` | `OrderExecution` | `orders.approved` | `TST-EX-002` |
| `RULE-EX-003` | `SCN-EX-003` | `OrderExecution` | `orders.approved` | `TST-EX-003` |
| `RULE-EX-004` | `SCN-EX-004` | `OrderExecution` | `orders.approved` | `TST-EX-004` |
| `RULE-EX-005` | `SCN-EX-005` | `OrderExecution` | `orders.executed` | `TST-EX-005` |
| `RULE-EX-006` | `SCN-EX-006` | `OrderExecution` | `orders.execution.failed` | `TST-EX-006` |
| `RULE-EX-007` | `SCN-EX-007` | `DemoRunEvaluation` | `hypothesis.demo.completed` | `TST-EX-007` |
| `RULE-EX-008` | `SCN-EX-008` | `OrderExecution` | `orders.executed/failed` | `TST-EX-008` |
| `RULE-EX-009` | `SCN-EX-009` | `OrderExecution` | OpenAPI/AsyncAPI/Domain Model | `TST-EX-009` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `OrderExecution` | `OrderExecution` | 1注文の執行結果を確定する | `order_executions/{identifier}` | 重複外部発注禁止、結果確定後は再確定禁止 |
| `DemoRunEvaluation` | `DemoRunEvaluation` | デモ完了通知の発行状態を確定する | `idempotency_keys/{identifier}` | 完了通知の重複発行禁止 |

#### Aggregate詳細: `OrderExecution`

- root: `OrderExecution`
- 参照先集約: なし（`orders.approved` の入力スナップショットで完結）
- 生成コマンド: `AcceptApprovedOrder`
- 更新コマンド: `DispatchToBroker`, `RecordBrokerFailure`, `RecordBrokerSuccess`
- 削除/無効化コマンド: `TerminateExecution`
- 不変条件:
1. `status=APPROVED` 以外では `DispatchToBroker` を受け付けない。
2. `status=EXECUTED` または `status=FAILED` 確定後は再度執行しない。
3. `status=FAILED` のとき `reasonCode` は必須。
4. `identifier` は不変。

#### 4.1.1 Aggregate Rootフィールド定義: `OrderExecution`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 注文識別子（`order_executions/{identifier}`） | `1` |
| `status` | `enum(APPROVED, EXECUTED, FAILED)` | execution文脈で扱う状態 | `1` |
| `request` | `ExecutionRequest` | 発注要求スナップショット | `1` |
| `attemptCount` | `integer` | 執行試行回数 | `1` |
| `maxAttempts` | `integer` | 再試行上限（既定3） | `1` |
| `brokerOrder` | `string` | ブローカー注文識別子（成功時） | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由（失敗時必須） | `0..1` |
| `trace` | `string` | 追跡識別子 | `1` |
| `lastAttemptAt` | `datetime` | 最終試行時刻 | `0..1` |
| `executedAt` | `datetime` | 執行成功時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）: `OrderExecution`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `attempts` | `List<ExecutionAttempt>` | 試行履歴 | `1..n` |
| `retryPolicy` | `RetryPolicySnapshot` | リトライ判定条件 | `1` |
| `failureDetail` | `FailureDetail` | 最終失敗情報 | `0..1` |

#### Aggregate詳細: `DemoRunEvaluation`

- root: `DemoRunEvaluation`
- 参照先集約: `Hypothesis`（`identifier` 参照のみ）
- 生成コマンド: `StartDemoRun`
- 更新コマンド: `CompleteDemoRun`
- 削除/無効化コマンド: `TerminateDemoRunEvaluation`
- 不変条件:
1. 完了状態へは1回のみ遷移できる。
2. `published=true` のとき同一 `identifier` で再発行しない。
3. `identifier` は不変。

#### 4.1.3 Aggregate Rootフィールド定義: `DemoRunEvaluation`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 仮説識別子 | `1` |
| `demoRun` | `string` | デモ実行識別子 | `1` |
| `status` | `enum(active, completed)` | デモ評価状態 | `1` |
| `startedAt` | `datetime` | デモ開始時刻 | `1` |
| `endedAt` | `datetime` | デモ終了時刻（完了時） | `0..1` |
| `published` | `boolean` | 完了通知発行済みフラグ | `1` |
| `trace` | `string` | 追跡識別子 | `1` |

#### 4.1.4 集約内要素の保持（Entity/Value Object）: `DemoRunEvaluation`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `performance` | `DemoPerformance` | デモ評価指標 | `0..1` |
| `promotionGate` | `PromotionGate` | 昇格可否入力情報 | `0..1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `OrderExecution` | `identifier` | `APPROVED -> EXECUTED/FAILED` | `dispatch`, `recordSuccess`, `recordFailure` |
| `ExecutionAttempt` | `identifier` | `created -> succeeded/failed` | `markAttempted`, `markRetryable`, `markFinal` |
| `DemoRunEvaluation` | `identifier` | `active -> completed` | `complete`, `markPublished` |

#### Entity詳細: `OrderExecution`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 注文識別子 | `1` |
| `status` | `enum(APPROVED, EXECUTED, FAILED)` | 執行状態 | `1` |
| `attemptCount` | `integer` | 試行回数 | `1` |
| `brokerOrder` | `string` | ブローカー注文識別子 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース情報 | `1` |

#### Entity詳細: `ExecutionAttempt`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 対象注文識別子 | `1` |
| `attempt` | `integer` | 試行番号 | `1` |
| `attemptedAt` | `datetime` | 試行時刻 | `1` |
| `result` | `enum(success, retryable_failure, final_failure)` | 試行結果 | `1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |

#### Entity詳細: `DemoRunEvaluation`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 仮説識別子 | `1` |
| `demoRun` | `string` | デモ実行識別子 | `1` |
| `status` | `enum(active, completed)` | デモ評価状態 | `1` |
| `published` | `boolean` | 完了通知発行済み | `1` |
| `trace` | `string` | トレース情報 | `1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `ExecutionRequest` | `symbol`, `side`, `qty` | 値比較 | immutable |
| `RetryPolicySnapshot` | `maxAttempts`, `backoff` | 値比較 | immutable |
| `FailureDetail` | `reasonCode`, `detail`, `retryable` | 値比較 | immutable |
| `DemoPerformance` | `costAdjustedReturn`, `dsr`, `pbo`, `demoPeriodDays` | 値比較 | immutable |
| `PromotionGate` | `instrumentType`, `insiderRisk`, `mnpiSelfDeclared`, `requiresComplianceReview`, `promotable` | 値比較 | immutable |

#### Value Object詳細: `ExecutionRequest`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `symbol` | `string` | 銘柄コード | `1` |
| `side` | `enum(BUY, SELL)` | 売買区分 | `1` |
| `qty` | `number` | 注文数量 | `1` |

#### Value Object詳細: `RetryPolicySnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `maxAttempts` | `integer` | 最大試行回数 | `1` |
| `backoff` | `string` | バックオフ種別（`exponential`） | `1` |

#### Value Object詳細: `FailureDetail`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `reasonCode` | `enum(ReasonCode)` | 失敗理由コード | `1` |
| `detail` | `string` | 補足エラー内容 | `0..1` |
| `retryable` | `boolean` | 再試行可否 | `1` |

#### Value Object詳細: `DemoPerformance`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `costAdjustedReturn` | `number` | コスト控除後リターン | `0..1` |
| `dsr` | `number` | Deflated Sharpe Ratio | `0..1` |
| `pbo` | `number` | Probability of Backtest Overfitting | `0..1` |
| `demoPeriodDays` | `integer` | デモ継続日数 | `1` |

#### Value Object詳細: `PromotionGate`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `instrumentType` | `enum(ETF, STOCK)` | 金融商品種別 | `1` |
| `insiderRisk` | `enum(low, medium, high)` | インサイダーリスク区分 | `1` |
| `mnpiSelfDeclared` | `boolean` | MNPI非保有自己申告 | `1` |
| `requiresComplianceReview` | `boolean` | コンプラレビュー要否 | `1` |
| `promotable` | `boolean` | 昇格候補可否 | `1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `BrokerExecutionPolicy` | domain | ブローカー応答を `ReasonCode` と再試行可否へ変換 | Firestoreアクセス |
| `ExecutionIdempotencyPolicy` | domain | 重複発注判定 | 外部API呼び出し |
| `OrderExecutionService` | application | 受信イベントを執行処理へオーケストレーション | 業務ルール本体 |
| `DemoCompletionService` | application | デモ完了イベント組み立てと発行 | 昇格判定ロジック本体 |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `OrderExecutionRepository` | 注文執行状態永続化 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `IdempotencyKeyRepository` | 重複処理防止 | `Find`, `Persist`, `Terminate` |
| Repository | `DemoRunEvaluationRepository` | デモ完了通知状態（重複防止キー）永続化 | `Find`, `Persist`, `Terminate` |
| Factory | `OrderExecutionFactory` | 承認イベントから執行集約生成 | `fromApprovedOrder` |
| Factory | `DemoRunEvaluationFactory` | デモ実行結果から完了集約生成 | `fromDemoRunRecord` |
| Specification | `ApprovedStatusSpecification` | `APPROVED` 状態確認 | `isSatisfiedBy(order)` |
| Specification | `RetryableFailureSpecification` | 再試行可否判定 | `isSatisfiedBy(failure)` |
| Specification | `DemoRunCompletedSpecification` | デモ完了条件判定 | `isSatisfiedBy(run)` |

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
| `APPROVED` | `DispatchToBroker` | `EXECUTED` | ブローカー発注成功 | - |
| `APPROVED` | `DispatchToBroker` | `APPROVED` | リトライ可能エラーかつ `attemptCount < 3` | `EXECUTION_BROKER_TIMEOUT` |
| `APPROVED` | `DispatchToBroker` | `FAILED` | リトライ上限到達 | `EXECUTION_BROKER_TIMEOUT` |
| `APPROVED` | `DispatchToBroker` | `FAILED` | 非再試行エラー（例: `EXECUTION_MARKET_CLOSED`） | `EXECUTION_MARKET_CLOSED` |
| `APPROVED` | `DispatchToBroker` | `FAILED` | 非再試行エラー（例: `EXECUTION_INSUFFICIENT_FUNDS`） | `EXECUTION_INSUFFICIENT_FUNDS` |
| `APPROVED` | `DispatchToBroker` | `FAILED` | 非再試行エラー（例: `EXECUTION_BROKER_REJECTED`） | `EXECUTION_BROKER_REJECTED` |
| `EXECUTED` | `DispatchToBroker` | `EXECUTED` | 同一イベントidentifier重複受信 | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `FAILED` | `DispatchToBroker` | `FAILED` | 終端状態への再実行 | `STATE_CONFLICT` |
| `active` | `CompleteDemoRun` | `completed` | 完了条件を満たし未発行 | - |
| `completed` | `CompleteDemoRun` | `completed` | 同一イベントidentifier重複実行 | `IDEMPOTENCY_DUPLICATE_EVENT` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-EX-001` | `OrderExecution` | `status=APPROVED` のときのみ外部発注可 | コマンド拒否 |
| `INV-EX-002` | `OrderExecution` | `status=FAILED` のとき `reasonCode` 必須 | コマンド拒否 |
| `INV-EX-003` | `OrderExecution` | 外部発注は `identifier` 単位で一度だけ | 冪等扱い |
| `INV-EX-004` | `DemoRunEvaluation` | 完了通知は `identifier` 単位で一度だけ | 冪等扱い |
| `INV-EX-005` | `OrderExecution` | `trace` なしで結果イベントを発行しない | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `order.execution.attempted` | `OrderExecution` | ブローカー送信直後 | `identifier, attempt, trace` | `identifier` |
| `order.execution.succeeded` | `OrderExecution` | 成功確定後 | `identifier, brokerOrder, executedAt, trace` | `identifier` |
| `order.execution.failed` | `OrderExecution` | 失敗確定後 | `identifier, reasonCode, attempt, trace` | `identifier` |
| `demo.run.completed` | `DemoRunEvaluation` | デモ完了確定後 | `identifier, demoRun, metrics, trace` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `orders.executed` | `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `orders.execution.failed` | `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `hypothesis.demo.completed` | `hypothesis-lab`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 承認済み注文の執行 | `DispatchToBroker` | なし（イベント駆動） | `orders.approved`（受信） | `APPROVED` のみ |
| 執行成功通知 | `RecordBrokerSuccess` | なし | `orders.executed`（発行） | 保存後に発行 |
| 執行失敗通知 | `RecordBrokerFailure` | なし | `orders.execution.failed`（発行） | 保存後に発行 |
| デモ完了通知 | `CompleteDemoRun` | なし | `hypothesis.demo.completed`（発行） | 同一identifierで1回 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `OrderExecution` | `execution` | `Firestore:order_executions` | `order_executions/{identifier}` 単位 | `trace, identifier, brokerOrder, reasonCode` |
| `ExecutionIdempotency` | `execution` | `Firestore:idempotency_keys` | `identifier` 単位 | `trace, identifier, processedAt` |
| `DemoRunSourceSnapshot` | `hypothesis-lab` | `Firestore:demo_trade_runs`（参照） | 読み取り専用 | `identifier, demoRun, endedAt` |
| `DemoRunEvaluation` | `execution` | `Firestore:idempotency_keys` | `identifier` 単位 | `trace, identifier, processedAt` |
| `ExecutionAudit` | `execution` | `Cloud Logging` | 別Tx（状態確定後） | `trace, identifier, result` |

- 他集約更新は同一Txで行わない
- 集約間整合はイベントで実現する

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-EX-001` | acceptance | `RULE-EX-001` | `status!=APPROVED` の執行拒否 |
| `TST-EX-002` | invariant | `RULE-EX-002` | 同一identifierの重複発注防止 |
| `TST-EX-003` | acceptance | `RULE-EX-003` | timeout時の最大3回リトライ |
| `TST-EX-004` | acceptance | `RULE-EX-004` | 非再試行エラー即時FAILED |
| `TST-EX-005` | domain event | `RULE-EX-005` | `orders.executed` が保存後に発行 |
| `TST-EX-006` | domain event | `RULE-EX-006` | `orders.execution.failed` が保存後に発行 |
| `TST-EX-007` | acceptance | `RULE-EX-007` | `hypothesis.demo.completed` 重複発行なし |
| `TST-EX-008` | contract | `RULE-EX-008` | AsyncAPI payloadに `trace`,`identifier` を含む |
| `TST-EX-009` | contract | `RULE-EX-009` | OpenAPI/AsyncAPI/Domain Modelで `identifier` 命名統一 |

- 受け入れ: Gherkinの `Given/When/Then`
- ドメイン: 不変条件・状態遷移・イベント発行
- 契約: AsyncAPI schema検証 + サンプル検証

## 10. 実装規約（このプロジェクト向け）

- ドメイン設計（Aggregate/Entity/Value Object/Domain Event）にも `Identifier` 命名規約を適用する
- `Id` は使わず `identifier` を使う
- 当該関心ごとの識別子は `identifier`
- 他関心ごとの識別子は `{entity}`（例: `user`）
- 集約外参照はID参照のみ（オブジェクト参照禁止）
- 識別子生成は `ULID` を使用する
- `UUIDv4` はトークン等、推測耐性のために高いランダム性が必要な用途でのみ利用する
- イベントエンベロープ `identifier` は `ULID` を使用する

## 11. レビュー観点

- `APPROVED` 以外の執行が混入していないか
- リトライ可能/非可能の分類と `ReasonCode` が一致しているか
- `order_executions` 更新とイベント発行の順序が保証されるか
- `hypothesis.demo.completed` の重複発行を防止できるか
- Rule→Scenario→Model→Contract→Testのトレースが切れていないか

## 12. 参照（調査ソース）

- `documents/外部設計/services/execution.md`
- `documents/内部設計/services/execution.md`
- `documents/外部設計/state/状態遷移設計.md`
- `documents/外部設計/api/asyncapi.yaml`
