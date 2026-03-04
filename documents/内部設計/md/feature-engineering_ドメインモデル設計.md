# feature-engineering ドメインモデル設計

最終更新日: 2026-03-03
対象Bounded Context: `feature-engineering`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: `market.collected` を入力に、時点整合を満たした再現可能な特徴量を生成し、`features.generated` / `features.generation.failed` を整合的に発行する。
- スコープ内:
1. `market.collected` 受信時の入力検証
2. `insight_records` 参照と `targetDate` 基準の時点整合フィルタ
3. 特徴量生成・`featureVersion` 採番・保存
4. 冪等性制御と監査保存
- スコープ外:
1. 市場データ収集（`data-collector`）
2. シグナル推論（`signal-generator`）
3. 注文計画・審査・執行（`portfolio-planner` / `risk-guard` / `execution`）

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Feature Pipeline`
- ミッション: 将来情報リークを防止しつつ、下流推論で再利用可能な特徴量アーティファクトを提供する。
- コア/支援/汎用サブドメイン区分: `supporting`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Market Snapshot | `market.collected` の入力要約 | AsyncAPI payload | 必須項目欠損のまま処理しない |
| Insight Snapshot | `insight_records` から対象日までに収集された定性情報の要約 | Firestore read model | `collectedAt > targetDate` は取り込み禁止 |
| Point-in-Time Join | `targetDate` 時点での定量/定性結合 | Feature生成処理 | 時系列逆転の結合を禁止 |
| Leakage Guard | 将来情報混入の検知・遮断規則 | 品質ゲート | 検知時に成功イベントを出さない |
| Feature Artifact | 生成特徴量ファイルと付随メタデータ | `Cloud Storage:feature_store` | 保存前に `features.generated` を発行しない |
| Feature Dispatch | 1回の特徴量イベント発行処理 | `idempotency_keys` | 同一イベントの二重発行禁止 |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `data-collector` | Upstream (`Customer-Supplier`) | `market.collected` | payload を `MarketSnapshot` に正規化 |
| `insight-collector` | Upstream (`Separate Ways`) | `Firestore:insight_records`（参照） | `targetDate` で時点フィルタし `InsightSnapshot` へ正規化 |
| `signal-generator` | Downstream (`OHS+PL`) | `features.generated` | `targetDate`, `featureVersion`, `storagePath` を必須伝播 |
| `audit-log` | Downstream (`OHS+PL`) | `features.generated`, `features.generation.failed` | `trace`, `identifier`, `reasonCode` を必須伝播 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-FE-001` | `market.collected` の必須項目（`targetDate`, `storagePath`, `sourceStatus`）欠損時は生成開始しない | must | inside |
| `RULE-FE-002` | `sourceStatus.jp/us` が `ok` でない場合は `features.generation.failed`（`DEPENDENCY_UNAVAILABLE`）を発行する | must | inside |
| `RULE-FE-003` | `insight_records` は `collectedAt <= targetDate` のみ結合し、将来情報が混入した場合は失敗（`DATA_QUALITY_LEAK_DETECTED`）とする | must | inside |
| `RULE-FE-004` | 同一イベント `identifier`（event envelope）は1回のみ処理する | must | outside |
| `RULE-FE-005` | 成功時は `feature_store` 保存後にのみ `features.generated` を発行する | must | outside |
| `RULE-FE-006` | `featureVersion` は一意に採番し、生成後に変更しない | must | inside |
| `RULE-FE-007` | `features.generated` は `targetDate`, `featureVersion`, `storagePath` を必須で含む | must | inside |
| `RULE-FE-008` | 失敗時は `reasonCode` を保存し `features.generation.failed` を発行する | must | inside |
| `RULE-FE-009` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: feature generation
  Rule: 正常入力は時点整合を満たして特徴量を生成する
    Example: 生成成功
      Given market.collected の必須項目が揃っている
      And sourceStatus.jp/us がともに ok である
      And insight_records が targetDate 以前のみである
      When market.collected を受信する
      Then feature_store に特徴量が保存される
      And features.generated が発行される
```

```gherkin
Feature: feature generation
  Rule: 将来情報混入時は失敗する
    Example: collectedAtがtargetDateを超過
      Given market.collected の必須項目が揃っている
      And insight_records に collectedAt > targetDate のレコードが含まれる
      When market.collected を受信する
      Then features.generation.failed が発行される
      And reasonCode は DATA_QUALITY_LEAK_DETECTED になる
```

```gherkin
Feature: feature generation
  Rule: 同一イベントidentifierは重複処理しない
    Example: 重複受信
      Given 同一イベントidentifierが既に処理済みである
      When market.collected を受信する
      Then features.generated は再発行されない
      And features.generation.failed は再発行されない
```

```gherkin
Feature: feature generation
  Rule: 入力不備時は失敗を発行する
    Example: sourceStatusがfailed
      Given market.collected の sourceStatus.jp が failed である
      When market.collected を受信する
      Then features.generation.failed が発行される
      And reasonCode は DEPENDENCY_UNAVAILABLE になる
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-FE-001` | `SCN-FE-001` | `FeatureGeneration` | `market.collected` | `TST-FE-001` |
| `RULE-FE-002` | `SCN-FE-004` | `FeatureGeneration` | `market.collected`, `features.generation.failed` | `TST-FE-002` |
| `RULE-FE-003` | `SCN-FE-002` | `FeatureGeneration` | `features.generation.failed` | `TST-FE-003` |
| `RULE-FE-004` | `SCN-FE-003` | `FeatureDispatch` | `market.collected` | `TST-FE-004` |
| `RULE-FE-005` | `SCN-FE-001` | `FeatureDispatch` | `features.generated` | `TST-FE-005` |
| `RULE-FE-006` | `SCN-FE-001` | `FeatureGeneration` | `features.generated` | `TST-FE-006` |
| `RULE-FE-007` | `SCN-FE-001` | `FeatureGeneration` | `features.generated` | `TST-FE-007` |
| `RULE-FE-008` | `SCN-FE-002` | `FeatureGeneration` | `features.generation.failed` | `TST-FE-008` |
| `RULE-FE-009` | `SCN-FE-009` | `FeatureGeneration` | OpenAPI/AsyncAPI/Domain Model | `TST-FE-009` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `FeatureGeneration` | `FeatureGeneration` | 入力検証・時点整合判定・特徴量生成結果確定 | `feature_runs/{identifier}` | 成功/失敗の単一確定、`featureVersion` 不変 |
| `FeatureDispatch` | `FeatureDispatch` | 発行重複防止と配信状態確定 | `idempotency_keys/{identifier}` | 同一イベントの二重配信禁止 |

#### Aggregate詳細: `FeatureGeneration`

- root: `FeatureGeneration`
- 参照先集約: `FeatureDispatch`（`identifier` 参照のみ）
- 生成コマンド: `StartFeatureGeneration`
- 更新コマンド: `ValidateMarketSnapshot`, `LoadInsightSnapshot`, `BuildFeatures`, `RecordGenerationSuccess`, `RecordGenerationFailure`
- 削除/無効化コマンド: `TerminateFeatureGeneration`
- 不変条件:
1. `status=generated` のとき `featureVersion`, `storagePath`, `rowCount`, `featureCount` は必須。
2. `status=failed` のとき `reasonCode` は必須。
3. `insightSnapshot.latestCollectedAt` は `targetDate` を超過しない。
4. `identifier` は不変。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 生成処理識別子（ULID） | `1` |
| `status` | `enum(pending, generated, failed)` | 生成状態 | `1` |
| `market` | `MarketSnapshot` | 入力市場データ要約 | `1` |
| `insight` | `InsightSnapshot` | 結合対象インサイト要約 | `0..1` |
| `featureVersion` | `string` | 特徴量版 | `0..1` |
| `storagePath` | `string` | 出力保存先 | `0..1` |
| `rowCount` | `integer` | 生成行数 | `0..1` |
| `featureCount` | `integer` | 生成列数 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |
| `processedAt` | `datetime` | 処理確定時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `marketSnapshot` | `MarketSnapshot` | 入力イベント正規化結果 | `1` |
| `insightSnapshot` | `InsightSnapshot` | `targetDate` 時点の定性要約 | `0..1` |
| `featureArtifact` | `FeatureArtifact` | 出力特徴量の保存情報 | `0..1` |
| `failureDetail` | `FailureDetail` | 失敗情報 | `0..1` |

#### Aggregate詳細: `FeatureDispatch`

- root: `FeatureDispatch`
- 参照先集約: `FeatureGeneration`（`identifier` 参照のみ）
- 生成コマンド: `StartDispatch`
- 更新コマンド: `MarkDispatched`, `MarkDispatchFailed`
- 削除/無効化コマンド: `TerminateDispatch`
- 不変条件:
1. 同一イベント `identifier` は1回のみ `published` へ遷移できる。
2. `dispatchStatus=failed` のとき `reasonCode` 必須。

#### 4.1.1 Aggregate Rootフィールド定義（FeatureDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子（ULID） | `1` |
| `dispatchStatus` | `enum(pending, published, failed)` | 配信状態 | `1` |
| `publishedEvent` | `enum(features.generated, features.generation.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 配信失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |
| `processedAt` | `datetime` | 配信確定時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（FeatureDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `dispatchDecision` | `DispatchDecision` | 配信結果と理由 | `1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `FeatureGeneration` | `identifier` | `pending -> generated/failed` | `validate`, `joinPointInTime`, `complete`, `fail` |
| `FeatureDispatch` | `identifier` | `pending -> published/failed` | `publish`, `fail` |

#### Entity詳細: `FeatureGeneration`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 生成識別子 | `1` |
| `status` | `enum(pending, generated, failed)` | 生成状態 | `1` |
| `featureVersion` | `string` | 出力特徴量版 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

#### Entity詳細: `FeatureDispatch`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子 | `1` |
| `dispatchStatus` | `enum(pending, published, failed)` | 配信状態 | `1` |
| `publishedEvent` | `enum(features.generated, features.generation.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `MarketSnapshot` | `targetDate`, `storagePath`, `sourceStatus` | 値比較 | immutable |
| `SourceStatus` | `jp`, `us` | 値比較 | immutable |
| `InsightSnapshot` | `recordCount`, `latestCollectedAt`, `filteredByTargetDate` | 値比較 | immutable |
| `FeatureArtifact` | `featureVersion`, `storagePath`, `rowCount`, `featureCount` | 値比較 | immutable |
| `FailureDetail` | `reasonCode`, `detail`, `retryable` | 値比較 | immutable |
| `DispatchDecision` | `dispatchStatus`, `publishedEvent`, `reasonCode` | 値比較 | immutable |

#### Value Object詳細: `MarketSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `targetDate` | `date` | 対象日 | `1` |
| `storagePath` | `string` | 市場データ保存先 | `1` |
| `sourceStatus` | `SourceStatus` | 収集元状態 | `1` |

#### Value Object詳細: `SourceStatus`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `jp` | `enum(ok, failed)` | 国内市場データ状態 | `1` |
| `us` | `enum(ok, failed)` | 米国市場データ状態 | `1` |

#### Value Object詳細: `InsightSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `recordCount` | `integer` | 結合対象インサイト件数 | `1` |
| `latestCollectedAt` | `datetime` | 最大収集時刻 | `0..1` |
| `filteredByTargetDate` | `boolean` | `targetDate` フィルタ適用済みフラグ | `1` |

#### Value Object詳細: `FeatureArtifact`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `featureVersion` | `string` | 出力特徴量版 | `1` |
| `storagePath` | `string` | 出力保存先 | `1` |
| `rowCount` | `integer` | 生成行数 | `1` |
| `featureCount` | `integer` | 生成列数 | `1` |

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
| `publishedEvent` | `enum(features.generated, features.generation.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `PointInTimeJoinPolicy` | domain | 定量/定性の時点整合結合判定 | Firestore/Storageアクセス |
| `FeatureLeakagePolicy` | domain | 将来情報混入検知と失敗理由決定 | IO処理 |
| `FeatureGenerationService` | application | 受信イベントから生成/保存/発行までをオーケストレーション | 業務ルール本体 |
| `FeatureAuditWriter` | application | 監査ログ記録 | 生成判定ロジック |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `FeatureGenerationRepository` | 生成状態永続化 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `FeatureDispatchRepository` | 配信状態永続化 | `Find`, `Persist`, `Terminate` |
| Repository | `MarketDataRepository` | 市場データ参照 | `Find`, `FindByTargetDate` |
| Repository | `InsightRecordRepository` | インサイト参照 | `Search`, `FindByTargetDate` |
| Repository | `FeatureArtifactRepository` | 特徴量保存 | `Persist`, `Find`, `Terminate` |
| Repository | `IdempotencyKeyRepository` | 重複処理防止 | `Find`, `Persist`, `Terminate` |
| Factory | `FeatureGenerationFactory` | 入力イベントから生成集約を作成 | `fromMarketCollectedEvent` |
| Factory | `FeatureDispatchFactory` | 配信集約の作成 | `fromFeatureGeneration` |
| Specification | `MarketPayloadIntegritySpecification` | 入力必須項目判定 | `isSatisfiedBy(market)` |
| Specification | `SourceStatusHealthySpecification` | 収集元状態判定 | `isSatisfiedBy(sourceStatus)` |
| Specification | `PointInTimeConsistencySpecification` | 将来情報混入判定 | `isSatisfiedBy(insightSnapshot)` |

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
| `pending` | `BuildFeatures` | `generated` | 入力必須項目OK + sourceStatus健全 + 時点整合OK + 保存成功 | - |
| `pending` | `BuildFeatures` | `failed` | 入力必須項目不足 | `REQUEST_VALIDATION_FAILED` |
| `pending` | `BuildFeatures` | `failed` | sourceStatus不健全 | `DEPENDENCY_UNAVAILABLE` |
| `pending` | `BuildFeatures` | `failed` | 将来情報リーク検知 | `DATA_QUALITY_LEAK_DETECTED` |
| `pending` | `BuildFeatures` | `failed` | スキーマ不正 | `DATA_SCHEMA_INVALID` |
| `pending` | `BuildFeatures` | `failed` | 生成処理内部エラー | `FEATURE_GENERATION_FAILED` |
| `generated` | `BuildFeatures` | `generated` | 同一イベントidentifier重複受信 | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `failed` | `BuildFeatures` | `failed` | 終端状態への再実行 | `STATE_CONFLICT` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-FE-001` | `FeatureGeneration` | `status=generated` のとき `featureVersion`,`storagePath`,`rowCount`,`featureCount` 必須 | コマンド拒否 |
| `INV-FE-002` | `FeatureGeneration` | `status=failed` のとき `reasonCode` 必須 | コマンド拒否 |
| `INV-FE-003` | `FeatureGeneration` | `insight.latestCollectedAt <= targetDate` | コマンド拒否 |
| `INV-FE-004` | `FeatureDispatch` | 同一イベント `identifier` は1回のみ publish | 冪等扱い |
| `INV-FE-005` | `FeatureGeneration` | `identifier` と `featureVersion` は確定後不変 | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `feature.generation.started` | `FeatureGeneration` | 受信処理開始時 | `identifier`, `targetDate`, `trace` | `identifier` |
| `feature.generation.completed` | `FeatureGeneration` | 生成確定時 | `identifier`, `targetDate`, `featureVersion`, `storagePath`, `trace` | `identifier` |
| `feature.generation.failed` | `FeatureGeneration` | 失敗確定時 | `identifier`, `reasonCode`, `detail`, `trace` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `features.generated` | `signal-generator`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `features.generation.failed` | `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 市場データ受信で特徴量生成開始 | `GenerateFeatures` | なし（イベント駆動） | `market.collected`（受信） | 入力は `MarketCollectedPayload` |
| 特徴量生成成功通知 | `PublishFeaturesGenerated` | なし | `features.generated`（発行） | 保存後に発行 |
| 特徴量生成失敗通知 | `PublishFeaturesGenerationFailed` | なし | `features.generation.failed`（発行） | `reasonCode` 必須 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `FeatureArtifact` | `feature-engineering` | `Cloud Storage:feature_store` | `identifier` 単位 | `trace`, `identifier`, `featureVersion`, `targetDate` |
| `FeatureDispatch` | `feature-engineering` | `Firestore:idempotency_keys` | `identifier` 単位 | `trace`, `identifier`, `processedAt` |
| `FeatureGenerationAudit` | `feature-engineering` | `Cloud Logging` | 別Tx（状態確定後） | `trace`, `identifier`, `result`, `reasonCode` |
| `MarketSnapshot` | `data-collector` | `Cloud Storage:raw_market_data`（参照） | 読み取り専用 | `trace`, `targetDate`, `sourceStatus` |
| `InsightSnapshot` | `insight-collector` | `Firestore:insight_records`（参照） | 読み取り専用 | `trace`, `recordCount`, `latestCollectedAt` |

- 他集約更新は同一Txで行わない。
- 集約間整合は `features.*` イベントで実現する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-FE-001` | acceptance | `RULE-FE-001` | 必須項目欠損時に生成開始しない |
| `TST-FE-002` | acceptance | `RULE-FE-002` | sourceStatus不健全時に `DEPENDENCY_UNAVAILABLE` |
| `TST-FE-003` | invariant | `RULE-FE-003` | `collectedAt > targetDate` で `DATA_QUALITY_LEAK_DETECTED` |
| `TST-FE-004` | idempotency | `RULE-FE-004` | 同一identifier重複で副作用なし |
| `TST-FE-005` | domain event | `RULE-FE-005` | 保存後に `features.generated` 発行 |
| `TST-FE-006` | invariant | `RULE-FE-006` | `featureVersion` 再生成禁止 |
| `TST-FE-007` | contract | `RULE-FE-007` | `features.generated` 必須項目を常に含む |
| `TST-FE-008` | domain event | `RULE-FE-008` | 失敗時に `reasonCode` 付きで `features.generation.failed` 発行 |
| `TST-FE-009` | contract | `RULE-FE-009` | OpenAPI/AsyncAPI/Domain Modelで `identifier` 命名統一 |

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

- `targetDate` 基準の時点整合が保証され、将来情報混入を検知できるか。
- `sourceStatus` 不健全時に安全側で停止できるか。
- `feature_store` 保存とイベント発行順序が保証されるか。
- `features.generated` 必須項目が下流要件と一致しているか。
- Rule→Scenario→Model→Contract→Test のトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/feature-engineering.md`
- `documents/内部設計/services/feature-engineering.md`
- `documents/内部設計/json/feature-engineering.json`
- `documents/外部設計/api/asyncapi.yaml`
- `documents/外部設計/error/error-codes.json`
