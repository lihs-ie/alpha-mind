# audit-log ドメインモデル設計

最終更新日: 2026-02-28
対象Bounded Context: `audit-log`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: 全業務イベントを監査可能な共通形式へ正規化し、`audit_logs` へ冪等に保存して追跡性を担保する。
- スコープ内:
1. 業務イベント受信時のエンベロープ検証
2. 監査レコード正規化（`result`, `reason`, `payloadSummary`）
3. `audit_logs` / `idempotency_keys` への保存
4. 任意の `audit.recorded` 発行
- スコープ外:
1. 業務意思決定（注文承認、昇格判定など）
2. 画面表示ロジック（`bff` が担当）
3. 各サービス固有の業務ルール評価

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Audit Trail Management`
- ミッション: 業務イベントを時系列追跡可能な監査証跡へ変換し、障害調査と運用監査の基盤を提供する。
- コア/支援/汎用サブドメイン区分: `generic`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Source Event | 監査対象の元イベント（CloudEvents） | AsyncAPI `*.yaml` | 監査記録と同一視しない |
| Audit Record | 正規化済み監査エントリ | `Firestore:audit_logs` | 業務状態の正本として使わない |
| Payload Summary | 監査保存向けに要約したpayload | `payloadSummary` | 元payload全量の永続化を強制しない |
| Audit Publication | 任意の `audit.recorded` 通知 | AsyncAPI | 保存前に発行しない |
| Duplicate Event | 同一 `identifier` の再受信 | `idempotency_keys` | 副作用を再実行しない |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `data-collector` | Upstream (`Customer-Supplier`) | `market.*` | 共通エンベロープを `SourceEventSnapshot` に正規化 |
| `feature-engineering` | Upstream (`Customer-Supplier`) | `features.*` | `result/reason` を共通監査語彙へ変換 |
| `signal-generator` | Upstream (`Customer-Supplier`) | `signal.*` | 失敗時 `payload.reasonCode` を `reason` へ写像 |
| `portfolio-planner` | Upstream (`Customer-Supplier`) | `orders.proposed`, `orders.proposal.failed` | 成功/失敗を `result` に正規化 |
| `risk-guard` | Upstream (`Customer-Supplier`) | `orders.approved`, `orders.rejected` | `reasonCode/actionReasonCode` を優先順位で正規化 |
| `execution` | Upstream (`Customer-Supplier`) | `orders.executed`, `orders.execution.failed`, `hypothesis.demo.completed` | 執行結果を監査索引へ正規化 |
| `insight-collector` | Upstream (`Customer-Supplier`) | `insight.*` | 根拠収集結果を要約して保存 |
| `agent-orchestrator` | Upstream (`Customer-Supplier`) | `hypothesis.proposed`, `hypothesis.proposal.failed` | 仮説生成結果を監査形式へ正規化 |
| `hypothesis-lab` | Upstream (`Customer-Supplier`) | `hypothesis.backtested`, `hypothesis.promoted`, `hypothesis.rejected` | 昇格/却下の監査項目を保存 |
| `bff` | Downstream (`OHS+PL`) | `GET /audit`, `GET /audit/{identifier}` | `audit_logs` から表示用DTOへ変換 |
| `audit-view` | Downstream (`OHS+PL`) | `audit.recorded`（任意） | 保存済み監査レコードのみ通知 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-AU-001` | 受信イベントは `identifier`, `eventType`, `occurredAt`, `trace`, `payload` を必須とする | must | inside |
| `RULE-AU-002` | 同一イベント `identifier` は1回のみ監査保存する（冪等） | must | outside |
| `RULE-AU-003` | `result` は `eventType` と `payload.reasonCode` から正規化する（`*.failed` は `failed`） | must | inside |
| `RULE-AU-004` | `reason` は `reasonCode` -> `actionReasonCode` -> `reason` の優先順で決定する | must | inside |
| `RULE-AU-005` | 正規化成功時は `audit_logs` 保存後にのみ `audit.recorded` を発行可能とする | must | inside |
| `RULE-AU-006` | スキーマ不正（`DATA_SCHEMA_INVALID`）は非再試行とし、副作用を発生させない | must | inside |
| `RULE-AU-007` | 永続化失敗時は `AUDIT_WRITE_FAILED` として再試行対象にする | must | outside |
| `RULE-AU-008` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: audit recording
  Rule: 正常な業務イベントは監査保存される
    Example: orders.executed を記録
      Given 必須属性を持つ orders.executed を受信する
      And identifier が未処理である
      When audit-log がイベントを処理する
      Then audit_logs に監査レコードが1件保存される
      And result は success になる
```

```gherkin
Feature: audit recording
  Rule: 同一identifierは重複保存しない
    Example: duplicate ingest
      Given 同一identifierのイベントが既に処理済みである
      When 同じイベントを再受信する
      Then audit_logs の件数は増えない
      And 追加の副作用は発生しない
```

```gherkin
Feature: audit recording
  Rule: スキーマ不正は非再試行で終了する
    Example: trace 欠損イベント
      Given trace が欠損したイベントを受信する
      When audit-log が検証する
      Then 処理は DATA_SCHEMA_INVALID で失敗確定する
      And audit.recorded は発行されない
```

```gherkin
Feature: audit recording
  Rule: 理由は優先順位で正規化する
    Example: reasonCode と actionReasonCode が共存
      Given payload.reasonCode と payload.actionReasonCode を含むイベントを受信する
      When reason を正規化する
      Then reason には reasonCode が採用される
```

```gherkin
Feature: audit recording
  Rule: 識別子命名はidentifierへ統一する
    Example: 契約とドメインモデルの命名整合
      Given OpenAPI/AsyncAPI/Domain Model を突合する
      When 識別子項目を検査する
      Then Id サフィックス項目は存在しない
      And 当該関心の識別子は identifier を使用する
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-AU-001` | `SCN-AU-001` | `AuditRecord` | 全購読イベント | `TST-AU-001` |
| `RULE-AU-002` | `SCN-AU-002` | `AuditIngestion` | 全購読イベント | `TST-AU-002` |
| `RULE-AU-003` | `SCN-AU-001` | `AuditRecord` | `*.failed`, `*.executed`, `*.promoted` | `TST-AU-003` |
| `RULE-AU-004` | `SCN-AU-004` | `AuditRecord` | `orders.rejected`, `hypothesis.promoted` | `TST-AU-004` |
| `RULE-AU-005` | `SCN-AU-001` | `AuditIngestion` | `audit.recorded` | `TST-AU-005` |
| `RULE-AU-006` | `SCN-AU-003` | `AuditRecord` | 全購読イベント | `TST-AU-006` |
| `RULE-AU-007` | `SCN-AU-005` | `AuditIngestion` | Firestore/Logging write | `TST-AU-007` |
| `RULE-AU-008` | `SCN-AU-008` | `AuditRecord` | OpenAPI/AsyncAPI/Domain Model | `TST-AU-008` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `AuditRecord` | `AuditRecord` | 受信イベントの監査正規化と保存内容確定 | `audit_logs/{identifier}` | 必須属性の完全性、`result` 正規化 |
| `AuditIngestion` | `AuditIngestion` | 冪等制御と処理結果確定（通知発行可否を含む） | `idempotency_keys/{identifier}` | 同一identifierの単一副作用、保存成功時のみ publish |

#### Aggregate詳細: `AuditRecord`

- root: `AuditRecord`
- 参照先集約: `AuditIngestion`（`identifier` 参照のみ）
- 生成コマンド: `AcceptSourceEvent`
- 更新コマンド: `NormalizeResult`, `NormalizeReason`, `SummarizePayload`, `MarkRecorded`, `MarkFailed`
- 削除/無効化コマンド: `TerminateRecord`
- 不変条件:
1. `status=recorded` のとき `identifier`, `eventType`, `service`, `result`, `trace`, `occurredAt` は必須。
2. `status=failed` のとき `reasonCode` は `DATA_SCHEMA_INVALID` または `AUDIT_WRITE_FAILED`。
3. `identifier` は生成後不変。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 監査対象イベント識別子（ULID） | `1` |
| `eventType` | `string` | 元イベント種別 | `1` |
| `service` | `string` | 発行元サービス | `1` |
| `result` | `enum(success, failed)` | 正規化した結果 | `1` |
| `trace` | `string` | 横断追跡識別子（ULID） | `1` |
| `occurredAt` | `datetime` | 元イベント発生時刻 | `1` |
| `reason` | `string` | 理由コード/操作理由の正規化値 | `0..1` |
| `payloadSummary` | `map<string, string|number|boolean>` | payload要約 | `0..1` |
| `status` | `enum(pending, recorded, failed)` | 監査記録処理状態 | `1` |
| `reasonCode` | `enum(ReasonCode)` | 監査処理失敗理由 | `0..1` |
| `recordedAt` | `datetime` | 監査保存完了時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `sourceEventSnapshot` | `SourceEventSnapshot` | 入力イベントの正規化スナップショット | `1` |
| `resultNormalization` | `ResultNormalization` | `result/reason` の正規化結果 | `1` |
| `payloadDigest` | `PayloadDigest` | payload要約情報 | `0..1` |

#### Aggregate詳細: `AuditIngestion`

- root: `AuditIngestion`
- 参照先集約: `AuditRecord`（`identifier` 参照のみ）
- 生成コマンド: `StartIngestion`
- 更新コマンド: `MarkProcessed`, `MarkFailed`
- 削除/無効化コマンド: `TerminateIngestion`
- 不変条件:
1. 同一 `identifier` は1回のみ `processed=true` へ遷移。
2. `processed=true` のとき `processedAt` は必須。

#### 4.1.1 Aggregate Rootフィールド定義（AuditIngestion）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子（ULID） | `1` |
| `processed` | `boolean` | 処理済みフラグ | `1` |
| `processedAt` | `datetime` | 処理完了時刻 | `0..1` |
| `trace` | `string` | トレース識別子（ULID） | `1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗時理由 | `0..1` |

#### 4.1.2 集約内要素の保持（AuditIngestion）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `dispatchDecision` | `DispatchDecision` | `audit.recorded` 発行判定 | `0..1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `AuditRecord` | `identifier` | `pending -> recorded/failed` | `normalize`, `record`, `fail` |
| `AuditIngestion` | `identifier` | `new -> processed/failed` | `checkIdempotency`, `markProcessed`, `markFailed`, `publishAuditRecorded` |

#### Entity詳細: `AuditRecord`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 監査対象イベント識別子 | `1` |
| `eventType` | `string` | 元イベント種別 | `1` |
| `service` | `string` | 発行元サービス | `1` |
| `result` | `enum(success, failed)` | 正規化結果 | `1` |
| `reason` | `string` | 正規化理由 | `0..1` |
| `trace` | `string` | トレース識別子（ULID） | `1` |

#### Entity詳細: `AuditIngestion`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 入力イベント識別子 | `1` |
| `processed` | `boolean` | 冪等処理状態 | `1` |
| `processedAt` | `datetime` | 処理時刻 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `SourceEventSnapshot` | `identifier`, `eventType`, `occurredAt`, `trace`, `payload` | 値比較 | immutable |
| `ResultNormalization` | `result`, `reason`, `reasonSource` | 値比較 | immutable |
| `PayloadDigest` | `fieldCount`, `topLevelKeys`, `summary` | 値比較 | immutable |
| `DispatchDecision` | `shouldPublish`, `targetEventType`, `reasonCode` | 値比較 | immutable |

#### Value Object詳細: `SourceEventSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 元イベント識別子（ULID） | `1` |
| `eventType` | `string` | 元イベント種別 | `1` |
| `occurredAt` | `datetime` | 発生時刻 | `1` |
| `trace` | `string` | トレース識別子（ULID） | `1` |
| `payload` | `object` | 元payload | `1` |

#### Value Object詳細: `ResultNormalization`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `result` | `enum(success, failed)` | 正規化結果 | `1` |
| `reason` | `string` | 正規化理由 | `0..1` |
| `reasonSource` | `enum(reasonCode, actionReasonCode, reason, none)` | 理由の採用元 | `1` |

#### Value Object詳細: `PayloadDigest`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `fieldCount` | `integer` | payloadトップレベル項目数 | `1` |
| `topLevelKeys` | `array<string>` | 保存対象キー一覧 | `0..n` |
| `summary` | `map<string, string|number|boolean>` | 表示向け要約 | `1` |

#### Value Object詳細: `DispatchDecision`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `shouldPublish` | `boolean` | 発行可否 | `1` |
| `targetEventType` | `enum(audit.recorded)` | 発行先イベント | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 発行不可理由 | `0..1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `AuditNormalizationPolicy` | domain | `result/reason/payloadSummary` の正規化 | Firestore/Logging 直接アクセス |
| `AuditIngestionPolicy` | domain | 必須属性検証と冪等判定 | 外部IO |
| `AuditRecordService` | application | 受信から保存・再試行判断までのオーケストレーション | 業務ルール本体 |
| `AuditNotificationService` | application | `audit.recorded` 発行制御 | 正規化ルール本体 |
| `AuditArchiveWriter` | application | Cloud Logging への長期保存 | 判定ロジック |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `AuditRecordRepository` | 監査レコード永続化 | `Find`, `FindByEventType`, `FindByTrace`, `Search`, `Persist`, `Terminate` |
| Repository | `AuditIngestionRepository` | 冪等状態永続化 | `Find`, `Persist`, `Terminate` |
| Repository | `AuditArchiveRepository` | Cloud Logging への保存 | `Persist` |
| Factory | `AuditRecordFactory` | 受信イベントから監査レコード生成 | `fromSourceEvent` |
| Specification | `SourceEventEnvelopeSpecification` | 必須属性検証 | `isSatisfiedBy(sourceEvent)` |
| Specification | `ReasonPrioritySpecification` | 理由優先順位決定 | `isSatisfiedBy(payload)` |
| Specification | `PublicationEligibilitySpecification` | `audit.recorded` 発行可否判定 | `isSatisfiedBy(auditRecord)` |

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

| Aggregate | 現在状態 | コマンド | 次状態 | ガード条件 | 失敗時reasonCode |
|---|---|---|---|---|---|
| `AuditIngestion` | `new` | `RecordAudit` | `processed` | エンベロープ必須属性OK + 未処理identifier + 保存成功 | - |
| `AuditRecord` | `pending` | `RecordAudit` | `recorded` | 正規化成功 + 保存成功 | - |
| `AuditRecord` | `pending` | `RecordAudit` | `failed` | 必須属性欠損 | `DATA_SCHEMA_INVALID` |
| `AuditRecord` | `pending` | `RecordAudit` | `failed` | 保存失敗 | `AUDIT_WRITE_FAILED` |
| `AuditIngestion` | `processed` | `RecordAudit` | `processed` | 同一identifier重複受信 | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `AuditIngestion` | `failed` | `RecordAudit` | `failed` | 非再試行エラー（`DATA_SCHEMA_INVALID`） | `DATA_SCHEMA_INVALID` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-AU-001` | `AuditRecord` | `status=recorded` のとき必須属性をすべて保持 | コマンド拒否 |
| `INV-AU-002` | `AuditIngestion` | 同一 `identifier` は1回のみ副作用実行 | 冪等扱い |
| `INV-AU-003` | `AuditRecord` | `result=failed` のとき `reason` または `reasonCode` を保持 | コマンド拒否 |
| `INV-AU-004` | `AuditIngestion` | `dispatchDecision.shouldPublish=true` は `AuditRecord.status=recorded` のときのみ | コマンド拒否 |
| `INV-AU-005` | `AuditRecord` | `identifier` は生成後不変 | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `audit.record.accepted` | `AuditRecord` | 必須属性検証通過時 | `identifier`, `eventType`, `trace` | `identifier` |
| `audit.record.persisted` | `AuditRecord` | Firestore保存確定時 | `identifier`, `eventType`, `service`, `result`, `trace` | `identifier` |
| `audit.record.persistence.failed` | `AuditRecord` | 保存失敗確定時 | `identifier`, `reasonCode`, `trace` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `audit.recorded` | `audit-view`（任意） | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 業務イベント監査記録 | `RecordAuditFromSourceEvent` | なし（イベント駆動） | `market.*`, `features.*`, `signal.*`, `orders.*`, `operation.kill_switch.changed`, `insight.*`, `hypothesis.*`（受信） | 受信対象は `内部設計/services/audit-log.md` を正本 |
| 監査記録通知（任意） | `PublishAuditRecorded` | なし | `audit.recorded`（発行） | 保存成功時のみ |
| 監査一覧参照 | `QueryAuditLogs` | `GET /audit` | なし | BFFが `audit_logs` を参照 |
| 監査詳細参照 | `QueryAuditLogByIdentifier` | `GET /audit/{identifier}` | なし | BFFが `audit_logs/{identifier}` を参照 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `AuditRecord` | `audit-log` | `Firestore:audit_logs` | `identifier` 単位 | `trace`, `identifier`, `eventType`, `service`, `result`, `reason` |
| `AuditIngestion` | `audit-log` | `Firestore:idempotency_keys` | `identifier` 単位 | `trace`, `identifier`, `processedAt` |
| `AuditArchive` | `audit-log` | `Cloud Logging` | 別Tx（保存確定後） | `trace`, `identifier`, `eventType`, `payloadSummary` |
- 他集約更新は同一Txで行わない。
- 集約間整合は `audit.recorded` と `idempotency_keys` で実現する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-AU-001` | acceptance | `RULE-AU-001` | 必須属性欠損時に `DATA_SCHEMA_INVALID` で拒否 |
| `TST-AU-002` | idempotency | `RULE-AU-002` | 同一identifier重複で保存件数増加なし |
| `TST-AU-003` | invariant | `RULE-AU-003` | `*.failed` を `result=failed` へ正規化 |
| `TST-AU-004` | acceptance | `RULE-AU-004` | `reasonCode` 優先で `reason` が決定される |
| `TST-AU-005` | domain event | `RULE-AU-005` | 保存成功時のみ `audit.recorded` 発行 |
| `TST-AU-006` | acceptance | `RULE-AU-006` | スキーマ不正は非再試行で終了 |
| `TST-AU-007` | retry | `RULE-AU-007` | `AUDIT_WRITE_FAILED` は最大3回再試行 |
| `TST-AU-008` | contract | `RULE-AU-008` | OpenAPI/AsyncAPI/Domain Modelで `identifier` 命名統一 |

- 受け入れ: Gherkinの `Given/When/Then`
- ドメイン: 不変条件・状態遷移・イベント発行
- 契約: OpenAPI/AsyncAPI schema検証 + サンプル検証

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

- 受信イベントの必須属性検証が fail-closed になっているか。
- 冪等性（`idempotency_keys/{identifier}`）で重複副作用を確実に防げるか。
- `reason` 正規化の優先順位が `reasonCode` / `actionReasonCode` 方針と矛盾しないか。
- Firestore保存と `audit.recorded` 発行順序が保証されるか。
- Rule→Scenario→Model→Contract→Test のトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/audit-log.md`
- `documents/内部設計/services/audit-log.md`
- `documents/内部設計/json/audit-log.json`
- `documents/外部設計/api/openapi.yaml`
- `documents/外部設計/api/asyncapi.yaml`
- `documents/外部設計/db/firestore設計.md`
- `documents/外部設計/error/error-codes.json`
