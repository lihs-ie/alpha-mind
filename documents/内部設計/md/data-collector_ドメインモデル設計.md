# data-collector ドメインモデル設計

最終更新日: 2026-02-28
対象Bounded Context: `data-collector`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: `market.collect.requested` を受けて市場データを収集・正規化・保存し、`market.collected` / `market.collect.failed` を整合的に発行する。
- スコープ内:
1. 収集要求イベントの入力検証
2. 日米市場データと逆日歩データの収集・正規化
3. 収集結果保存と `sourceStatus` 確定
4. 冪等性制御と監査保存
- スコープ外:
1. 特徴量生成（`feature-engineering`）
2. シグナル生成（`signal-generator`）
3. 注文生成・執行（`portfolio-planner` / `risk-guard` / `execution`）

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Market Intake`
- ミッション: 収集要求を可観測かつ再現可能な市場データスナップショットへ変換し、下流処理の入力を安定供給する。
- コア/支援/汎用サブドメイン区分: `supporting`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Collect Request | `market.collect.requested` の収集要求 | AsyncAPI payload | `targetDate` 欠損のまま収集しない |
| Market Snapshot | 正規化後の市場データ保存結果 | `Cloud Storage:raw_market_data` | 保存前に成功イベントを発行しない |
| Source Status | 収集ソース状態（`jp`, `us`） | `market.collected.payload.sourceStatus` | 不明状態での成功発行禁止 |
| Collection Artifact | 収集データの保存成果物 | `storagePath` | パス不定のままイベント発行禁止 |
| Collection Dispatch | 収集結果イベント発行処理 | `idempotency_keys` | 同一イベントの重複発行禁止 |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `bff` | Upstream (`Customer-Supplier`) | `market.collect.requested` | payload を `CollectionRequestSnapshot` に正規化 |
| `feature-engineering` | Downstream (`OHS+PL`) | `market.collected` | `targetDate`, `storagePath`, `sourceStatus` を必須伝播 |
| `audit-log` | Downstream (`OHS+PL`) | `market.collected`, `market.collect.failed` | `trace`, `identifier`, `reasonCode` を必須伝播 |
| `External Data Providers` | Upstream (`Separate Ways`) | J-Quants / Alpaca / 日商金 | 取得結果を `SourceStatus` と `FailureDetail` に正規化 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-DC-001` | `market.collect.requested` の必須項目（`targetDate`, `requestedBy`）欠損時は収集を開始しない | must | inside |
| `RULE-DC-002` | 収集対象ソースが未承認なら `market.collect.failed`（`COMPLIANCE_SOURCE_UNAPPROVED`）を発行する | must | inside |
| `RULE-DC-003` | 収集完了時は `sourceStatus.jp/us` を必ず設定する | must | inside |
| `RULE-DC-004` | 同一イベント `identifier`（event envelope）は1回のみ処理する | must | outside |
| `RULE-DC-005` | 成功時は `raw_market_data` 保存後にのみ `market.collected` を発行する | must | outside |
| `RULE-DC-006` | `market.collected` は `targetDate`, `storagePath`, `sourceStatus` を必須で含む | must | inside |
| `RULE-DC-007` | ソースタイムアウト/利用不可は `DATA_SOURCE_TIMEOUT` または `DATA_SOURCE_UNAVAILABLE` として失敗確定する | must | inside |
| `RULE-DC-008` | スキーマ不正時は `DATA_SCHEMA_INVALID` を保存し `market.collect.failed` を発行する | must | inside |
| `RULE-DC-009` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: market collection
  Rule: 正常入力で市場データを収集する
    Example: 収集成功
      Given market.collect.requested の必須項目が揃っている
      And 収集対象ソースが承認済みである
      And 日米ソースが取得成功する
      When market.collect.requested を受信する
      Then raw_market_data にデータが保存される
      And market.collected が発行される
```

```gherkin
Feature: market collection
  Rule: ソース未承認時は失敗する
    Example: ソースポリシー違反
      Given 収集対象ソースが未承認である
      When market.collect.requested を受信する
      Then market.collect.failed が発行される
      And reasonCode は COMPLIANCE_SOURCE_UNAPPROVED になる
```

```gherkin
Feature: market collection
  Rule: 同一イベントidentifierは重複処理しない
    Example: 重複受信
      Given 同一イベントidentifierが既に処理済みである
      When market.collect.requested を受信する
      Then market.collected は再発行されない
      And market.collect.failed は再発行されない
```

```gherkin
Feature: market collection
  Rule: ソースタイムアウトは失敗通知する
    Example: jpソースタイムアウト
      Given J-Quants がタイムアウトする
      When market.collect.requested を受信する
      Then market.collect.failed が発行される
      And reasonCode は DATA_SOURCE_TIMEOUT になる
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-DC-001` | `SCN-DC-001` | `MarketCollection` | `market.collect.requested` | `TST-DC-001` |
| `RULE-DC-002` | `SCN-DC-002` | `MarketCollection` | `market.collect.failed` | `TST-DC-002` |
| `RULE-DC-003` | `SCN-DC-001` | `MarketCollection` | `market.collected` | `TST-DC-003` |
| `RULE-DC-004` | `SCN-DC-003` | `CollectionDispatch` | `market.collect.requested` | `TST-DC-004` |
| `RULE-DC-005` | `SCN-DC-001` | `CollectionDispatch` | `market.collected` | `TST-DC-005` |
| `RULE-DC-006` | `SCN-DC-001` | `MarketCollection` | `market.collected` | `TST-DC-006` |
| `RULE-DC-007` | `SCN-DC-004` | `MarketCollection` | `market.collect.failed` | `TST-DC-007` |
| `RULE-DC-008` | `SCN-DC-005` | `MarketCollection` | `market.collect.failed` | `TST-DC-008` |
| `RULE-DC-009` | `SCN-DC-009` | `MarketCollection` | OpenAPI/AsyncAPI/Domain Model | `TST-DC-009` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `MarketCollection` | `MarketCollection` | 入力検証・ソース取得・収集結果確定 | `collection_runs/{identifier}` | 成功/失敗の単一確定、`sourceStatus` 必須 |
| `CollectionDispatch` | `CollectionDispatch` | 発行重複防止と配信状態確定 | `idempotency_keys/{identifier}` | 同一イベントの二重配信禁止 |

#### Aggregate詳細: `MarketCollection`

- root: `MarketCollection`
- 参照先集約: `CollectionDispatch`（`identifier` 参照のみ）
- 生成コマンド: `StartCollection`
- 更新コマンド: `ValidateRequest`, `FetchSourceData`, `NormalizePayload`, `RecordCollectionSuccess`, `RecordCollectionFailure`
- 削除/無効化コマンド: `TerminateCollection`
- 不変条件:
1. `status=collected` のとき `targetDate`, `storagePath`, `sourceStatus` は必須。
2. `status=failed` のとき `reasonCode` は必須。
3. `sourceStatus.jp/us` は `ok|failed` のみ。
4. `identifier` は不変。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 収集処理識別子（ULID） | `1` |
| `status` | `enum(pending, collected, failed)` | 収集状態 | `1` |
| `request` | `CollectionRequestSnapshot` | 収集要求情報 | `1` |
| `targetDate` | `date` | 収集対象日 | `1` |
| `storagePath` | `string` | 保存先 | `0..1` |
| `sourceStatus` | `SourceStatus` | 収集元状態 | `0..1` |
| `rowCount` | `integer` | 正規化後件数 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |
| `processedAt` | `datetime` | 処理確定時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `requestSnapshot` | `CollectionRequestSnapshot` | 受信要求の正規化結果 | `1` |
| `sourceStatusSnapshot` | `SourceStatus` | ソース収集結果 | `0..1` |
| `collectedArtifact` | `CollectedArtifact` | 保存成果物 | `0..1` |
| `failureDetail` | `FailureDetail` | 失敗情報 | `0..1` |

#### Aggregate詳細: `CollectionDispatch`

- root: `CollectionDispatch`
- 参照先集約: `MarketCollection`（`identifier` 参照のみ）
- 生成コマンド: `StartDispatch`
- 更新コマンド: `MarkDispatched`, `MarkDispatchFailed`
- 削除/無効化コマンド: `TerminateDispatch`
- 不変条件:
1. 同一イベント `identifier` は1回のみ `published` へ遷移できる。
2. `dispatchStatus=failed` のとき `reasonCode` 必須。

#### 4.1.1 Aggregate Rootフィールド定義（CollectionDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子（ULID） | `1` |
| `dispatchStatus` | `enum(pending, published, failed)` | 配信状態 | `1` |
| `publishedEvent` | `enum(market.collected, market.collect.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 配信失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |
| `processedAt` | `datetime` | 配信確定時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（CollectionDispatch）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `dispatchDecision` | `DispatchDecision` | 配信結果と理由 | `1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `MarketCollection` | `identifier` | `pending -> collected/failed` | `validateRequest`, `collect`, `complete`, `fail` |
| `CollectionDispatch` | `identifier` | `pending -> published/failed` | `publish`, `fail` |

#### Entity詳細: `MarketCollection`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 収集識別子 | `1` |
| `status` | `enum(pending, collected, failed)` | 収集状態 | `1` |
| `storagePath` | `string` | 保存先 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

#### Entity詳細: `CollectionDispatch`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子 | `1` |
| `dispatchStatus` | `enum(pending, published, failed)` | 配信状態 | `1` |
| `publishedEvent` | `enum(market.collected, market.collect.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `CollectionRequestSnapshot` | `targetDate`, `requestedBy`, `mode` | 値比較 | immutable |
| `SourceStatus` | `jp`, `us` | 値比較 | immutable |
| `CollectedArtifact` | `targetDate`, `storagePath`, `sourceStatus`, `rowCount` | 値比較 | immutable |
| `FailureDetail` | `reasonCode`, `detail`, `retryable` | 値比較 | immutable |
| `DispatchDecision` | `dispatchStatus`, `publishedEvent`, `reasonCode` | 値比較 | immutable |

#### Value Object詳細: `CollectionRequestSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `targetDate` | `date` | 収集対象日 | `1` |
| `requestedBy` | `enum(scheduler, user)` | 起動主体 | `1` |
| `mode` | `enum(daily, manual)` | 収集モード | `0..1` |

#### Value Object詳細: `SourceStatus`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `jp` | `enum(ok, failed)` | 国内市場データ状態 | `1` |
| `us` | `enum(ok, failed)` | 米国市場データ状態 | `1` |

#### Value Object詳細: `CollectedArtifact`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `targetDate` | `date` | 対象日 | `1` |
| `storagePath` | `string` | 保存パス | `1` |
| `sourceStatus` | `SourceStatus` | 収集元状態 | `1` |
| `rowCount` | `integer` | 正規化後件数 | `1` |

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
| `publishedEvent` | `enum(market.collected, market.collect.failed)` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `SourcePolicySpecificationService` | domain | 許可ソース判定と違反理由決定 | 外部API呼び出し |
| `CollectionQualityPolicy` | domain | スキーマ整合/欠損検証と失敗理由決定 | IO処理 |
| `MarketCollectionService` | application | 受信イベントから収集/保存/発行までをオーケストレーション | 業務ルール本体 |
| `CollectionAuditWriter` | application | 監査ログ記録 | 収集判定ロジック |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `MarketCollectionRepository` | 収集状態永続化 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `CollectionDispatchRepository` | 配信状態永続化 | `Find`, `Persist`, `Terminate` |
| Repository | `RawMarketDataRepository` | 収集データ保存 | `Persist`, `Find`, `FindByTargetDate` |
| Repository | `IdempotencyKeyRepository` | 重複処理防止 | `Find`, `Persist`, `Terminate` |
| Factory | `MarketCollectionFactory` | 入力イベントから収集集約を作成 | `fromCollectRequestedEvent` |
| Factory | `CollectionDispatchFactory` | 配信集約の作成 | `fromMarketCollection` |
| Specification | `CollectRequestIntegritySpecification` | 入力必須項目判定 | `isSatisfiedBy(request)` |
| Specification | `ApprovedSourceSpecification` | 許可ソース判定 | `isSatisfiedBy(source)` |
| Specification | `MarketSchemaIntegritySpecification` | 正規化スキーマ判定 | `isSatisfiedBy(dataset)` |

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
| `pending` | `CollectMarketData` | `collected` | 入力必須項目OK + ソース承認済み + スキーマ整合 + 保存成功 | - |
| `pending` | `CollectMarketData` | `failed` | 入力不正 | `REQUEST_VALIDATION_FAILED` |
| `pending` | `CollectMarketData` | `failed` | 未承認ソース | `COMPLIANCE_SOURCE_UNAPPROVED` |
| `pending` | `CollectMarketData` | `failed` | ソースタイムアウト | `DATA_SOURCE_TIMEOUT` |
| `pending` | `CollectMarketData` | `failed` | ソース利用不可 | `DATA_SOURCE_UNAVAILABLE` |
| `pending` | `CollectMarketData` | `failed` | スキーマ不正 | `DATA_SCHEMA_INVALID` |
| `collected` | `CollectMarketData` | `collected` | 同一イベントidentifier重複受信 | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `failed` | `CollectMarketData` | `failed` | 終端状態への再実行 | `STATE_CONFLICT` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-DC-001` | `MarketCollection` | `status=collected` のとき `targetDate`,`storagePath`,`sourceStatus` 必須 | コマンド拒否 |
| `INV-DC-002` | `MarketCollection` | `status=failed` のとき `reasonCode` 必須 | コマンド拒否 |
| `INV-DC-003` | `MarketCollection` | `sourceStatus.jp/us` は `ok|failed` のみ | コマンド拒否 |
| `INV-DC-004` | `CollectionDispatch` | 同一イベント `identifier` は1回のみ publish | 冪等扱い |
| `INV-DC-005` | `MarketCollection` | `identifier` は生成後不変 | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `market.collection.started` | `MarketCollection` | 受信処理開始時 | `identifier`, `targetDate`, `trace` | `identifier` |
| `market.collection.completed` | `MarketCollection` | 収集確定時 | `identifier`, `targetDate`, `storagePath`, `trace` | `identifier` |
| `market.collection.failed` | `MarketCollection` | 失敗確定時 | `identifier`, `reasonCode`, `detail`, `trace` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `market.collected` | `feature-engineering`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `market.collect.failed` | `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 収集要求でデータ収集開始 | `CollectMarketData` | なし（イベント駆動） | `market.collect.requested`（受信） | 入力は `MarketCollectRequestedPayload` |
| 収集成功通知 | `PublishMarketCollected` | なし | `market.collected`（発行） | 保存後に発行 |
| 収集失敗通知 | `PublishMarketCollectFailed` | なし | `market.collect.failed`（発行） | `reasonCode` 必須 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `CollectedArtifact` | `data-collector` | `Cloud Storage:raw_market_data` | `identifier` 単位 | `trace`, `identifier`, `targetDate`, `sourceStatus` |
| `CollectionDispatch` | `data-collector` | `Firestore:idempotency_keys` | `identifier` 単位 | `trace`, `identifier`, `processedAt` |
| `CollectionAudit` | `data-collector` | `Firestore:audit_logs` | `identifier` 単位 | `trace`, `identifier`, `result`, `reasonCode` |

- 他集約更新は同一Txで行わない。
- 集約間整合は `market.*` イベントで実現する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-DC-001` | acceptance | `RULE-DC-001` | 入力必須項目欠損時に収集開始しない |
| `TST-DC-002` | acceptance | `RULE-DC-002` | 未承認ソースで `COMPLIANCE_SOURCE_UNAPPROVED` |
| `TST-DC-003` | invariant | `RULE-DC-003` | `sourceStatus.jp/us` の完全性を検証 |
| `TST-DC-004` | idempotency | `RULE-DC-004` | 同一identifier重複で副作用なし |
| `TST-DC-005` | domain event | `RULE-DC-005` | 保存後に `market.collected` 発行 |
| `TST-DC-006` | contract | `RULE-DC-006` | `market.collected` 必須項目を常に含む |
| `TST-DC-007` | acceptance | `RULE-DC-007` | timeout/unavailable を正しい reasonCode へ正規化 |
| `TST-DC-008` | domain event | `RULE-DC-008` | スキーマ不正時に `DATA_SCHEMA_INVALID` 発行 |
| `TST-DC-009` | contract | `RULE-DC-009` | OpenAPI/AsyncAPI/Domain Modelで `identifier` 命名統一 |

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

- `market.collect.requested` の入力不備を安全側に倒せるか。
- `sourceStatus` と `reasonCode` が失敗形態を正しく表現できるか。
- `raw_market_data` 保存とイベント発行順序が保証されるか。
- Rule→Scenario→Model→Contract→Test のトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/data-collector.md`
- `documents/内部設計/services/data-collector.md`
- `documents/内部設計/json/data-collector.json`
- `documents/外部設計/api/asyncapi.yaml`
- `documents/外部設計/error/error-codes.json`
