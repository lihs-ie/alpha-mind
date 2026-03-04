# signal-generator ドメインモデル設計

最終更新日: 2026-03-03
対象Bounded Context: `signal-generator`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: `features.generated` から再現可能な推論シグナルを生成し、`signal.generated` / `signal.generation.failed` を整合的に発行する。
- スコープ内:
1. `features.generated` 受信時の入力検証
2. `approved` モデル解決と推論実行
3. `modelDiagnostics` を含む結果イベント生成
4. 冪等性制御と監査保存
- スコープ外:
1. 特徴量生成（`feature-engineering`）
2. 注文候補生成（`portfolio-planner`）
3. モデル学習/評価（`models/validation`）

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Signal Inference`
- ミッション: 承認済みモデルのみを使って推論し、下流判断に必要な診断情報付きシグナルを提供する。
- コア/支援/汎用サブドメイン区分: `core`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Feature Snapshot | `features.generated` の入力スナップショット | AsyncAPI payload | 必須項目欠損のまま推論しない |
| Approved Model | 本番利用許可済みモデル | `model_registry` | `candidate/rejected` は利用禁止 |
| Model Diagnostics | 推論結果に付随する診断情報 | `signal.generated.payload.modelDiagnostics` | `requiresComplianceReview` 欠損禁止 |
| Signal Artifact | 推論結果ファイル | `Cloud Storage:signal_store` | 保存前に成功イベントを発行しない |
| Signal Dispatch | 1回のシグナル発行処理 | `idempotency_keys` | 同一イベントの二重発行禁止 |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `feature-engineering` | Upstream (`Customer-Supplier`) | `features.generated` | payload を `FeatureSnapshot` に正規化 |
| `bff` | Upstream (`Separate Ways`) | `GET /models/validation*`（運用制御） | `model_registry` の `approved` 状態を推論可否へ変換 |
| `portfolio-planner` | Downstream (`OHS+PL`) | `signal.generated` | `modelDiagnostics` を保持して伝播 |
| `audit-log` | Downstream (`OHS+PL`) | `signal.generated`, `signal.generation.failed` | `trace`, `identifier`, `reasonCode` を必須伝播 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-SG-001` | `features.generated` の必須項目（`targetDate`, `featureVersion`, `storagePath`）欠損時は推論を開始しない | must | inside |
| `RULE-SG-002` | `approved` モデルが存在しない場合は `signal.generation.failed`（`MODEL_NOT_APPROVED`）を発行する | must | inside |
| `RULE-SG-003` | 同一イベント `identifier`（event envelope）は1回のみ処理する | must | outside |
| `RULE-SG-004` | 推論件数はユニバース件数と一致しなければならない。不一致時は失敗（`SIGNAL_GENERATION_FAILED`）とする | must | inside |
| `RULE-SG-005` | 成功時は `signal_store` 保存後にのみ `signal.generated` を発行する | must | outside |
| `RULE-SG-006` | `signal.generated` には `modelDiagnostics` を必須で含め、`requiresComplianceReview` を必ず設定する | must | inside |
| `RULE-SG-007` | `degradationFlag=block` の場合は `requiresComplianceReview=true` として伝播する | must | inside |
| `RULE-SG-008` | 失敗時は `reasonCode` を保存し `signal.generation.failed` を発行する | must | inside |
| `RULE-SG-009` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: signal inference
  Rule: 正常入力とapprovedモデルでシグナルを生成する
    Example: 推論成功
      Given features.generated の必須項目が揃っている
      And approved モデルが存在する
      And 推論件数がユニバース件数と一致する
      When features.generated を受信する
      Then signal_store に結果が保存される
      And signal.generated が発行される
```

```gherkin
Feature: signal inference
  Rule: approvedモデル未解決時は失敗する
    Example: approvedモデルなし
      Given features.generated の必須項目が揃っている
      And approved モデルが存在しない
      When features.generated を受信する
      Then signal.generation.failed が発行される
      And reasonCode は MODEL_NOT_APPROVED になる
```

```gherkin
Feature: signal inference
  Rule: 同一イベントidentifierは重複処理しない
    Example: 重複受信
      Given 同一イベントidentifierが既に処理済みである
      When features.generated を受信する
      Then signal.generated は再発行されない
      And signal.generation.failed は再発行されない
```

```gherkin
Feature: signal inference
  Rule: block劣化はコンプライアンスレビュー要として伝播する
    Example: block判定
      Given approved モデルで推論が成功する
      And modelDiagnostics.degradationFlag が block である
      When features.generated を受信する
      Then signal.generated が発行される
      And modelDiagnostics.requiresComplianceReview は true になる
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-SG-001` | `SCN-SG-001` | `SignalGeneration` | `features.generated` | `TST-SG-001` |
| `RULE-SG-002` | `SCN-SG-002` | `SignalGeneration` | `features.generated`, `signal.generation.failed` | `TST-SG-002` |
| `RULE-SG-003` | `SCN-SG-003` | `SignalDispatch` | `features.generated` | `TST-SG-003` |
| `RULE-SG-004` | `SCN-SG-004` | `SignalGeneration` | `signal.generated` | `TST-SG-004` |
| `RULE-SG-005` | `SCN-SG-001` | `SignalDispatch` | `signal.generated` | `TST-SG-005` |
| `RULE-SG-006` | `SCN-SG-005` | `SignalGeneration` | `signal.generated` | `TST-SG-006` |
| `RULE-SG-007` | `SCN-SG-005` | `SignalGeneration` | `signal.generated` | `TST-SG-007` |
| `RULE-SG-008` | `SCN-SG-006` | `SignalGeneration` | `signal.generation.failed` | `TST-SG-008` |
| `RULE-SG-009` | `SCN-SG-009` | `SignalGeneration` | OpenAPI/AsyncAPI/Domain Model | `TST-SG-009` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `SignalGeneration` | `SignalGeneration` | 入力検証・モデル解決・推論結果確定 | `signal_runs/{identifier}` | 成功/失敗の単一確定、診断情報必須 |
| `SignalDispatch` | `SignalDispatch` | 発行重複防止と配信状態確定 | `idempotency_keys/{identifier}` | 同一イベントの二重配信禁止 |

#### Aggregate詳細: `SignalGeneration`

- root: `SignalGeneration`
- 参照先集約: `SignalDispatch`（`identifier` 参照のみ）
- 生成コマンド: `StartSignalGeneration`
- 更新コマンド: `ResolveApprovedModel`, `RunInference`, `RecordGenerationSuccess`, `RecordGenerationFailure`
- 削除/無効化コマンド: `TerminateSignalGeneration`
- 不変条件:
1. `status=generated` のとき `signalVersion`, `storagePath`, `modelDiagnostics` は必須。
2. `status=failed` のとき `reasonCode` は必須。
3. `degradationFlag=block` のとき `requiresComplianceReview=true`。
4. `identifier` は不変。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | シグナル生成処理識別子（ULID） | `1` |
| `status` | `enum(pending, generated, failed)` | 生成状態 | `1` |
| `feature` | `FeatureSnapshot` | 入力特徴量スナップショット | `1` |
| `model` | `ModelSnapshot` | 推論に使うモデル情報 | `0..1` |
| `signalVersion` | `string` | シグナル版 | `0..1` |
| `storagePath` | `string` | 出力保存先 | `0..1` |
| `generatedCount` | `integer` | 推論結果件数 | `0..1` |
| `universeCount` | `integer` | 期待件数 | `1` |
| `modelDiagnostics` | `ModelDiagnosticsSnapshot` | モデル診断情報 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |
| `processedAt` | `datetime` | 処理確定時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `featureSnapshot` | `FeatureSnapshot` | 入力イベントの要約 | `1` |
| `modelSnapshot` | `ModelSnapshot` | モデル解決結果 | `0..1` |
| `signalArtifact` | `SignalArtifact` | 出力アーティファクト情報 | `0..1` |
| `failureDetail` | `FailureDetail` | 失敗情報 | `0..1` |

#### Aggregate詳細: `SignalDispatch`

- root: `SignalDispatch`
- 参照先集約: `SignalGeneration`（`identifier` 参照のみ）
- 生成コマンド: `StartDispatch`
- 更新コマンド: `MarkDispatched`, `MarkDispatchFailed`
- 削除/無効化コマンド: `TerminateDispatch`
- 不変条件:
1. 同一イベント `identifier` は1回のみ `published` へ遷移できる。
2. `dispatchStatus=failed` のとき `reasonCode` 必須。

#### 4.1.1 Aggregate Rootフィールド定義（SignalDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子（ULID） | `1` |
| `dispatchStatus` | `enum(pending, published, failed)` | 配信状態 | `1` |
| `publishedEvent` | `enum(signal.generated, signal.generation.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 配信失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |
| `processedAt` | `datetime` | 配信確定時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（SignalDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `dispatchDecision` | `DispatchDecision` | 配信結果と理由 | `1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `SignalGeneration` | `identifier` | `pending -> generated/failed` | `resolveModel`, `infer`, `complete`, `fail` |
| `SignalDispatch` | `identifier` | `pending -> published/failed` | `publish`, `fail` |

#### Entity詳細: `SignalGeneration`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 生成識別子 | `1` |
| `status` | `enum(pending, generated, failed)` | 生成状態 | `1` |
| `signalVersion` | `string` | 出力シグナル版 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

#### Entity詳細: `SignalDispatch`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子 | `1` |
| `dispatchStatus` | `enum(pending, published, failed)` | 配信状態 | `1` |
| `publishedEvent` | `enum(signal.generated, signal.generation.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `FeatureSnapshot` | `targetDate`, `featureVersion`, `storagePath` | 値比較 | immutable |
| `ModelSnapshot` | `modelVersion`, `status`, `approvedAt` | 値比較 | immutable |
| `ModelDiagnosticsSnapshot` | `degradationFlag`, `requiresComplianceReview`, `costAdjustedReturn`, `slippageAdjustedSharpe` | 値比較 | immutable |
| `SignalArtifact` | `signalVersion`, `storagePath`, `generatedCount`, `universeCount` | 値比較 | immutable |
| `FailureDetail` | `reasonCode`, `detail`, `retryable` | 値比較 | immutable |
| `DispatchDecision` | `dispatchStatus`, `publishedEvent`, `reasonCode` | 値比較 | immutable |

#### Value Object詳細: `FeatureSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `targetDate` | `date` | 対象日 | `1` |
| `featureVersion` | `string` | 特徴量版 | `1` |
| `storagePath` | `string` | 特徴量保存先 | `1` |

#### Value Object詳細: `ModelSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `modelVersion` | `string` | モデル版 | `1` |
| `status` | `enum(candidate, approved, rejected)` | モデル状態 | `1` |
| `approvedAt` | `datetime` | 承認時刻 | `0..1` |

#### Value Object詳細: `ModelDiagnosticsSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `degradationFlag` | `enum(normal, warn, block)` | 劣化フラグ | `1` |
| `requiresComplianceReview` | `boolean` | コンプライアンスレビュー要否 | `1` |
| `costAdjustedReturn` | `number` | コスト控除後リターン | `0..1` |
| `slippageAdjustedSharpe` | `number` | スリッページ控除後Sharpe | `0..1` |

#### Value Object詳細: `SignalArtifact`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `signalVersion` | `string` | 出力シグナル版 | `1` |
| `storagePath` | `string` | 出力保存先 | `1` |
| `generatedCount` | `integer` | 生成件数 | `1` |
| `universeCount` | `integer` | 期待件数 | `1` |

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
| `publishedEvent` | `enum(signal.generated, signal.generation.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `ApprovedModelPolicy` | domain | `approved` モデル解決可否判定 | Firestoreアクセス |
| `InferenceConsistencyPolicy` | domain | 推論件数整合と診断情報補正（block時のレビュー要否） | IO処理 |
| `SignalGenerationService` | application | 受信イベントから推論/保存/発行までをオーケストレーション | 業務ルール本体 |
| `SignalAuditWriter` | application | 監査ログ記録 | 推論判定ロジック |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `SignalGenerationRepository` | 生成状態永続化 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `SignalDispatchRepository` | 配信状態永続化 | `Find`, `Persist`, `Terminate` |
| Repository | `ModelRegistryRepository` | モデル参照 | `FindByStatus`, `Find`, `Search` |
| Repository | `IdempotencyKeyRepository` | 重複処理防止 | `Find`, `Persist`, `Terminate` |
| Factory | `SignalGenerationFactory` | 入力イベントから生成集約を作成 | `fromFeaturesGeneratedEvent` |
| Factory | `SignalDispatchFactory` | 配信集約の作成 | `fromSignalGeneration` |
| Specification | `FeaturePayloadIntegritySpecification` | 入力必須項目判定 | `isSatisfiedBy(feature)` |
| Specification | `ApprovedModelExistsSpecification` | approvedモデル存在判定 | `isSatisfiedBy(model)` |
| Specification | `PredictionCountConsistencySpecification` | 件数整合判定 | `isSatisfiedBy(artifact)` |

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
| `pending` | `RunInference` | `generated` | approvedモデルあり + 件数整合 + 出力保存成功 | - |
| `pending` | `RunInference` | `failed` | approvedモデル未解決 | `MODEL_NOT_APPROVED` |
| `pending` | `RunInference` | `failed` | 入力特徴量不正 | `REQUEST_VALIDATION_FAILED` |
| `pending` | `RunInference` | `failed` | 依存先timeout/利用不可 | `DEPENDENCY_TIMEOUT` / `DEPENDENCY_UNAVAILABLE` |
| `pending` | `RunInference` | `failed` | 推論件数不一致 | `SIGNAL_GENERATION_FAILED` |
| `generated` | `RunInference` | `generated` | 同一イベントidentifier重複受信 | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `failed` | `RunInference` | `failed` | 終端状態への再実行 | `STATE_CONFLICT` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-SG-001` | `SignalGeneration` | `status=generated` のとき `signalVersion`,`storagePath`,`modelDiagnostics` 必須 | コマンド拒否 |
| `INV-SG-002` | `SignalGeneration` | `status=failed` のとき `reasonCode` 必須 | コマンド拒否 |
| `INV-SG-003` | `SignalGeneration` | `degradationFlag=block` のとき `requiresComplianceReview=true` | コマンド拒否 |
| `INV-SG-004` | `SignalDispatch` | 同一イベント `identifier` は1回のみ publish | 冪等扱い |
| `INV-SG-005` | `SignalGeneration` | `identifier` は生成後不変 | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `signal.generation.started` | `SignalGeneration` | 受信処理開始時 | `identifier`, `featureVersion`, `trace` | `identifier` |
| `signal.generation.completed` | `SignalGeneration` | 生成確定時 | `identifier`, `signalVersion`, `modelVersion`, `featureVersion`, `storagePath`, `modelDiagnostics`, `trace` | `identifier` |
| `signal.generation.failed` | `SignalGeneration` | 失敗確定時 | `identifier`, `reasonCode`, `detail`, `trace` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `signal.generated` | `portfolio-planner`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `signal.generation.failed` | `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 特徴量受信で推論開始 | `GenerateSignals` | なし（イベント駆動） | `features.generated`（受信） | 入力は `FeaturesGeneratedPayload` |
| 推論成功通知 | `PublishSignalGenerated` | なし | `signal.generated`（発行） | 保存後に発行 |
| 推論失敗通知 | `PublishSignalGenerationFailed` | なし | `signal.generation.failed`（発行） | `reasonCode` 必須 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `SignalArtifact` | `signal-generator` | `Cloud Storage:signal_store` | `identifier` 単位 | `trace`, `identifier`, `signalVersion`, `modelVersion`, `featureVersion` |
| `SignalDispatch` | `signal-generator` | `Firestore:idempotency_keys` | `identifier` 単位 | `trace`, `identifier`, `processedAt` |
| `SignalGenerationAudit` | `signal-generator` | `Cloud Logging` | 別Tx（状態確定後） | `trace`, `identifier`, `result`, `reasonCode` |
| `FeatureSnapshot` | `feature-engineering` | `Cloud Storage:feature_store`（参照） | 読み取り専用 | `trace`, `featureVersion`, `targetDate` |
| `ModelSnapshot` | `bff/model validation` | `Firestore:model_registry`（参照） | 読み取り専用 | `trace`, `modelVersion`, `status` |

- 他集約更新は同一Txで行わない。
- 集約間整合は `signal.*` イベントで実現する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-SG-001` | acceptance | `RULE-SG-001` | 入力必須項目欠損時に推論開始しない |
| `TST-SG-002` | acceptance | `RULE-SG-002` | approvedモデル未解決で `signal.generation.failed` |
| `TST-SG-003` | idempotency | `RULE-SG-003` | 同一identifier重複で副作用なし |
| `TST-SG-004` | acceptance | `RULE-SG-004` | 件数不一致で `SIGNAL_GENERATION_FAILED` |
| `TST-SG-005` | domain event | `RULE-SG-005` | 保存後に `signal.generated` 発行 |
| `TST-SG-006` | contract | `RULE-SG-006` | `modelDiagnostics.requiresComplianceReview` を常に含む |
| `TST-SG-007` | invariant | `RULE-SG-007` | `degradationFlag=block` なら `requiresComplianceReview=true` |
| `TST-SG-008` | domain event | `RULE-SG-008` | 失敗時に `reasonCode` 付きで `signal.generation.failed` 発行 |
| `TST-SG-009` | contract | `RULE-SG-009` | OpenAPI/AsyncAPI/Domain Modelで `identifier` 命名統一 |

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

- approvedモデル以外を誤って推論に使っていないか。
- `modelDiagnostics.requiresComplianceReview` が必ず伝播されるか。
- 失敗時 `reasonCode` が業務語彙（`MODEL_NOT_APPROVED` 等）と一致しているか。
- `signal_store` 保存とイベント発行順序が保証されるか。
- Rule→Scenario→Model→Contract→Test のトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/signal-generator.md`
- `documents/内部設計/services/signal-generator.md`
- `documents/内部設計/json/signal-generator.json`
- `documents/外部設計/api/asyncapi.yaml`
- `documents/外部設計/state/状態遷移設計.md`
