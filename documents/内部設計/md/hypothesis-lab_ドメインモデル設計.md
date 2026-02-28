# hypothesis-lab ドメインモデル設計

最終更新日: 2026-02-28
対象Bounded Context: `hypothesis-lab`
ドキュメント版: `v0.2.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: 仮説の検証（backtest/demo）と昇格判定ルールを、状態遷移と不変条件として明確化する。
- スコープ内:
1. `hypothesis.proposed` 受信後の仮説登録と backtest 判定
2. `hypothesis.demo.completed` 受信後の demo 評価反映
3. 手動昇格、MNPI自己申告更新、却下のドメインルール
4. 昇格/却下イベントと失敗知見の記録
- スコープ外:
1. インサイト収集
2. 実注文執行
3. UI 表示ロジック

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Hypothesis Validation & Promotion`
- ミッション: 仮説の統計的妥当性とコンプライアンス適合性を判定し、`demo -> live` 遷移を安全に制御する。
- コア/支援/汎用サブドメイン区分: `core`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Hypothesis | 検証対象の投資仮説 | `hypothesis_registry` | `idea` と混在させない |
| Backtest | 過去データによる統計検証 | `backtest_runs` | 損益のみで合否判定しない |
| Demo Run | デモ運用期間の評価実行 | `demo_trade_runs` | 本番取引と混同しない |
| Promotion | `live` への昇格判断 | `hypothesis.promoted` | 無条件自動昇格は禁止 |
| MNPI Self Declaration | 未公表重要事実を知らない自己申告 | `mnpiSelfDeclared` | 省略不可（昇格時） |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `agent-orchestrator` | Upstream (`Customer-Supplier`) | `hypothesis.proposed` | 受信payloadを `Hypothesis` 集約へ正規化 |
| `execution` | Upstream (`Customer-Supplier`) | `hypothesis.demo.completed` | demo評価を `ValidationRun` へ正規化 |
| `bff` | Downstream (`OHS+PL`) | `POST/PUT /hypotheses/*` | Command を集約操作に変換 |
| `audit-log` | Downstream (`OHS+PL`) | `hypothesis.*` | `trace` を必須伝播 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-HL-001` | backtest合格前に `demo` へ遷移してはならない | must | inside |
| `RULE-HL-002` | `promotable=true` かつ `demoPeriodDays>=30` かつ `requiresComplianceReview=false` の場合のみ昇格候補となる | must | inside |
| `RULE-HL-003` | 自動昇格は `instrumentType=ETF` かつ `insiderRisk=low` かつ `mnpiSelfDeclared=true` かつ `partnerRestrictedSymbols` 非該当時のみ許可 | must | inside |
| `RULE-HL-004` | `instrumentType=STOCK` は手動昇格コマンド時のみ `live` へ遷移可能 | must | inside |
| `RULE-HL-005` | 失敗時は `failure_knowledge` へ Markdown 要約を保存する | must | outside |
| `RULE-HL-006` | 同一イベント `identifier` は冪等に1回のみ処理する | must | outside |
| `RULE-HL-007` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |
| `RULE-HL-008` | `PUT /hypotheses/{identifier}/mnpi-self-declaration` は `status=demo` のときのみ更新可 | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: hypothesis-lab validation and promotion
  Rule: ETF低リスク条件を満たす仮説は自動昇格できる
    Example: demo完了で自動昇格
      Given status が demo の Hypothesis が存在し instrumentType が ETF で insiderRisk が low
      And 最新 demo 評価で promotable が true
      And demoPeriodDays が 30 以上
      And requiresComplianceReview が false
      And mnpiSelfDeclared が true
      And symbol が partnerRestrictedSymbols に含まれない
      When hypothesis.demo.completed を受信する
      Then Hypothesis は live に遷移する
      And hypothesis.promoted が発行される
```

```gherkin
Feature: hypothesis-lab validation and promotion
  Rule: 個別株は手動昇格のみ許可
    Example: 手動昇格でのみ live 遷移
      Given status が demo の Hypothesis が存在し instrumentType が STOCK
      And 最新 demo 評価で promotable が true
      And demoPeriodDays が 30 以上
      And requiresComplianceReview が false
      And mnpiSelfDeclared が true
      When 運用者が POST /hypotheses/{identifier}/promote を実行する
      Then Hypothesis は live に遷移する
      And hypothesis.promoted が発行される
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-HL-001` | `SCN-HL-001` | `Hypothesis` | `hypothesis.proposed` | `TST-HL-001` |
| `RULE-HL-002` | `SCN-HL-002` | `Hypothesis` | `hypothesis.demo.completed` | `TST-HL-002` |
| `RULE-HL-003` | `SCN-HL-003` | `Hypothesis` | `hypothesis.demo.completed` | `TST-HL-003` |
| `RULE-HL-004` | `SCN-HL-004` | `Hypothesis` | `POST /hypotheses/{identifier}/promote` | `TST-HL-004` |
| `RULE-HL-005` | `SCN-HL-006` | `FailureSummary` | `failure_knowledge` | `TST-HL-008` |
| `RULE-HL-006` | `SCN-HL-007` | `Hypothesis` | `hypothesis.proposed`, `hypothesis.demo.completed` | `TST-HL-009` |
| `RULE-HL-007` | `SCN-HL-008` | `Hypothesis` | OpenAPI/AsyncAPI/Domain Model | `TST-HL-006` |
| `RULE-HL-008` | `SCN-HL-005` | `Hypothesis` | `PUT /hypotheses/{identifier}/mnpi-self-declaration` | `TST-HL-005` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `Hypothesis` | `Hypothesis` | 仮説状態と昇格可否判定を管理 | `hypothesis_registry/{identifier}` | `live` 遷移条件厳守 |
| `ValidationRun` | `ValidationRun` | backtest/demo結果を記録 | `backtest_runs/{identifier}` or `demo_trade_runs/{identifier}` | run種別ごとの必須指標 |

#### Aggregate詳細: `Hypothesis`

- root: `Hypothesis`
- 参照先集約: `ValidationRun`（`identifier`参照のみ）
- 生成コマンド: `AcceptProposedHypothesis`
- 更新コマンド: `RecordBacktestResult`, `CompleteDemoRun`, `UpdateMnpiSelfDeclaration`
- 判定コマンド: `PromoteHypothesis`, `RejectHypothesis`
- 不変条件:
1. `live` 遷移は `status=demo` かつ `promotable=true` かつ `demoPeriodDays>=30` かつ `requiresComplianceReview=false` のときのみ可能。
2. 自動昇格は `instrumentType=ETF` かつ `insiderRisk=low` かつ `mnpiSelfDeclared=true` かつ `partnerRestrictedSymbols` 非該当時のみ可能。
3. `instrumentType=STOCK` は手動 `PromoteHypothesis` のときのみ `live` へ遷移可能。
4. `identifier` は不変。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 仮説識別子 | `1` |
| `symbol` | `string` | 対象銘柄 | `1` |
| `instrumentType` | `enum(ETF, STOCK)` | 金融商品種別 | `1` |
| `status` | `enum(draft, backtested, demo, live, rejected)` | 仮説ライフサイクル状態 | `1` |
| `title` | `string` | 仮説タイトル | `0..1` |
| `insiderRisk` | `enum(low, medium, high)` | インサイダー接触リスク | `0..1` |
| `requiresComplianceReview` | `boolean` | コンプライアンス追加審査要否 | `0..1` |
| `mnpiSelfDeclared` | `boolean` | MNPI未保有自己申告 | `0..1` |
| `autoPromotionEligible` | `boolean` | 自動昇格候補かどうか | `0..1` |
| `promotionMode` | `enum(manual, auto)` | 昇格モード | `0..1` |
| `sourceEvidence` | `array<string>` | 根拠インサイト識別子群 | `0..n` |
| `instructionProfileVersion` | `string` | 指示プロファイル版 | `0..1` |
| `latestFailureSummary` | `string` | 直近失敗要約 | `0..1` |
| `updatedAt` | `datetime` | 最終更新時刻 | `1` |
| `updatedBy` | `string` | 最終更新主体 | `0..1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `validationRuns` | `array<ValidationRunRef>` | 検証実行結果への参照 | `0..n` |
| `performanceMetrics` | `PerformanceMetrics` | 現在評価に使う成績指標 | `0..1` |
| `demoWindow` | `DemoWindow` | 現在/直近demo期間情報 | `0..1` |
| `complianceSnapshot` | `ComplianceSnapshot` | 昇格判定時のコンプライアンス状態 | `0..1` |

#### Aggregate詳細: `ValidationRun`

- root: `ValidationRun`
- run種別: `backtest` / `demo`
- 不変条件:
1. `runType=backtest` では `costAdjustedReturn`, `dsr`, `pbo` が必須。
2. `runType=demo` では `startedAt`, `endedAt`, `demoPeriodDays`, `promotable` が必須。

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `Hypothesis` | `identifier` | `draft -> backtested -> demo -> live/rejected` | `applyBacktestResult`, `applyDemoResult`, `promote`, `reject` |
| `ValidationRun` | `identifier` | `created -> recorded` | `recordBacktestMetrics`, `recordDemoMetrics` |

#### Entity詳細: `Hypothesis`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 仮説識別子 | `1` |
| `status` | `enum(draft, backtested, demo, live, rejected)` | 状態 | `1` |
| `instrumentType` | `enum(ETF, STOCK)` | 商品種別 | `1` |
| `mnpiSelfDeclared` | `boolean` | MNPI自己申告 | `0..1` |
| `promotionMode` | `enum(manual, auto)` | 最終判断モード | `0..1` |

#### Entity詳細: `ValidationRun`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 検証実行識別子 | `1` |
| `hypothesis` | `string` | 対象仮説の識別子 | `1` |
| `runType` | `enum(backtest, demo)` | 実行種別 | `1` |
| `executedAt` | `datetime` | 実行時刻 | `1` |
| `metrics` | `PerformanceMetrics` | 成績指標 | `0..1` |
| `demoWindow` | `DemoWindow` | demo期間 | `0..1` |
| `promotable` | `boolean` | 昇格判定可否 | `0..1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `PerformanceMetrics` | `costAdjustedReturn`, `dsr`, `pbo` | 値比較 | immutable |
| `DemoWindow` | `startedAt`, `endedAt`, `demoPeriodDays` | 値比較 | immutable |
| `ComplianceSnapshot` | `requiresComplianceReview`, `insiderRisk`, `mnpiSelfDeclared` | 値比較 | immutable |
| `PromotionDecision` | `decision`, `reasonCode`, `promotionMode` | 値比較 | immutable |
| `FailureSummary` | `reasonCode`, `markdownSummary` | 値比較 | immutable |

#### Value Object詳細: `PerformanceMetrics`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `costAdjustedReturn` | `number` | コスト控除後リターン | `1` |
| `dsr` | `number` | Deflated Sharpe Ratio | `1` |
| `pbo` | `number` | Probability of Backtest Overfitting | `1` |

#### Value Object詳細: `DemoWindow`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `startedAt` | `datetime` | demo開始日時 | `1` |
| `endedAt` | `datetime` | demo終了日時 | `1` |
| `demoPeriodDays` | `integer` | demo期間日数 | `1` |

#### Value Object詳細: `ComplianceSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `requiresComplianceReview` | `boolean` | 追加審査要否 | `1` |
| `insiderRisk` | `enum(low, medium, high)` | リスク評価 | `1` |
| `mnpiSelfDeclared` | `boolean` | MNPI自己申告状態 | `1` |

#### Value Object詳細: `PromotionDecision`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `decision` | `enum(promoted, rejected)` | 判定結果 | `1` |
| `reasonCode` | `enum(OperatorActionReasonCode)` | 判断理由コード | `1` |
| `promotionMode` | `enum(manual, auto)` | 判定経路 | `1` |

#### Value Object詳細: `FailureSummary`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `reasonCode` | `enum(ReasonCode)` | 失敗理由コード | `1` |
| `markdownSummary` | `string` | Markdown形式の要約 | `1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `PromotionEligibilityPolicy` | domain | 昇格可否判定（自動/手動/ブロック） | IO処理 |
| `FailureKnowledgeRegistrar` | application | 失敗知見の整形と永続化 | 判定ルール本体 |
| `HypothesisWorkflowService` | application | イベント受信・APIコマンドのオーケストレーション | 不変条件の実装 |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `HypothesisRepository` | `Hypothesis` 永続化 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `ValidationRunRepository` | 検証結果永続化 | `Find`, `FindByRunType`, `Search`, `Persist`, `Terminate` |
| Repository | `FailureKnowledgeRepository` | 失敗知見保存 | `Find`, `FindByReasonCode`, `Search`, `Persist`, `Terminate` |
| Factory | `HypothesisFactory` | 提案イベントから仮説生成 | `fromProposedEvent` |
| Specification | `PromotionReadySpecification` | 昇格条件判定 | `isSatisfiedBy(hypothesis)` |

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
| なし | `AcceptProposedHypothesis` | `draft` | 必須フィールドあり | `REQUEST_VALIDATION_FAILED` |
| `draft` | `RecordBacktestResult(pass=true)` | `backtested` | backtest必須指標あり | `REQUEST_VALIDATION_FAILED` |
| `draft` | `RecordBacktestResult(pass=false)` | `rejected` | backtest必須指標あり | `REQUEST_VALIDATION_FAILED` |
| `backtested` | `StartDemoRun` | `demo` | demo開始条件を満たす | `STATE_CONFLICT` |
| `demo` | `UpdateMnpiSelfDeclaration` | `demo` | `mnpiSelfDeclared` を更新可能（`status=demo`） | `OPERATION_NOT_ALLOWED` |
| `demo` | `CompleteDemoRun(promotable=true)` | `live` | 自動昇格条件（RULE-HL-003）を満たす | - |
| `demo` | `CompleteDemoRun(promotable=true)` | `demo` | 自動昇格条件未達（手動昇格待ち） | - |
| `demo` | `CompleteDemoRun(promotable=false)` | `rejected` | なし | `REQUEST_VALIDATION_FAILED` |
| `demo` | `PromoteHypothesis` | `live` | 手動昇格条件を満たす（STOCK含む） | `COMPLIANCE_REVIEW_REQUIRED` / `OPERATION_NOT_ALLOWED` |
| `demo` | `RejectHypothesis` | `rejected` | 理由コードあり | `REQUEST_VALIDATION_FAILED` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-HL-001` | `Hypothesis` | `identifier` は生成後不変 | コマンド拒否 |
| `INV-HL-002` | `Hypothesis` | `live` 遷移には昇格条件充足が必要 | コマンド拒否 |
| `INV-HL-003` | `Hypothesis` | 自動昇格は ETF低リスク + MNPI自己申告 + 非ブロック銘柄が必須 | コマンド拒否 |
| `INV-HL-004` | `ValidationRun` | run種別ごとの必須フィールド欠損禁止 | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `hypothesis.backtested` | `Hypothesis` | backtest結果確定時 | `identifier`, `passed`, `costAdjustedReturn`, `dsr`, `pbo` | `identifier` |
| `hypothesis.promoted` | `Hypothesis` | `live` 遷移確定時 | `identifier`, `decision`, `reasonCode`, `promotionMode`, `mnpiSelfDeclared`, `insiderRisk` | `identifier` |
| `hypothesis.rejected` | `Hypothesis` | `rejected` 遷移確定時 | `identifier`, `decision`, `reasonCode`, `promotionMode`, `mnpiSelfDeclared`, `insiderRisk` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `hypothesis.backtested` | `bff`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `hypothesis.promoted` | `bff` | AsyncAPI | eventual consistency | max3 + DLQ |
| `hypothesis.rejected` | `bff`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 仮説登録 | `AcceptProposedHypothesis` | なし | `hypothesis.proposed`（受信） | agent-orchestrator起点 |
| デモ完了判定 | `CompleteDemoRun` | なし | `hypothesis.demo.completed`（受信） | 条件一致時は自動昇格 |
| MNPI自己申告更新 | `UpdateMnpiSelfDeclaration` | `PUT /hypotheses/{identifier}/mnpi-self-declaration` | なし | `status=demo` のみ |
| 仮説昇格（手動） | `PromoteHypothesis` | `POST /hypotheses/{identifier}/promote` | `hypothesis.promoted`（発行） | STOCKは手動必須 |
| 仮説却下 | `RejectHypothesis` | `POST /hypotheses/{identifier}/reject` | `hypothesis.rejected`（発行） | 理由コード必須 |
| 仮説詳細参照 | `GetHypothesisByIdentifier` | `GET /hypotheses/{identifier}` | なし | BFF経由 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `Hypothesis` | `hypothesis-lab` | `hypothesis_registry` | 単一集約 | `trace`, `identifier`, `user` |
| `ValidationRun(backtest)` | `hypothesis-lab` | `backtest_runs` | 単一集約 | `trace`, `identifier` |
| `ValidationRun(demo)` | `hypothesis-lab` | `demo_trade_runs` | 単一集約 | `trace`, `identifier` |
| `FailureSummary` | `hypothesis-lab` | `failure_knowledge` | 別Tx（結果確定後） | `trace`, `identifier`, `reasonCode` |

- 他集約更新は同一Txで行わない。
- 集約間整合は `hypothesis.*` イベントで実現する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-HL-001` | acceptance | `RULE-HL-001` | backtest合格前に `demo` へ遷移しない |
| `TST-HL-002` | acceptance | `RULE-HL-002` | demo完了で昇格候補条件を評価する |
| `TST-HL-003` | acceptance | `RULE-HL-003` | ETF低リスク条件未達時は自動昇格しない |
| `TST-HL-004` | acceptance | `RULE-HL-004` | STOCKは手動昇格時のみ `live` 遷移 |
| `TST-HL-005` | acceptance | `RULE-HL-008` | `status!=demo` でMNPI自己申告更新不可 |
| `TST-HL-006` | invariant | `RULE-HL-007` | `identifier` 命名と不変条件を検証 |
| `TST-HL-007` | contract | `RULE-HL-003` | OpenAPI/AsyncAPI payload整合 |
| `TST-HL-008` | acceptance | `RULE-HL-005` | 失敗時に `failure_knowledge` へMarkdown要約保存 |
| `TST-HL-009` | idempotency | `RULE-HL-006` | 同一identifierイベント重複で副作用なし |

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

- Bounded Context境界は明確か。
- 用語がコード/API/ドキュメントで一致しているか。
- 不変条件がAggregate Rootで担保されているか。
- Application Serviceに業務ルールが漏れていないか。
- 集約間更新が単一トランザクションに混入していないか。
- Rule→Scenario→Model→Contract→Test のトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/hypothesis-lab.md`
- `documents/外部設計/security/条件付き自動昇格設計.md`
- `documents/外部設計/api/openapi.yaml`
- `documents/外部設計/api/asyncapi.yaml`
- `documents/外部設計/state/状態遷移設計.md`
- `documents/外部設計/db/firestore設計.md`
