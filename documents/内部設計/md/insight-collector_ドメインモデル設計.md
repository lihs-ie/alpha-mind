# insight-collector ドメインモデル設計

最終更新日: 2026-02-28
対象Bounded Context: `insight-collector`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: `insight.collect.requested` を入力に、許可ソースと利用規約条件を満たす定性データを収集・構造化し、`insight.collected` / `insight.collect.failed` を整合的に発行する。
- スコープ内:
1. 収集要求イベントの入力検証（`targetDate`, `requestedBy`）
2. `source_policies` による許可ソース/利用規約の判定
3. 収集・要約・根拠情報（`sourceUrl`, `evidenceSnippet`）の必須検証
4. 収集結果保存と冪等性制御、監査保存
- スコープ外:
1. 仮説生成（`agent-orchestrator`）
2. 特徴量生成（`feature-engineering`）
3. 売買シグナル生成・注文処理（`signal-generator` / `portfolio-planner` / `risk-guard` / `execution`）

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Insight Intake`
- ミッション: 再現可能な収集ポリシーに基づき、根拠付きインサイトを下流で機械利用可能な形式で提供する。
- コア/支援/汎用サブドメイン区分: `supporting`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Insight Collect Request | `insight.collect.requested` の収集要求 | AsyncAPI payload | 必須項目欠損のまま収集を開始しない |
| Source Policy | 収集可否と利用規約条件を定義するポリシー | `Firestore:source_policies` | `enabled=false` や規約未充足のまま収集しない |
| Insight Record | 根拠付きで正規化されたインサイト記録 | `Firestore:insight_records` | `sourceUrl`/`evidenceSnippet` 欠損で保存しない |
| Insight Artifact | 収集成果物（保存先と件数） | `Cloud Storage:insight_processed`, `insight.collected.payload` | 保存前に成功イベントを発行しない |
| Collection Dispatch | 収集結果イベントの発行処理 | `idempotency_keys` | 同一イベントの重複発行禁止 |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `bff` | Upstream (`Customer-Supplier`) | `POST /commands/run-insight-cycle` -> `insight.collect.requested` | 受付時の `identifier`, `trace` を収集要求スナップショットへ正規化 |
| `source policy management` | Upstream (`Separate Ways`) | `Firestore:source_policies` | `sourceType`, `enabled`, `termsVersion`, `redistributionAllowed` を `SourcePolicySnapshot` へ正規化 |
| `agent-orchestrator` | Downstream (`OHS+PL`) | `insight.collected` | `payload.identifier`, `count`, `storagePath` を必須伝播 |
| `feature-engineering` | Downstream (`Separate Ways`) | `Firestore:insight_records`（参照） | `collectedAt`, `sourceUrl`, `evidenceSnippet` の整合を維持して保存 |
| `audit-log` | Downstream (`OHS+PL`) | `insight.collected`, `insight.collect.failed` | `trace`, `identifier`, `reasonCode` を必須伝播 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-IC-001` | `insight.collect.requested` の必須項目（`targetDate`, `requestedBy`）欠損時は収集開始しない | must | inside |
| `RULE-IC-002` | 許可されていないソース/規約未充足ソースは `insight.collect.failed`（`COMPLIANCE_SOURCE_UNAPPROVED`）を発行する | must | inside |
| `RULE-IC-003` | 保存対象の各インサイトは `sourceUrl` と `evidenceSnippet` を必須とする | must | inside |
| `RULE-IC-004` | 同一イベント `identifier`（event envelope）は1回のみ処理する | must | outside |
| `RULE-IC-005` | 成功時は `insight_records` / `insight_processed` 保存後にのみ `insight.collected` を発行する | must | outside |
| `RULE-IC-006` | `insight.collected` は `payload.identifier`, `payload.count`, `payload.storagePath` を必須で含む | must | inside |
| `RULE-IC-007` | 外部ソース障害は `DEPENDENCY_TIMEOUT` または `DEPENDENCY_UNAVAILABLE` として失敗確定する | must | inside |
| `RULE-IC-008` | 失敗時は `reasonCode` を保存し `insight.collect.failed` を発行する | must | inside |
| `RULE-IC-009` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: insight collection
  Rule: 許可済みソースのみ収集し根拠付きインサイトを保存する
    Example: 収集成功
      Given insight.collect.requested の必須項目が揃っている
      And source_policies が有効かつ規約条件を満たしている
      And 収集結果の全レコードに sourceUrl と evidenceSnippet がある
      When insight.collect.requested を受信する
      Then insight_records と insight_processed に成果物が保存される
      And insight.collected が発行される
```

```gherkin
Feature: insight collection
  Rule: 未承認ソースは失敗する
    Example: ポリシー未承認
      Given source_policies で対象ソースが enabled=false である
      When insight.collect.requested を受信する
      Then insight.collect.failed が発行される
      And reasonCode は COMPLIANCE_SOURCE_UNAPPROVED になる
```

```gherkin
Feature: insight collection
  Rule: 根拠欠損データは保存しない
    Example: evidenceSnippet欠損
      Given 収集データに evidenceSnippet 欠損レコードがある
      When insight.collect.requested を受信する
      Then insight.collect.failed が発行される
      And reasonCode は REQUEST_VALIDATION_FAILED になる
```

```gherkin
Feature: insight collection
  Rule: 同一イベントidentifierは重複処理しない
    Example: 重複受信
      Given 同一イベントidentifierが既に処理済みである
      When insight.collect.requested を受信する
      Then insight.collected は再発行されない
      And insight.collect.failed は再発行されない
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-IC-001` | `SCN-IC-001` | `InsightCollection` | `insight.collect.requested` | `TST-IC-001` |
| `RULE-IC-002` | `SCN-IC-002` | `InsightCollection` | `insight.collect.failed` | `TST-IC-002` |
| `RULE-IC-003` | `SCN-IC-003` | `InsightCollection` | `insight.collect.failed` | `TST-IC-003` |
| `RULE-IC-004` | `SCN-IC-004` | `InsightDispatch` | `insight.collect.requested` | `TST-IC-004` |
| `RULE-IC-005` | `SCN-IC-001` | `InsightDispatch` | `insight.collected` | `TST-IC-005` |
| `RULE-IC-006` | `SCN-IC-001` | `InsightCollection` | `insight.collected` | `TST-IC-006` |
| `RULE-IC-007` | `SCN-IC-005` | `InsightCollection` | `insight.collect.failed` | `TST-IC-007` |
| `RULE-IC-008` | `SCN-IC-002`, `SCN-IC-003`, `SCN-IC-005` | `InsightCollection` | `insight.collect.failed` | `TST-IC-008` |
| `RULE-IC-009` | `SCN-IC-009` | `InsightCollection` | OpenAPI/AsyncAPI/Domain Model | `TST-IC-009` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `InsightCollection` | `InsightCollection` | 入力検証・ポリシー判定・収集結果確定 | `insight_collection_runs/{identifier}` | 成功/失敗の単一確定、根拠情報必須 |
| `InsightDispatch` | `InsightDispatch` | 発行重複防止と配信状態確定 | `idempotency_keys/{identifier}` | 同一イベントの二重配信禁止 |

#### Aggregate詳細: `InsightCollection`

- root: `InsightCollection`
- 参照先集約: `InsightDispatch`（`identifier` 参照のみ）
- 生成コマンド: `StartCollection`
- 更新コマンド: `ValidateRequest`, `ResolveSourcePolicies`, `CollectInsights`, `NormalizeInsights`, `RecordCollectionSuccess`, `RecordCollectionFailure`
- 削除/無効化コマンド: `TerminateCollection`
- 不変条件:
1. `status=collected` のとき `count` と `storagePath` は必須。
2. `status=collected` のとき `records` の全要素で `sourceUrl` と `evidenceSnippet` は必須。
3. `status=failed` のとき `reasonCode` は必須。
4. `identifier` は不変。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 収集処理識別子（ULID） | `1` |
| `status` | `enum(pending, collected, failed)` | 収集状態 | `1` |
| `request` | `InsightCollectionRequestSnapshot` | 収集要求情報 | `1` |
| `sourcePolicy` | `SourcePolicySnapshot` | 適用ポリシー情報 | `0..n` |
| `records` | `InsightRecord` | 正規化済みインサイト | `0..n` |
| `count` | `integer` | 保存件数 | `0..1` |
| `storagePath` | `string` | 成果物保存先 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |
| `processedAt` | `datetime` | 処理確定時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `requestSnapshot` | `InsightCollectionRequestSnapshot` | 受信要求の正規化結果 | `1` |
| `sourcePolicySnapshot` | `SourcePolicySnapshot` | 収集ポリシー適用結果 | `0..n` |
| `insightArtifact` | `InsightArtifact` | 保存成果物 | `0..1` |
| `failureDetail` | `FailureDetail` | 失敗情報 | `0..1` |

#### Aggregate詳細: `InsightDispatch`

- root: `InsightDispatch`
- 参照先集約: `InsightCollection`（`identifier` 参照のみ）
- 生成コマンド: `StartDispatch`
- 更新コマンド: `MarkDispatched`, `MarkDispatchFailed`
- 削除/無効化コマンド: `TerminateDispatch`
- 不変条件:
1. 同一イベント `identifier` は1回のみ `published` へ遷移できる。
2. `dispatchStatus=failed` のとき `reasonCode` 必須。

#### 4.1.1 Aggregate Rootフィールド定義（InsightDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子（ULID） | `1` |
| `dispatchStatus` | `enum(pending, published, failed)` | 配信状態 | `1` |
| `publishedEvent` | `enum(insight.collected, insight.collect.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 配信失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |
| `processedAt` | `datetime` | 配信確定時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（InsightDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `dispatchDecision` | `DispatchDecision` | 配信結果と理由 | `1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `InsightCollection` | `identifier` | `pending -> collected/failed` | `validateRequest`, `applyPolicies`, `collect`, `complete`, `fail` |
| `InsightDispatch` | `identifier` | `pending -> published/failed` | `publish`, `fail` |

#### Entity詳細: `InsightCollection`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 収集識別子 | `1` |
| `status` | `enum(pending, collected, failed)` | 収集状態 | `1` |
| `count` | `integer` | 保存件数 | `0..1` |
| `storagePath` | `string` | 保存先 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

#### Entity詳細: `InsightDispatch`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子 | `1` |
| `dispatchStatus` | `enum(pending, published, failed)` | 配信状態 | `1` |
| `publishedEvent` | `enum(insight.collected, insight.collect.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `InsightCollectionRequestSnapshot` | `targetDate`, `requestedBy` | 値比較 | immutable |
| `SourcePolicySnapshot` | `sourceType`, `enabled`, `termsVersion`, `redistributionAllowed`, `dailyQuota` | 値比較 | immutable |
| `InsightRecord` | `identifier`, `sourceType`, `sourceUrl`, `evidenceSnippet`, `collectedAt`, `summary`, `skillVersion` | 値比較 | immutable |
| `InsightArtifact` | `identifier`, `count`, `storagePath` | 値比較 | immutable |
| `FailureDetail` | `reasonCode`, `detail`, `retryable` | 値比較 | immutable |
| `DispatchDecision` | `dispatchStatus`, `publishedEvent`, `reasonCode` | 値比較 | immutable |

#### Value Object詳細: `InsightCollectionRequestSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `targetDate` | `date` | 収集対象日 | `1` |
| `requestedBy` | `enum(scheduler, user)` | 起動主体 | `1` |

#### Value Object詳細: `SourcePolicySnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `sourceType` | `enum(x, youtube, paper, github, nisshokin)` | ソース種別 | `1` |
| `enabled` | `boolean` | 利用可否 | `1` |
| `termsVersion` | `string` | 規約版 | `1` |
| `redistributionAllowed` | `boolean` | 再配布可否 | `1` |
| `dailyQuota` | `integer` | 日次利用上限 | `0..1` |

#### Value Object詳細: `InsightRecord`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | インサイト識別子（ULID） | `1` |
| `sourceType` | `enum(x, youtube, paper, github)` | 情報源種別 | `1` |
| `sourceUrl` | `string` | 根拠URL | `1` |
| `evidenceSnippet` | `string` | 根拠抜粋 | `1` |
| `collectedAt` | `datetime` | 収集時刻 | `1` |
| `summary` | `string` | 要約本文 | `1` |
| `skillVersion` | `string` | 収集Skill版 | `1` |

#### Value Object詳細: `InsightArtifact`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 収集処理識別子 | `1` |
| `count` | `integer` | 保存件数 | `1` |
| `storagePath` | `string` | 成果物保存先 | `1` |

#### Value Object詳細: `FailureDetail`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `reasonCode` | `enum(ReasonCode)` | 失敗理由コード | `1` |
| `detail` | `string` | 補足情報 | `0..1` |
| `retryable` | `boolean` | 再試行可否 | `1` |

#### Value Object詳細: `DispatchDecision`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `dispatchStatus` | `enum(pending, published, failed)` | 配信状態 | `1` |
| `publishedEvent` | `enum(insight.collected, insight.collect.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `SourcePolicyComplianceService` | domain | 許可ソース・規約条件判定と失敗理由決定 | 外部API呼び出し |
| `EvidenceCompletenessPolicy` | domain | `sourceUrl`/`evidenceSnippet` 完全性判定 | IO処理 |
| `InsightCollectionService` | application | 受信イベントから収集/保存/発行までをオーケストレーション | 業務ルール本体 |
| `InsightAuditWriter` | application | 監査ログ記録 | 収集判定ロジック |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `InsightCollectionRepository` | 収集状態永続化 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `InsightDispatchRepository` | 配信状態永続化 | `Find`, `Persist`, `Terminate` |
| Repository | `SourcePolicyRepository` | 収集ポリシー参照 | `Search`, `FindBySourceType` |
| Repository | `InsightRecordRepository` | インサイト保存 | `Persist`, `Search`, `FindByTargetDate` |
| Repository | `InsightArtifactRepository` | 成果物保存 | `Persist`, `Find`, `Terminate` |
| Repository | `IdempotencyKeyRepository` | 重複処理防止 | `Find`, `Persist`, `Terminate` |
| Factory | `InsightCollectionFactory` | 入力イベントから収集集約を作成 | `fromCollectRequestedEvent` |
| Factory | `InsightDispatchFactory` | 配信集約の作成 | `fromInsightCollection` |
| Specification | `InsightRequestIntegritySpecification` | 入力必須項目判定 | `isSatisfiedBy(request)` |
| Specification | `SourcePolicyApprovedSpecification` | 許可ソース判定 | `isSatisfiedBy(policy)` |
| Specification | `EvidenceCompletenessSpecification` | 根拠情報完全性判定 | `isSatisfiedBy(record)` |

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
| `pending` | `CollectInsights` | `collected` | 入力必須項目OK + 許可ソース/規約条件OK + 根拠情報完全 + 保存成功 | - |
| `pending` | `CollectInsights` | `failed` | 入力不正 | `REQUEST_VALIDATION_FAILED` |
| `pending` | `CollectInsights` | `failed` | 未承認ソース/規約違反 | `COMPLIANCE_SOURCE_UNAPPROVED` |
| `pending` | `CollectInsights` | `failed` | 外部ソースタイムアウト | `DEPENDENCY_TIMEOUT` |
| `pending` | `CollectInsights` | `failed` | 外部ソース利用不可 | `DEPENDENCY_UNAVAILABLE` |
| `pending` | `CollectInsights` | `failed` | 根拠情報欠損 | `REQUEST_VALIDATION_FAILED` |
| `collected` | `CollectInsights` | `collected` | 同一イベントidentifier重複受信 | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `failed` | `CollectInsights` | `failed` | 終端状態への再実行 | `STATE_CONFLICT` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-IC-001` | `InsightCollection` | `status=collected` のとき `count`,`storagePath` 必須 | コマンド拒否 |
| `INV-IC-002` | `InsightCollection` | `status=collected` のとき全 `records` で `sourceUrl`,`evidenceSnippet` 必須 | コマンド拒否 |
| `INV-IC-003` | `InsightCollection` | `status=failed` のとき `reasonCode` 必須 | コマンド拒否 |
| `INV-IC-004` | `InsightDispatch` | 同一イベント `identifier` は1回のみ publish | 冪等扱い |
| `INV-IC-005` | `InsightCollection` | `identifier` は生成後不変 | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `insight.collection.started` | `InsightCollection` | 受信処理開始時 | `identifier`, `targetDate`, `trace` | `identifier` |
| `insight.collection.completed` | `InsightCollection` | 収集確定時 | `identifier`, `count`, `storagePath`, `trace` | `identifier` |
| `insight.collection.failed` | `InsightCollection` | 失敗確定時 | `identifier`, `reasonCode`, `detail`, `trace` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `insight.collected` | `agent-orchestrator`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `insight.collect.failed` | `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 手動インサイト収集受付 | `RunInsightCycle` | `POST /commands/run-insight-cycle` | `insight.collect.requested`（受信） | BFFが受付しイベント発行 |
| インサイト収集成功通知 | `PublishInsightCollected` | なし | `insight.collected`（発行） | `payload.identifier`, `count`, `storagePath` 必須 |
| インサイト収集失敗通知 | `PublishInsightCollectFailed` | なし | `insight.collect.failed`（発行） | `reasonCode` 必須 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `InsightRecord` | `insight-collector` | `Firestore:insight_records` | `identifier` 単位 | `trace`, `identifier`, `sourceType`, `collectedAt` |
| `InsightArtifact` | `insight-collector` | `Cloud Storage:insight_processed` | `identifier` 単位 | `trace`, `identifier`, `count`, `storagePath` |
| `SourcePolicySnapshot` | `insight-collector` | `Firestore:source_policies`（参照） | 読み取り専用 | `sourceType`, `termsVersion`, `enabled` |
| `InsightDispatch` | `insight-collector` | `Firestore:idempotency_keys` | `identifier` 単位 | `trace`, `identifier`, `processedAt` |
| `InsightCollectionAudit` | `insight-collector` | `Firestore:audit_logs` | `identifier` 単位 | `trace`, `identifier`, `result`, `reasonCode` |

- 他集約更新は同一Txで行わない。
- 集約間整合は `insight.collect.*` イベントで実現する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-IC-001` | acceptance | `RULE-IC-001` | 必須項目欠損時に収集開始しない |
| `TST-IC-002` | acceptance | `RULE-IC-002` | 未承認ソースで `COMPLIANCE_SOURCE_UNAPPROVED` |
| `TST-IC-003` | invariant | `RULE-IC-003` | `sourceUrl` または `evidenceSnippet` 欠損時に失敗 |
| `TST-IC-004` | idempotency | `RULE-IC-004` | 同一identifier重複で副作用なし |
| `TST-IC-005` | domain event | `RULE-IC-005` | 保存後に `insight.collected` 発行 |
| `TST-IC-006` | contract | `RULE-IC-006` | `insight.collected` 必須項目を常に含む |
| `TST-IC-007` | acceptance | `RULE-IC-007` | timeout/unavailable を正しい reasonCode へ正規化 |
| `TST-IC-008` | domain event | `RULE-IC-008` | 失敗時に `reasonCode` 付きで `insight.collect.failed` 発行 |
| `TST-IC-009` | contract | `RULE-IC-009` | OpenAPI/AsyncAPI/Domain Modelで `identifier` 命名統一 |

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

- `source_policies` による許可/規約判定を安全側で保証できるか。
- `sourceUrl` と `evidenceSnippet` を欠損なく保持できるか。
- `insight_records` / `insight_processed` 保存とイベント発行順序が保証されるか。
- 下流（`agent-orchestrator`）が要求する収集成果（件数・保存先）を契約どおり受け取れるか。
- Rule→Scenario→Model→Contract→Test のトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/insight-collector.md`
- `documents/内部設計/services/insight-collector.md`
- `documents/内部設計/json/insight-collector.json`
- `documents/外部設計/api/asyncapi.yaml`
- `documents/外部設計/api/openapi.yaml`
- `documents/外部設計/db/firestore設計.md`
- `documents/外部設計/error/error-codes.json`
