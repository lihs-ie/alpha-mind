# frontend-sol ドメインモデル設計

最終更新日: 2026-03-01
対象Bounded Context: `frontend-sol`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: BFF契約を前提に、画面コンテキストごとの振る舞いをDDD/オニオンアーキテクチャで定義する。
- スコープ内:
1. 認証状態、権限、kill switch、画面遷移を含むUIドメインモデル
2. 画面操作（承認/却下/再送/昇格等）のコマンド意図モデル
3. BFFレスポンスの画面向け変換（ACL）
- スコープ外:
1. BFF/バックエンドの業務判定ロジック本体
2. 注文・リスク・執行・学習推論の計算ロジック

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Frontend Interaction Context`
- ミッション: 運用者が安全に操作できるUI状態を維持し、BFF契約を画面体験へ整形する。
- コア/支援/汎用サブドメイン区分: `supporting`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Screen Context | 1画面の表示・操作状態の単位 | SCR-001〜SCR-007 | 画面を跨いで状態を書き換えない |
| Command Intent | 更新系UI操作の意図 | approve/reject/retry/promote など | API呼び出し前に必須条件を検証する |
| Read Model Projection | BFFレスポンスをUI表示へ投影したモデル | 一覧/詳細/指標カード | 生レスポンスを直接描画しない |
| Permission Snapshot | 操作時点の権限スナップショット | 操作可否判定 | 画面表示と判定結果を不一致にしない |
| Operation Guard | kill switchや状態遷移条件のUIガード | 注文/実行系操作 | ガード回避の直叩き導線を作らない |
| Identifier | 画面内の識別子 | `identifier` | `id` / `Id` を使わない |
| Trace | 画面操作とバックエンド処理の相関識別子 | 更新系操作 | 更新系で欠落させない |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `Operator` | Upstream (`Customer-Supplier`) | 画面操作 | 操作を `CommandIntent` に正規化 |
| `bff` | Upstream (`OHS+PL`) | OpenAPI（HTTP） | BFF DTO -> `ReadModelProjection`（ACL） |
| `OIDC/JWT Provider` | Upstream (`Separate Ways`) | 認証トークン | claims -> `PermissionSnapshot` |
| `audit-log` | Downstream（間接） | `GET /audit*`（BFF経由） | `AuditListItem` に整形 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-FE-001` | `GET /healthz`, `POST /auth/login` 以外は認証済み状態でのみ操作可能 | must | inside |
| `RULE-FE-002` | 更新系操作は `trace` と対象 `identifier` を保持して送信する | must | inside |
| `RULE-FE-003` | kill switch有効時は発注系操作をUIで無効化する | must | inside |
| `RULE-FE-004` | BFFレスポンスは画面専用モデルへ変換して描画する | must | outside |
| `RULE-FE-005` | 同一操作の多重送信を `submissionIdentifier` で抑止する | must | inside |
| `RULE-FE-006` | 参照系画面操作は状態変更イベントを発行しない | must | inside |
| `RULE-FE-007` | 識別子命名は `identifier` に統一し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: order operation guard
  Rule: kill switch 有効時は承認操作できない
    Example: SCR-003 approve blocked
      Given kill switch が有効
      And PROPOSED の注文が表示されている
      When 運用者が承認ボタンを押す
      Then 承認操作は実行されない
      And 警告メッセージが表示される
```

```gherkin
Feature: command dedup
  Rule: 更新系操作の多重送信を防止する
    Example: retry double click
      Given FAILED の注文詳細を表示している
      When 再送ボタンを短時間で2回押す
      Then BFFへのPOSTは1回だけ送信される
      And 2回目は duplicate としてUIで無害化される
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-FE-001` | `SCN-FE-001` | `UiSession` | 保護API全般 | `TST-FE-001` |
| `RULE-FE-002` | `SCN-FE-002` | `CommandInteraction` | `POST /orders/{identifier}/approve` ほか | `TST-FE-002` |
| `RULE-FE-003` | `SCN-FE-003` | `OperationGuardState` | `POST /operations/kill-switch` | `TST-FE-003` |
| `RULE-FE-004` | `SCN-FE-004` | `ReadModelProjection` | `GET /dashboard/summary`, `GET /orders` ほか | `TST-FE-004` |
| `RULE-FE-005` | `SCN-FE-005` | `CommandInteraction` | 更新系OpenAPI | `TST-FE-005` |
| `RULE-FE-006` | `SCN-FE-006` | `ReadModelProjection` | `GET /audit`, `GET /insights`, `GET /hypotheses` | `TST-FE-006` |
| `RULE-FE-007` | `SCN-FE-007` | `UiSession` | OpenAPI/画面モデル | `TST-FE-007` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `UiSession` | `UiSession` | 認証状態・権限・画面遷移状態の管理 | `in-memory session` | 認証状態と操作可否の整合 |
| `CommandInteraction` | `CommandInteraction` | 更新系操作の意図、送信状態、重複防止 | `in-memory interaction` | 同一送信の単一実行 |
| `ReadModelProjection` | `ReadModelProjection` | BFF応答の画面向け投影 | `view scope` | 生DTO非露出 |

#### Aggregate詳細: `UiSession`

- root: `UiSession`
- 参照先集約: `ReadModelProjection`（`identifier` 参照のみ）
- 生成コマンド: `StartSession`
- 更新コマンド: `Authenticate`, `Authorize`, `NavigateScreen`, `ExpireSession`
- 削除/無効化コマンド: `TerminateSession`
- 不変条件:
1. `authState=unauthenticated` の場合、保護画面へ遷移できない。
2. `currentScreen` は `SCR-000`〜`SCR-007` のみ。
3. `identifier` は生成後不変。

#### 4.1.1 Aggregate Rootフィールド定義（UiSession）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | セッション識別子（ULID） | `1` |
| `user` | `string` | 操作ユーザー識別子 | `0..1` |
| `authState` | `enum(unauthenticated, authenticated, expired)` | 認証状態 | `1` |
| `permissionSnapshot` | `PermissionSnapshot` | 権限スナップショット | `0..1` |
| `currentScreen` | `enum(SCR-000..SCR-007)` | 現在画面 | `1` |
| `trace` | `string` | 直近操作トレース | `0..1` |
| `updatedAt` | `datetime` | 更新時刻 | `1` |

#### 4.1.2 集約内要素の保持（UiSession）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `operationGuardState` | `OperationGuardState` | kill switch 等の操作ガード | `1` |
| `screenContexts` | `List<ScreenContext>` | 画面別状態 | `1..n` |

#### Aggregate詳細: `CommandInteraction`

- root: `CommandInteraction`
- 参照先集約: `UiSession`（`identifier` 参照のみ）
- 生成コマンド: `CreateCommandIntent`
- 更新コマンド: `SubmitCommand`, `AcknowledgeCommand`, `RejectCommand`, `MarkDuplicate`
- 削除/無効化コマンド: `TerminateCommandInteraction`
- 不変条件:
1. `status=submitting` は同一 `submissionIdentifier` で1件のみ。
2. `status=accepted/rejected` では `responseCode` 必須。
3. 更新系送信では `trace` と対象 `identifier` を保持する。

#### 4.1.1 Aggregate Rootフィールド定義（CommandInteraction）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 画面操作識別子（ULID） | `1` |
| `submissionIdentifier` | `string` | 重複抑止キー（ULID） | `1` |
| `trace` | `string` | 操作トレース（ULID） | `1` |
| `commandType` | `enum(approve,reject,retry,runCycle,killSwitch,promote,hypothesize,adopt)` | 操作種別 | `1` |
| `target` | `CommandTarget` | 操作対象（注文/仮説など） | `0..1` |
| `status` | `enum(draft,submitting,accepted,rejected,duplicate)` | 送信状態 | `1` |
| `responseCode` | `integer` | BFF応答コード | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `actionReasonCode` | `enum(OperatorActionReasonCode)` | 操作理由コード | `0..1` |

#### Aggregate詳細: `ReadModelProjection`

- root: `ReadModelProjection`
- 参照先集約: なし
- 生成コマンド: `ProjectReadModel`
- 更新コマンド: `RefreshProjection`, `FailProjection`
- 削除/無効化コマンド: `TerminateProjection`
- 不変条件:
1. `status=ready` のとき `items` または `summary` のいずれか必須。
2. 生DTOは保持しない（画面モデルのみ保持）。

#### 4.1.1 Aggregate Rootフィールド定義（ReadModelProjection）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 投影識別子（ULID） | `1` |
| `screen` | `enum(SCR-001,SCR-003,SCR-004,SCR-005,SCR-006,SCR-007)` | 投影対象画面 | `1` |
| `status` | `enum(initial,loading,ready,empty,error,disabled)` | 画面状態 | `1` |
| `items` | `List<ViewItem>` | 一覧表示項目 | `0..n` |
| `summary` | `ViewSummary` | サマリー表示項目 | `0..1` |
| `pagination` | `Pagination` | ページング情報 | `0..1` |
| `updatedAt` | `datetime` | 更新時刻 | `1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `ScreenContext` | `identifier` | `initial -> loading -> ready/error` | `startLoading`, `applyProjection`, `fail` |
| `CommandIntent` | `identifier` | `draft -> submitting -> accepted/rejected/duplicate` | `validate`, `submit`, `acknowledge`, `reject`, `dedupe` |
| `ProjectionItem` | `identifier` | `created -> rendered -> stale` | `render`, `markStale` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `PermissionSnapshot` | `role`, `permissions` | 値比較 | immutable |
| `OperationGuardState` | `killSwitch`, `disabledActions` | 値比較 | immutable |
| `QueryCriteria` | `from`, `to`, `status`, `cursor`, `limit` | 値比較 | immutable |
| `ApiProblem` | `status`, `reasonCode`, `message` | 値比較 | immutable |
| `Pagination` | `cursor`, `limit`, `hasNext` | 値比較 | immutable |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `OperationAvailabilityPolicy` | domain | kill switch/権限/状態に基づく操作可否判定 | HTTP呼び出し |
| `CommandDeduplicationPolicy` | domain | `submissionIdentifier` の重複判定 | UI描画 |
| `DashboardQueryService` | application | SCR-001向け取得/投影フロー | 業務判定ロジック |
| `OrdersCommandService` | application | SCR-003更新系操作の実行管理 | 判定ルール本体 |
| `HypothesisWorkflowService` | application | SCR-007操作の実行管理 | バックテスト計算 |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `UiSessionRepository` | `UiSession` の保持 | `Find`, `Persist`, `Terminate` |
| Repository | `ProjectionRepository` | 画面投影状態の保持 | `FindByScreen`, `Persist`, `Terminate` |
| Factory | `CommandIntentFactory` | 送信意図の生成 | `create(commandType, target)` |
| Specification | `ActionAllowedSpecification` | 操作可否判定 | `isSatisfiedBy(session, intent)` |

#### 4.5.1 interface signature

| 役割 | 命名規則 | 用途 |
| - | - | - |
| 永続化 | Persist | UI状態を保存する |
| 削除 | Terminate | UI状態を破棄する |
| Identifierによる単一取得 | Find | 識別子で単体取得する |
| Identifier以外の要素による単一取得 | FindBy{XXX} | 画面や種別で単体取得する |
| 複数取得 | Search | 条件で複数取得する |

## 5. 状態遷移と不変条件

### 5.1 状態遷移

| 現在状態 | コマンド | 次状態 | ガード条件 | 失敗時reasonCode |
|---|---|---|---|---|
| `unauthenticated` | `Authenticate` | `authenticated` | JWT有効 | `AUTH_UNAUTHORIZED` |
| `authenticated` | `ExpireSession` | `expired` | token期限切れ | `AUTH_UNAUTHORIZED` |
| `draft` | `SubmitCommand` | `submitting` | `ActionAllowedSpecification` が真 | `OPERATION_NOT_ALLOWED` |
| `submitting` | `AcknowledgeCommand` | `accepted` | BFF 2xx | - |
| `submitting` | `RejectCommand` | `rejected` | BFF 4xx/5xx | `ReasonCode` |
| `submitting` | `MarkDuplicate` | `duplicate` | 同一 `submissionIdentifier` 検出 | `DUPLICATE_COMMAND` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-FE-001` | `UiSession` | `authState=unauthenticated` 時は保護画面へ遷移不可 | 画面遷移拒否 |
| `INV-FE-002` | `CommandInteraction` | 更新系送信時は `trace` と対象 `identifier` 必須 | 送信拒否 |
| `INV-FE-003` | `CommandInteraction` | 同一 `submissionIdentifier` の送信は1回のみ | duplicate扱い |
| `INV-FE-004` | `ReadModelProjection` | 生DTOを直接保持しない | 投影処理失敗 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `ui.command.submitted` | `CommandInteraction` | 送信開始時 | `commandType`, `trace`, `target` | `submissionIdentifier` |
| `ui.command.completed` | `CommandInteraction` | 応答確定時 | `status`, `responseCode`, `reasonCode` | `submissionIdentifier` |
| `ui.projection.refreshed` | `ReadModelProjection` | 投影更新時 | `screen`, `status`, `itemCount` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| なし（frontendはHTTPクライアントとしてBFFへ同期要求） | - | OpenAPI | request/response | UI再試行ポリシー |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| ダッシュボード表示 | `LoadDashboardSummary` | `GET /dashboard/summary` | なし | SCR-001 |
| 手動サイクル実行 | `RunCycle` | `POST /commands/run-cycle` | なし | SCR-001 |
| 注文承認 | `ApproveOrder` | `POST /orders/{identifier}/approve` | なし | SCR-003 |
| 注文却下 | `RejectOrder` | `POST /orders/{identifier}/reject` | なし | SCR-003 |
| 監査一覧表示 | `QueryAuditLogs` | `GET /audit` | なし | SCR-004 |
| モデル昇格 | `ApproveModel` | `POST /models/validation/{modelVersion}/approve` | なし | SCR-005 |
| インサイト仮説化 | `HypothesizeInsight` | `POST /insights/{identifier}/hypothesize` | なし | SCR-006 |
| 仮説昇格申請 | `PromoteHypothesis` | `POST /hypotheses/{identifier}/promote` | なし | SCR-007 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `UiSession` | `frontend-sol` | in-memory / secure storage | 単一セッション更新 | `trace`, `user`, `screen` |
| `CommandInteraction` | `frontend-sol` | in-memory | 単一操作更新 | `trace`, `identifier`, `action` |
| `ReadModelProjection` | `frontend-sol` | in-memory cache | 単一画面更新 | `trace`, `screen`, `result` |

- BFFをSystem of Recordとし、フロント側永続はキャッシュ用途に限定する。
- 画面間の整合は `trace` を軸に再取得で収束させる。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-FE-001` | acceptance | `RULE-FE-001` | 未認証時リダイレクト |
| `TST-FE-002` | acceptance | `RULE-FE-002` | 更新系送信に `trace`/`identifier` が含まれる |
| `TST-FE-003` | domain | `RULE-FE-003` | kill switch時に操作不可 |
| `TST-FE-004` | contract | `RULE-FE-004` | BFF DTO -> ViewModel 変換整合 |
| `TST-FE-005` | idempotency | `RULE-FE-005` | 多重クリックで単一送信 |
| `TST-FE-006` | acceptance | `RULE-FE-006` | 参照系で更新イベントなし |
| `TST-FE-007` | contract | `RULE-FE-007` | `identifier` 命名統一 |

## 10. 実装規約（このプロジェクト向け）

- `identifier` 命名規約を frontend ドメインにも適用する（`Id` 禁止）。
- 当該関心ごとの識別子は `identifier`、他関心の識別子は `{entity}` を使う。
- `trace` は更新系操作で必須とし、監査可能な形で保持する。
- BFF契約は上流公開言語として扱い、frontend側はACLで表示モデルへ変換する。

## 11. オニオンアーキテクチャ適用

| 層 | 主要要素 | 依存方向 |
|---|---|---|
| Domain | Aggregate, Entity, Value Object, Policy | 内向きのみ |
| Application | `*QueryService`, `*CommandService` | Domain に依存 |
| Interface Adapters | ルート定義、Presenter、ViewModel Mapper | Application に依存 |
| Infrastructure | BFF API Client, Storage, Telemetry | Interface/Application の Port 実装 |

- 外側から内側への一方向依存を維持する。
- UIフレームワーク（Sol/MoonBit）の詳細は Interface Adapters 層に閉じ込める。

## 12. レビュー観点

- 画面コンテキストと業務コンテキストが混線していないか。
- BFF契約変更時にACLで吸収できるか。
- kill switch/認可/重複送信防止の安全要件がUIで担保されるか。
- Rule -> Scenario -> Model -> Contract -> Test のトレースが維持されているか。
