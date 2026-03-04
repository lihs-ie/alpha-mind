# agent-orchestrator ドメインモデル設計

最終更新日: 2026-03-03
対象Bounded Context: `agent-orchestrator`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: Skill/指示書/失敗知見を用いて仮説を生成し、`hypothesis.proposed` と `hypothesis.proposal.failed` を整合的に発行する。
- スコープ内:
1. `insight.collected` / `hypothesis.retest.requested` 受信時の入力検証
2. `skill_registry`, `instruction_profiles`, `code_reference_templates` の解決
3. `failure_knowledge` 類似照合による重複仮説抑止
4. `hypothesis_registry` 保存と発行イベントの確定
5. `idempotency_keys` による重複副作用防止
- スコープ外:
1. インサイト収集処理そのもの（`insight-collector`）
2. 仮説のバックテスト/昇格判定（`hypothesis-lab`）
3. 画面操作API（`bff`）

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Hypothesis Orchestration`
- ミッション: 収集済みインサイトを再現可能な仮説候補へ変換し、重複を抑止したうえで検証文脈へ引き渡す。
- コア/支援/汎用サブドメイン区分: `core`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Proposal Generation | 仮説生成処理1回分 | `hypothesis_registry` | 保存前に成功イベントを発行しない |
| Generation Context | Skill/指示書/テンプレートの解決結果 | `skill_registry`, `instruction_profiles`, `code_reference_templates` | 未解決状態で生成しない |
| Duplicate Suppression | 類似失敗知見に基づく仮説抑止 | `failure_knowledge` | 人手裁量のみで判定しない |
| Proposal Artifact | 生成結果レポート | `Cloud Storage:hypothesis_reports` | 発行イベントと切り離さない |
| Orchestration Dispatch | 入力イベント単位の冪等処理 | `idempotency_keys` | 同一イベントの重複副作用を許可しない |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `insight-collector` | Upstream (`Customer-Supplier`) | `insight.collected` | payload を `SourceEventSnapshot` と `HypothesisProposal` 生成入力に正規化 |
| `bff` | Upstream (`Customer-Supplier`) | `hypothesis.retest.requested` | 再検証要求を既存仮説参照付き生成要求へ変換 |
| `hypothesis-lab` | Downstream (`OHS+PL`) | `hypothesis.proposed` | 仮説提案payloadを検証文脈の入力契約へ変換不要で伝播 |
| `audit-log` | Downstream (`OHS+PL`) | `hypothesis.proposed`, `hypothesis.proposal.failed` | `trace`, `identifier`, `reasonCode` を必須伝播 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-AO-001` | 受信イベントは `identifier`, `eventType`, `occurredAt`, `trace`, `payload` を必須とする | must | inside |
| `RULE-AO-002` | `skill_registry`/`instruction_profiles`/`code_reference_templates` の必須解決に失敗した場合は `hypothesis.proposal.failed`（`RESOURCE_NOT_FOUND`）で終了する | must | inside |
| `RULE-AO-003` | 類似失敗知見が閾値以上の場合は仮説を保存せず `hypothesis.proposal.failed`（`STATE_CONFLICT`）を発行する | must | inside |
| `RULE-AO-004` | 成功時の仮説は `identifier`, `symbol`, `instrumentType`, `title`, `sourceEvidence`, `skillVersion`, `instructionProfileVersion` を必須とする | must | inside |
| `RULE-AO-005` | 同一イベント `identifier`（エンベロープ）は1回のみ副作用を実行する | must | outside |
| `RULE-AO-006` | `hypothesis.proposed` は `hypothesis_registry` 保存成功後にのみ発行する | must | outside |
| `RULE-AO-007` | 失敗時は `failure_knowledge` に Markdown 要約（原因、再発防止、適用条件）を保存する | must | outside |
| `RULE-AO-008` | 非再試行エラーは `RESOURCE_NOT_FOUND`, `REQUEST_VALIDATION_FAILED` とする | must | inside |
| `RULE-AO-009` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: hypothesis orchestration
  Rule: 正常入力は仮説提案として発行される
    Example: insight.collected から提案成功
      Given 必須属性を持つ insight.collected を受信する
      And 必要な Skill と指示書とテンプレートが解決できる
      And 類似失敗知見が閾値未満である
      When agent-orchestrator が仮説生成を完了する
      Then hypothesis_registry に仮説が1件保存される
      And hypothesis.proposed が1回発行される
```

```gherkin
Feature: hypothesis orchestration
  Rule: 重複仮説は抑止される
    Example: 類似失敗知見が閾値以上
      Given insight.collected を受信する
      And failure_knowledge で類似度が閾値以上の知見が見つかる
      When 仮説生成可否を判定する
      Then hypothesis_registry への保存は行われない
      And hypothesis.proposal.failed が STATE_CONFLICT で発行される
```

```gherkin
Feature: hypothesis orchestration
  Rule: 依存解決不能は非再試行で失敗する
    Example: instruction profile 未登録
      Given insight.collected を受信する
      And instruction_profiles に対象版が存在しない
      When 生成コンテキストを解決する
      Then hypothesis.proposal.failed が RESOURCE_NOT_FOUND で発行される
      And 処理は非再試行で終了する
```

```gherkin
Feature: hypothesis orchestration
  Rule: 同一イベントidentifierは重複処理しない
    Example: duplicate event ingest
      Given 同一イベントidentifierが既に処理済みである
      When 同じ insight.collected を再受信する
      Then hypothesis.proposed は再発行されない
      And hypothesis.proposal.failed も再発行されない
```

```gherkin
Feature: hypothesis orchestration
  Rule: 識別子命名はidentifierへ統一する
    Example: 契約とドメインモデルの命名整合
      Given OpenAPI/AsyncAPI/Domain Model を突合する
      When 識別子項目を検査する
      Then 識別子サフィックス項目は存在しない
      And 当該関心の識別子は identifier を使用する
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-AO-001` | `SCN-AO-001` | `OrchestrationDispatch` | `insight.collected`, `hypothesis.retest.requested` | `TST-AO-001` |
| `RULE-AO-002` | `SCN-AO-003` | `HypothesisProposal` | `hypothesis.proposal.failed` | `TST-AO-002` |
| `RULE-AO-003` | `SCN-AO-002` | `HypothesisProposal` | `hypothesis.proposal.failed` | `TST-AO-003` |
| `RULE-AO-004` | `SCN-AO-001` | `HypothesisProposal` | `hypothesis.proposed` | `TST-AO-004` |
| `RULE-AO-005` | `SCN-AO-004` | `OrchestrationDispatch` | `insight.collected` | `TST-AO-005` |
| `RULE-AO-006` | `SCN-AO-001` | `OrchestrationDispatch` | `hypothesis.proposed` | `TST-AO-006` |
| `RULE-AO-007` | `SCN-AO-002` | `HypothesisProposal` | `failure_knowledge` | `TST-AO-007` |
| `RULE-AO-008` | `SCN-AO-003` | `HypothesisProposal` | `hypothesis.proposal.failed` | `TST-AO-008` |
| `RULE-AO-009` | `SCN-AO-009` | `HypothesisProposal` | OpenAPI/AsyncAPI/Domain Model | `TST-AO-009` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `HypothesisProposal` | `HypothesisProposal` | 仮説生成結果の確定と成功/失敗の業務判断 | `hypothesis_registry/{identifier}` | 成功時必須属性、失敗時理由必須 |
| `OrchestrationDispatch` | `OrchestrationDispatch` | 入力イベント単位の冪等性と発行可否確定 | `idempotency_keys/{identifier}` | 同一イベントの副作用単一実行 |

#### Aggregate詳細: `HypothesisProposal`

- root: `HypothesisProposal`
- 参照先集約: `OrchestrationDispatch`（`dispatch` 参照のみ）
- 生成コマンド: `StartProposal`
- 更新コマンド: `AttachGenerationContext`, `AssessDuplicateRisk`, `CompleteProposal`, `BlockProposal`, `FailProposal`
- 削除/無効化コマンド: `TerminateProposal`
- 不変条件:
1. `status=proposed` のとき `identifier`, `symbol`, `instrumentType`, `title`, `sourceEvidence`, `skillVersion`, `instructionProfileVersion` は必須。
2. `status=blocked` または `status=failed` のとき `reasonCode` は必須。
3. `identifier` は生成後不変。
4. `sourceEvidence` は空配列不可。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 仮説識別子（ULID） | `1` |
| `symbol` | `string` | 対象銘柄 | `1` |
| `instrumentType` | `enum(ETF, STOCK)` | 金融商品種別 | `1` |
| `title` | `string` | 仮説タイトル | `1` |
| `status` | `enum(pending, proposed, blocked, failed)` | 仮説生成状態 | `1` |
| `sourceEvidence` | `array<string>` | 根拠インサイト識別子群 | `1..n` |
| `skillVersion` | `string` | 生成に使用したSkill版 | `1` |
| `instructionProfileVersion` | `string` | 生成に使用した指示書版 | `1` |
| `insiderRisk` | `enum(low, medium, high)` | 初期リスク推定 | `0..1` |
| `mnpiSelfDeclared` | `boolean` | MNPI未保有自己申告初期値 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗/抑止理由 | `0..1` |
| `trace` | `string` | トレース識別子（ULID） | `1` |
| `dispatch` | `string` | 対応する `OrchestrationDispatch` 識別子 | `1` |
| `reportPath` | `string` | 生成レポート保存先 | `0..1` |
| `createdAt` | `datetime` | 生成開始時刻 | `1` |
| `updatedAt` | `datetime` | 最終更新時刻 | `1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `generationContext` | `GenerationContext` | Skill/指示書/テンプレート解決結果 | `1` |
| `duplicateAssessment` | `DuplicateAssessment` | 重複判定結果 | `0..1` |
| `proposalArtifact` | `ProposalArtifact` | 生成レポート情報 | `0..1` |
| `failureKnowledgeSummary` | `FailureKnowledgeSummary` | 失敗知見保存内容 | `0..1` |

#### Aggregate詳細: `OrchestrationDispatch`

- root: `OrchestrationDispatch`
- 参照先集約: `HypothesisProposal`（`hypothesis` 参照のみ）
- 生成コマンド: `StartDispatch`
- 更新コマンド: `MarkPublished`, `MarkDuplicate`, `MarkFailed`
- 削除/無効化コマンド: `TerminateDispatch`
- 不変条件:
1. 同一イベント `identifier` は1回のみ `published` へ遷移可能。
2. `dispatchStatus=published` のとき `publishedEvent` は必須。
3. `dispatchStatus=failed` のとき `reasonCode` は必須。
4. `identifier` は生成後不変。

#### 4.1.1 Aggregate Rootフィールド定義（OrchestrationDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子（ULID） | `1` |
| `sourceEventType` | `enum(insight.collected, hypothesis.retest.requested)` | 受信イベント種別 | `1` |
| `dispatchStatus` | `enum(pending, published, failed, duplicate)` | 配信確定状態 | `1` |
| `publishedEvent` | `enum(hypothesis.proposed, hypothesis.proposal.failed)` | 実際に発行したイベント種別 | `0..1` |
| `hypothesis` | `string` | 対応仮説識別子 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 配信失敗/重複理由 | `0..1` |
| `trace` | `string` | トレース識別子（ULID） | `1` |
| `retryCount` | `integer` | 再試行回数 | `0..1` |
| `processedAt` | `datetime` | 処理確定時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（OrchestrationDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `sourceEventSnapshot` | `SourceEventSnapshot` | 受信イベントの正規化スナップショット | `1` |
| `dispatchDecision` | `DispatchDecision` | 発行可否と再試行可否の判定結果 | `1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `HypothesisProposal` | `identifier` | `pending -> proposed/blocked/failed` | `resolveContext`, `assessDuplicate`, `propose`, `block`, `fail` |
| `OrchestrationDispatch` | `identifier` | `pending -> published/failed/duplicate` | `checkIdempotency`, `publish`, `markDuplicate`, `markFailed` |

#### Entity詳細: `HypothesisProposal`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 仮説識別子（ULID） | `1` |
| `status` | `enum(pending, proposed, blocked, failed)` | 仮説生成状態 | `1` |
| `sourceEvidence` | `array<string>` | 生成根拠インサイト | `1..n` |
| `skillVersion` | `string` | Skill版 | `1` |
| `instructionProfileVersion` | `string` | 指示書版 | `1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗/抑止理由 | `0..1` |

#### Entity詳細: `OrchestrationDispatch`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子（ULID） | `1` |
| `dispatchStatus` | `enum(pending, published, failed, duplicate)` | 発行状態 | `1` |
| `publishedEvent` | `enum(hypothesis.proposed, hypothesis.proposal.failed)` | 発行イベント種別 | `0..1` |
| `hypothesis` | `string` | 対応仮説識別子 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗/重複理由 | `0..1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `GenerationContext` | `skill`, `skillVersion`, `instructionProfile`, `instructionProfileVersion`, `codeReferenceTemplateVersion`, `promptHash` | 値比較 | immutable |
| `DuplicateAssessment` | `similarityHash`, `maxSimilarityScore`, `threshold`, `decision` | 値比較 | immutable |
| `ProposalArtifact` | `reportPath`, `llmModel`, `generatedAt`, `tokenUsage` | 値比較 | immutable |
| `FailureKnowledgeSummary` | `reasonCode`, `summary`, `markdownSummary`, `preventionChecklist` | 値比較 | immutable |
| `SourceEventSnapshot` | `identifier`, `eventType`, `occurredAt`, `trace`, `payload` | 値比較 | immutable |
| `DispatchDecision` | `publishedEvent`, `retryable`, `reasonCode` | 値比較 | immutable |

#### Value Object詳細: `GenerationContext`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `skill` | `string` | 適用Skill識別子 | `1` |
| `skillVersion` | `string` | Skill版 | `1` |
| `instructionProfile` | `string` | 指示書プロファイル識別子 | `1` |
| `instructionProfileVersion` | `string` | 指示書版 | `1` |
| `codeReferenceTemplateVersion` | `string` | コード参照テンプレート版 | `0..1` |
| `promptHash` | `string` | 実行プロンプトハッシュ | `1` |

#### Value Object詳細: `DuplicateAssessment`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `similarityHash` | `string` | 類似照合キー | `1` |
| `maxSimilarityScore` | `number` | 失敗知見との最大類似度 | `1` |
| `threshold` | `number` | 抑止閾値 | `1` |
| `decision` | `enum(allow, block)` | 判定結果 | `1` |
| `matchedKnowledge` | `string` | 一致した失敗知見識別子 | `0..1` |

#### Value Object詳細: `ProposalArtifact`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `reportPath` | `string` | 生成レポート保存先 | `1` |
| `llmModel` | `string` | 使用モデル識別子 | `1` |
| `generatedAt` | `datetime` | 生成完了時刻 | `1` |
| `tokenUsage` | `integer` | 推論トークン使用量 | `0..1` |

#### Value Object詳細: `FailureKnowledgeSummary`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `reasonCode` | `enum(ReasonCode)` | 失敗理由コード | `1` |
| `summary` | `string` | 短文要約 | `1` |
| `markdownSummary` | `string` | Markdown要約（原因・再発防止・適用条件） | `1` |
| `preventionChecklist` | `array<string>` | 再発防止チェック項目 | `0..n` |

#### Value Object詳細: `SourceEventSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子（ULID） | `1` |
| `eventType` | `enum(insight.collected, hypothesis.retest.requested)` | 受信イベント種別 | `1` |
| `occurredAt` | `datetime` | 発生時刻 | `1` |
| `trace` | `string` | トレース識別子（ULID） | `1` |
| `payload` | `object` | 正規化前入力payload | `1` |

#### Value Object詳細: `DispatchDecision`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `publishedEvent` | `enum(hypothesis.proposed, hypothesis.proposal.failed)` | 発行イベント種別 | `1` |
| `retryable` | `boolean` | 再試行可否 | `1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗/重複時理由 | `0..1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `GenerationContextResolutionPolicy` | domain | Skill/指示書/テンプレート解決可否判定 | Firestore直接アクセス |
| `DuplicateSuppressionPolicy` | domain | 失敗知見類似度による抑止判定 | IO処理 |
| `HypothesisOrchestrationService` | application | 受信イベントから生成・保存・発行までを統合実行 | 業務ルール本体 |
| `FailureKnowledgeRegistrar` | application | Markdown要約の整形と `failure_knowledge` 保存 | 重複判定ロジック |
| `DispatchService` | application | `idempotency_keys` を使った発行重複防止 | 業務判定ロジック |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `HypothesisProposalRepository` | 仮説提案状態永続化 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `OrchestrationDispatchRepository` | 冪等処理状態永続化 | `Find`, `Persist`, `Terminate` |
| Repository | `SkillRegistryRepository` | Skill解決 | `Find`, `FindByStatus`, `Search` |
| Repository | `InstructionProfileRepository` | 指示書解決 | `Find`, `FindByVersion`, `Search` |
| Repository | `CodeReferenceTemplateRepository` | テンプレート解決 | `Find`, `FindByScope`, `Search` |
| Repository | `FailureKnowledgeRepository` | 失敗知見照合/保存 | `Find`, `FindByReasonCode`, `Search`, `Persist` |
| Repository | `HypothesisReportRepository` | 生成レポート保存 | `Persist`, `Find` |
| Factory | `HypothesisProposalFactory` | 入力イベントから仮説提案を生成 | `fromInsightCollected`, `fromRetestRequested` |
| Factory | `DispatchFactory` | 入力イベントから冪等処理集約を生成 | `fromSourceEvent` |
| Specification | `ProposalPayloadIntegritySpecification` | 提案必須属性判定 | `isSatisfiedBy(proposal)` |
| Specification | `DuplicateThresholdSpecification` | 重複閾値判定 | `isSatisfiedBy(duplicateAssessment)` |
| Specification | `NonRetryableReasonSpecification` | 非再試行エラー判定 | `isSatisfiedBy(reasonCode)` |

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

| Aggregate | 現在状態 | コマンド | 次状態 | ガード条件 | 失敗時reasonCode |
|---|---|---|---|---|---|
| `OrchestrationDispatch` | `none` | `StartDispatch` | `pending` | エンベロープ必須属性が充足 | `REQUEST_VALIDATION_FAILED` |
| `HypothesisProposal` | `pending` | `CompleteProposal` | `proposed` | コンテキスト解決成功 + 重複判定 `allow` + 保存成功 | - |
| `HypothesisProposal` | `pending` | `BlockProposal` | `blocked` | 重複判定 `block` | `STATE_CONFLICT` |
| `HypothesisProposal` | `pending` | `FailProposal` | `failed` | Skill/指示書/テンプレート未解決 | `RESOURCE_NOT_FOUND` |
| `HypothesisProposal` | `pending` | `FailProposal` | `failed` | 入力不備/契約違反 | `REQUEST_VALIDATION_FAILED` |
| `HypothesisProposal` | `pending` | `FailProposal` | `failed` | 依存先タイムアウト/利用不可 | `DEPENDENCY_TIMEOUT` / `DEPENDENCY_UNAVAILABLE` |
| `OrchestrationDispatch` | `pending` | `MarkDuplicate` | `duplicate` | 同一イベント `identifier` が処理済み | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `OrchestrationDispatch` | `failed` | `RetryDispatch` | `failed` | `RESOURCE_NOT_FOUND` / `REQUEST_VALIDATION_FAILED`（非再試行） | 同左 |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-AO-001` | `HypothesisProposal` | `status=proposed` のとき必須属性（`sourceEvidence`, `skillVersion`, `instructionProfileVersion` 含む）を保持 | コマンド拒否 |
| `INV-AO-002` | `HypothesisProposal` | `status=blocked/failed` のとき `reasonCode` を保持 | コマンド拒否 |
| `INV-AO-003` | `OrchestrationDispatch` | 同一イベント `identifier` は1回のみ副作用実行 | 冪等扱い |
| `INV-AO-004` | `OrchestrationDispatch` | `dispatchStatus=published` のとき `publishedEvent` を保持 | コマンド拒否 |
| `INV-AO-005` | `HypothesisProposal` | `identifier` は生成後不変 | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `orchestration.dispatch.started` | `OrchestrationDispatch` | 入力検証通過時 | `identifier`, `sourceEventType`, `trace` | `identifier` |
| `hypothesis.proposal.composed` | `HypothesisProposal` | 生成完了時 | `identifier`, `symbol`, `instrumentType`, `skillVersion`, `instructionProfileVersion`, `trace` | `identifier` |
| `hypothesis.proposal.blocked` | `HypothesisProposal` | 重複抑止確定時 | `identifier`, `reasonCode`, `trace` | `identifier` |
| `hypothesis.proposal.failed` | `HypothesisProposal` | 失敗確定時 | `identifier`, `reasonCode`, `trace` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `hypothesis.proposed` | `hypothesis-lab`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `hypothesis.proposal.failed` | `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| インサイト起点の仮説生成 | `GenerateHypothesisFromInsight` | なし（イベント駆動） | `insight.collected`（受信） | `sourceEvidence` を必須付与 |
| 再検証要求起点の再生成 | `RegenerateHypothesis` | `POST /hypotheses/{identifier}/retest` | `hypothesis.retest.requested`（受信） | BFF経由で発行 |
| 仮説提案成功通知 | `PublishHypothesisProposed` | なし | `hypothesis.proposed`（発行） | 保存成功後にのみ発行 |
| 仮説提案失敗通知 | `PublishHypothesisProposalFailed` | なし | `hypothesis.proposal.failed`（発行） | `reasonCode` 必須 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `HypothesisProposal` | `agent-orchestrator` | `Firestore:hypothesis_registry` | `identifier`（仮説）単位 | `trace`, `identifier`, `symbol`, `status`, `skillVersion`, `instructionProfileVersion` |
| `OrchestrationDispatch` | `agent-orchestrator` | `Firestore:idempotency_keys` | `identifier`（イベント）単位 | `trace`, `identifier`, `sourceEventType`, `processedAt` |
| `FailureKnowledgeSummary` | `agent-orchestrator` | `Firestore:failure_knowledge` | 別Tx（失敗確定後） | `trace`, `identifier`, `reasonCode` |
| `ProposalExecutionAudit` | `agent-orchestrator` | `Cloud Logging` | 別Tx（各状態確定後） | `trace`, `identifier`, `eventType`, `result`, `reason` |
| `ProposalArtifact` | `agent-orchestrator` | `Cloud Storage:hypothesis_reports` | `identifier` 単位 | `trace`, `identifier`, `reportPath` |

- 他集約更新は同一Txで行わない。
- 集約間整合は `hypothesis.proposed` / `hypothesis.proposal.failed` と `idempotency_keys` で実現する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-AO-001` | acceptance | `RULE-AO-001` | 必須属性欠損時に `REQUEST_VALIDATION_FAILED` |
| `TST-AO-002` | acceptance | `RULE-AO-002` | 解決失敗時に `RESOURCE_NOT_FOUND` で `hypothesis.proposal.failed` |
| `TST-AO-003` | acceptance | `RULE-AO-003` | 類似度閾値超過で提案を保存せず失敗発行 |
| `TST-AO-004` | contract | `RULE-AO-004` | `hypothesis.proposed` payload 必須項目充足 |
| `TST-AO-005` | idempotency | `RULE-AO-005` | 同一イベントidentifier重複で副作用なし |
| `TST-AO-006` | domain event | `RULE-AO-006` | 保存後にのみ `hypothesis.proposed` 発行 |
| `TST-AO-007` | acceptance | `RULE-AO-007` | 失敗時に `failure_knowledge.markdownSummary` 保存 |
| `TST-AO-008` | retry | `RULE-AO-008` | 非再試行エラーは1回で終了 |
| `TST-AO-009` | contract | `RULE-AO-009` | OpenAPI/AsyncAPI/Domain Modelで `identifier` 命名統一 |

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

- 入力イベントの必須属性検証が fail-closed になっているか。
- `sourceEvidence`, `skillVersion`, `instructionProfileVersion` の必須性が成功系で担保されるか。
- 類似失敗知見の抑止判定が保存前に評価されるか。
- `hypothesis_registry` 保存とイベント発行順序が保証されるか。
- `idempotency_keys/{identifier}` で重複副作用を防止できるか。
- Rule→Scenario→Model→Contract→Test のトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/agent-orchestrator.md`
- `documents/内部設計/services/agent-orchestrator.md`
- `documents/内部設計/json/agent-orchestrator.json`
- `documents/外部設計/api/asyncapi.yaml`
- `documents/外部設計/api/asyncapi/components/schemas/HypothesisProposedPayload.yaml`
- `documents/外部設計/api/asyncapi/components/schemas/HypothesisRetestRequestedPayload.yaml`
- `documents/外部設計/api/asyncapi/components/schemas/InsightCollectedPayload.yaml`
- `documents/外部設計/db/firestore設計.md`
- `documents/外部設計/error/error-codes.json`
- `documents/外部設計/operations/運用設計.md`
