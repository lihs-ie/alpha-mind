# bff ドメインモデル設計

最終更新日: 2026-02-28
対象Bounded Context: `bff`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: 運用者APIの単一入口として、認証認可・コマンド受付・参照クエリ提供・監査記録を整合的に実行する。
- スコープ内:
1. JWT検証と権限判定
2. 更新系APIのコマンド受付と冪等制御
3. 状態更新/イベント発行の順序保証（更新成功後に発行）
4. 画面向けRead Modelクエリ組み立て
5. `trace`, `identifier`, `user` を含む監査記録
- スコープ外:
1. 市場データ収集・特徴量生成・シグナル生成
2. リスク評価・執行アルゴリズム
3. 仮説のバックテスト・昇格判定本体

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Operator API Gateway`
- ミッション: 運用者操作を安全に受け付け、下流サービスと契約整合した形でコマンド/クエリを中継する。
- コア/支援/汎用サブドメイン区分: `supporting`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Access Decision | リクエストごとの認証認可判定結果 | `audit_logs` | 判定未確定で更新処理を実行しない |
| Command Intake | 更新系APIの受付処理 | `idempotency_keys` | 同一identifierの副作用二重実行を許可しない |
| Read Model Query | 画面向け参照用データ取得 | `orders`, `audit_logs`, `hypothesis_registry` など | 更新系を混在させない |
| Permission Requirement | エンドポイントが要求する権限 | `authz-matrix.json` | ハードコードでの逸脱運用をしない |
| Publish Decision | コマンドに対するイベント発行可否 | AsyncAPI | 永続化前に発行しない |
| Identifier | 識別子 | 全モデル/API/Event | `Id` 表記は禁止 |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `Operator` | Upstream (`Customer-Supplier`) | OpenAPI（HTTP） | 入力を `CommandIntake` / `ReadModelQuery` へ正規化 |
| `OIDC/JWT Provider` | Upstream (`Separate Ways`) | JWT検証 | claims を `AuthClaimsSnapshot` へ写像 |
| `data-collector` | Downstream (`OHS+PL`) | `market.collect.requested` | `CommandIntake` 成功後に発行 |
| `insight-collector` | Downstream (`OHS+PL`) | `insight.collect.requested` | `run-insight-cycle` 受付後に発行 |
| `agent-orchestrator` | Downstream (`OHS+PL`) | `hypothesis.retest.requested` | `retest` 受付後に発行 |
| `risk-guard` | Downstream (`OHS+PL`) | `operation.kill_switch.changed`, `orders.proposed`（retry時）, `POST /internal/orders/{identifier}/approve`, `POST /internal/orders/{identifier}/reject` | 状態更新成功後に発行、承認/却下APIは内部コマンドへ委譲 |
| `audit-log` | Downstream (`OHS+PL`) | `audit_logs` 参照 | `trace` 軸で監査閲覧データへ変換 |
| `Firestore` | Downstream (`Customer-Supplier`) | `operations`, `settings`, `orders`, `hypothesis_registry` 等 | DTO/コマンド入出力へ変換 |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-BFF-001` | `GET /healthz` と `POST /auth/login` を除くすべてのAPIは JWT 必須 | must | inside |
| `RULE-BFF-002` | 権限判定は `authz-matrix.json` を正本にし、不足時は `AUTH_FORBIDDEN` を返す | must | inside |
| `RULE-BFF-003` | 更新系APIは `trace` と `identifier` を採番し監査記録する | must | inside |
| `RULE-BFF-004` | 更新系APIは状態更新成功後にのみ対応イベントを発行する | must | outside |
| `RULE-BFF-005` | 同一コマンド `identifier` は冪等に1回のみ副作用を実行する | must | outside |
| `RULE-BFF-006` | `POST /orders/{identifier}/retry` 受付時は `orders.proposed` を再送イベントとして発行する | must | outside |
| `RULE-BFF-007` | kill switch有効時は承認/再送など対象操作を拒否し `KILL_SWITCH_ENABLED` を返す | must | inside |
| `RULE-BFF-008` | クエリAPIは状態変更を行わず Read Model を返す | must | inside |
| `RULE-BFF-009` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: bff command intake and authorization
  Rule: 権限を満たす更新系APIのみ受け付ける
    Example: run-cycle 受付成功
      Given 有効なJWTと commands:run 権限を持つ運用者
      And kill switch が無効
      When POST /commands/run-cycle を実行する
      Then identifier と trace が採番される
      And market.collect.requested が1回発行される
```

```gherkin
Feature: bff command intake and authorization
  Rule: 権限不足は拒否する
    Example: orders approve の権限不足
      Given 有効なJWTだが orders:approve 権限を持たない運用者
      When POST /orders/{identifier}/approve を実行する
      Then APIは403で応答する
      And reasonCode は AUTH_FORBIDDEN になる
```

```gherkin
Feature: bff command intake and authorization
  Rule: retryは再送イベントを1回のみ発行する
    Example: failed order retry
      Given status が FAILED の注文が存在する
      And 同一identifierが未処理である
      When POST /orders/{identifier}/retry を実行する
      Then orders.proposed が1回発行される
      And 同一identifier再実行時は副作用が発生しない
```

```gherkin
Feature: bff query
  Rule: 参照系APIは状態を変更しない
    Example: hypothesis list query
      Given 有効なJWTと hypotheses:read 権限を持つ運用者
      When GET /hypotheses を実行する
      Then hypothesis_registry から一覧が返る
      And 更新系イベントは発行されない
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-BFF-001` | `SCN-BFF-001` | `AccessDecision` | 全保護API | `TST-BFF-001` |
| `RULE-BFF-002` | `SCN-BFF-002` | `AccessDecision` | 全保護API | `TST-BFF-002` |
| `RULE-BFF-003` | `SCN-BFF-001` | `CommandIntake` | 更新系OpenAPI | `TST-BFF-003` |
| `RULE-BFF-004` | `SCN-BFF-001` | `CommandIntake` | `market.collect.requested`, `operation.kill_switch.changed`, `insight.collect.requested`, `hypothesis.retest.requested`, `orders.proposed` | `TST-BFF-004` |
| `RULE-BFF-005` | `SCN-BFF-003` | `CommandIntake` | 更新系OpenAPI | `TST-BFF-005` |
| `RULE-BFF-006` | `SCN-BFF-003` | `CommandIntake` | `POST /orders/{identifier}/retry`, `orders.proposed` | `TST-BFF-006` |
| `RULE-BFF-007` | `SCN-BFF-004` | `CommandIntake` | `POST /orders/{identifier}/approve`, `POST /orders/{identifier}/retry` | `TST-BFF-007` |
| `RULE-BFF-008` | `SCN-BFF-005` | `ReadModelQuery` | `GET /dashboard/summary`, `GET /orders`, `GET /audit`, `GET /insights`, `GET /hypotheses`, `GET /models/validation` | `TST-BFF-008` |
| `RULE-BFF-009` | `SCN-BFF-009` | `CommandIntake` | OpenAPI/AsyncAPI/Domain Model | `TST-BFF-009` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `AccessDecision` | `AccessDecision` | JWT検証・権限判定・拒否理由確定 | `audit_logs/{identifier}` | 判定結果と理由の一貫性 |
| `CommandIntake` | `CommandIntake` | 更新系コマンド受付、冪等制御、発行可否確定 | `idempotency_keys/{identifier}` | 副作用単一実行、更新後発行 |
| `ReadModelQuery` | `ReadModelQuery` | 参照系クエリの条件検証と結果構成 | `request scope/{identifier}`（非永続） | 非更新、ページング条件整合 |

#### Aggregate詳細: `AccessDecision`

- root: `AccessDecision`
- 参照先集約: `CommandIntake`（`identifier` 参照のみ）
- 生成コマンド: `EvaluateAccess`
- 更新コマンド: `AllowAccess`, `DenyAccess`
- 削除/無効化コマンド: `TerminateAccessDecision`
- 不変条件:
1. `result=deny` のとき `reasonCode` は必須。
2. `result=allow` のとき `permission` は必須。
3. `identifier` は生成後不変。

#### 4.1.1 Aggregate Rootフィールド定義

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 判定識別子（ULID） | `1` |
| `trace` | `string` | トレース識別子（ULID） | `1` |
| `user` | `string` | 操作ユーザー識別子（JWT `sub`） | `1` |
| `email` | `string` | 操作ユーザーメール | `1` |
| `role` | `enum(admin, viewer)` | ユーザーロール | `1` |
| `endpoint` | `EndpointSignature` | 判定対象エンドポイント | `1` |
| `permission` | `string` | 必須権限 | `1` |
| `result` | `enum(allow, deny)` | 判定結果 | `1` |
| `reasonCode` | `enum(ReasonCode)` | 拒否理由 | `0..1` |
| `decidedAt` | `datetime` | 判定時刻 | `1` |

#### 4.1.2 集約内要素の保持（Entity/Value Object）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `claims` | `AuthClaimsSnapshot` | JWT claims の正規化結果 | `1` |
| `permissionRequirement` | `PermissionRequirement` | 必須権限定義 | `1` |

#### Aggregate詳細: `CommandIntake`

- root: `CommandIntake`
- 参照先集約: `AccessDecision`（`identifier` 参照のみ）
- 生成コマンド: `AcceptCommand`
- 更新コマンド: `RejectCommand`, `PublishCommandEvent`, `MarkDuplicate`
- 削除/無効化コマンド: `TerminateCommand`
- 不変条件:
1. `status=published` のとき `publishedEvent` は必須。
2. `status=rejected` のとき `reasonCode` は必須。
3. 同一 `identifier` は1回のみ副作用を実行可能。
4. `identifier` は生成後不変。

#### 4.1.1 Aggregate Rootフィールド定義（CommandIntake）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | コマンド識別子（ULID） | `1` |
| `trace` | `string` | トレース識別子（ULID） | `1` |
| `user` | `string` | 操作ユーザー識別子 | `1` |
| `commandType` | `enum(CommandType)` | 受付コマンド種別 | `1` |
| `target` | `CommandTarget` | 操作対象リソース | `0..1` |
| `status` | `enum(pending, accepted, published, rejected, duplicate)` | 受付状態 | `1` |
| `publishedEvent` | `enum(market.collect.requested, operation.kill_switch.changed, insight.collect.requested, hypothesis.retest.requested, orders.proposed)` | 発行イベント | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 拒否/重複理由 | `0..1` |
| `actionReasonCode` | `enum(OperatorActionReasonCode)` | 運用者操作理由コード | `0..1` |
| `processedAt` | `datetime` | 処理確定時刻 | `0..1` |
| `retryCount` | `integer` | 再試行回数 | `0..1` |

#### 4.1.2 集約内要素の保持（CommandIntake）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `publishDecision` | `PublishDecision` | 発行可否判定 | `1` |
| `auditEnvelope` | `AuditEnvelope` | 監査保存向け共通項目 | `1` |
| `idempotencyRecord` | `IdempotencyRecord` | 重複判定スナップショット | `1` |

#### Aggregate詳細: `ReadModelQuery`

- root: `ReadModelQuery`
- 参照先集約: なし
- 生成コマンド: `StartQuery`
- 更新コマンド: `ValidateQueryCriteria`, `CompleteQuery`, `FailQuery`
- 削除/無効化コマンド: `TerminateQuery`
- 不変条件:
1. `status=completed` のとき `resultCount` は必須。
2. `status=failed` のとき `reasonCode` は必須。
3. 参照系クエリは状態更新イベントを発行しない。

#### 4.1.1 Aggregate Rootフィールド定義（ReadModelQuery）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | クエリ識別子（ULID） | `1` |
| `trace` | `string` | トレース識別子（ULID） | `1` |
| `user` | `string` | 実行ユーザー識別子 | `1` |
| `queryType` | `enum(QueryType)` | 参照クエリ種別 | `1` |
| `criteria` | `QueryCriteria` | 検索条件 | `0..1` |
| `status` | `enum(pending, completed, failed)` | 実行状態 | `1` |
| `resultCount` | `integer` | 取得件数 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |
| `processedAt` | `datetime` | 完了時刻 | `0..1` |

#### 4.1.2 集約内要素の保持（ReadModelQuery）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `pagination` | `Pagination` | ページング情報 | `0..1` |
| `sort` | `SortOrder` | 並び順条件 | `0..1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `AccessDecision` | `identifier` | `pending -> allow/deny` | `verifyJwt`, `resolvePermission`, `allow`, `deny` |
| `CommandIntake` | `identifier` | `pending -> accepted -> published/rejected/duplicate` | `accept`, `publish`, `reject`, `markDuplicate` |
| `ReadModelQuery` | `identifier` | `pending -> completed/failed` | `validateCriteria`, `loadReadModel`, `complete`, `fail` |

#### Entity詳細: `AccessDecision`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 判定識別子（ULID） | `1` |
| `permission` | `string` | 必須権限 | `1` |
| `result` | `enum(allow, deny)` | 判定結果 | `1` |
| `reasonCode` | `enum(ReasonCode)` | 拒否理由 | `0..1` |
| `trace` | `string` | トレース識別子 | `1` |

#### Entity詳細: `CommandIntake`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | コマンド識別子（ULID） | `1` |
| `commandType` | `enum(CommandType)` | 受付種別 | `1` |
| `status` | `enum(pending, accepted, published, rejected, duplicate)` | 処理状態 | `1` |
| `publishedEvent` | `string` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 拒否/重複理由 | `0..1` |

#### Entity詳細: `ReadModelQuery`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | クエリ識別子（ULID） | `1` |
| `queryType` | `enum(QueryType)` | 参照種別 | `1` |
| `status` | `enum(pending, completed, failed)` | 実行状態 | `1` |
| `resultCount` | `integer` | 取得件数 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由 | `0..1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `AuthClaimsSnapshot` | `user`, `email`, `role`, `permissions`, `jti`, `exp` | 値比較 | immutable |
| `PermissionRequirement` | `method`, `path`, `permission` | 値比較 | immutable |
| `EndpointSignature` | `method`, `path` | 値比較 | immutable |
| `CommandTarget` | `resourceType`, `target` | 値比較 | immutable |
| `PublishDecision` | `shouldPublish`, `publishedEvent`, `reasonCode` | 値比較 | immutable |
| `AuditEnvelope` | `trace`, `identifier`, `user`, `actionReasonCode`, `result` | 値比較 | immutable |
| `IdempotencyRecord` | `identifier`, `processed`, `processedAt` | 値比較 | immutable |
| `QueryCriteria` | `status`, `from`, `to`, `eventType`, `symbol` | 値比較 | immutable |
| `Pagination` | `limit`, `cursor` | 値比較 | immutable |
| `SortOrder` | `field`, `direction` | 値比較 | immutable |

#### Value Object詳細: `AuthClaimsSnapshot`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `user` | `string` | JWT `sub` | `1` |
| `email` | `string` | JWT `email` | `1` |
| `role` | `enum(admin, viewer)` | ロール | `1` |
| `permissions` | `array<string>` | 権限配列 | `1..n` |
| `jti` | `string` | トークン識別子 | `1` |
| `exp` | `datetime` | 失効時刻 | `1` |

#### Value Object詳細: `PermissionRequirement`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `method` | `string` | HTTPメソッド | `1` |
| `path` | `string` | パスパターン | `1` |
| `permission` | `string` | 必須権限 | `1` |

#### Value Object詳細: `CommandTarget`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `resourceType` | `string` | 対象リソース種別（order/hypothesis/model など） | `1` |
| `target` | `string` | 対象識別子 | `0..1` |

#### Value Object詳細: `PublishDecision`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `shouldPublish` | `boolean` | 発行可否 | `1` |
| `publishedEvent` | `string` | 発行イベント種別 | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 発行不可理由 | `0..1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `AuthPolicy` | domain | JWT妥当性検証と権限判定 | Firestore/外部IO |
| `CommandEligibilityPolicy` | domain | kill switch・状態遷移前提・入力妥当性判定 | 永続化処理 |
| `IdempotencyPolicy` | domain | `identifier` 重複判定 | 外部発行処理 |
| `BffCommandService` | application | 更新系APIの受付、保存、発行、監査を統合 | 業務ルール本体 |
| `BffQueryService` | application | 参照系APIのクエリ組み立てとDTO整形 | 認可ルール本体 |
| `AuditWriteService` | application | 監査項目の永続化 | 権限判定ロジック |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `AccessDecisionRepository` | 認可判定結果の保存/参照 | `Find`, `Search`, `Persist`, `Terminate` |
| Repository | `CommandIntakeRepository` | コマンド受付状態の保存/参照 | `Find`, `FindByCommandType`, `Search`, `Persist`, `Terminate` |
| Repository | `IdempotencyKeyRepository` | 冪等判定 | `Find`, `Persist`, `Terminate` |
| Repository | `OperationsRepository` | `operations` 参照/更新 | `Find`, `Persist` |
| Repository | `OrdersRepository` | `orders` 参照/更新 | `Find`, `FindByStatus`, `Search`, `Persist` |
| Repository | `ReadModelRepository` | 画面表示向け参照 | `Find`, `Search` |
| Factory | `CommandIntakeFactory` | HTTP入力からコマンド生成 | `fromHttpRequest` |
| Factory | `ReadModelQueryFactory` | HTTPクエリから検索条件生成 | `fromHttpQuery` |
| Specification | `JwtClaimsIntegritySpecification` | 必須claims検証 | `isSatisfiedBy(claims)` |
| Specification | `PermissionGrantSpecification` | 権限保有判定 | `isSatisfiedBy(accessDecision)` |
| Specification | `CommandPublishableSpecification` | 発行可否判定（更新後発行） | `isSatisfiedBy(commandIntake)` |
| Specification | `KillSwitchGuardSpecification` | kill switchガード判定 | `isSatisfiedBy(commandIntake)` |

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
| `pending` | `EvaluateAccess` | `allow` | JWT有効 + 権限充足 | - |
| `pending` | `EvaluateAccess` | `deny` | JWT不正/期限切れ/権限不足 | `AUTH_INVALID_CREDENTIALS` / `AUTH_TOKEN_EXPIRED` / `AUTH_FORBIDDEN` |
| `pending` | `AcceptCommand` | `accepted` | `AccessDecision=allow` + 入力妥当 + kill switch条件充足 | - |
| `pending` | `RejectCommand` | `rejected` | 入力不正または状態不整合 | `REQUEST_VALIDATION_FAILED` / `STATE_CONFLICT` / `OPERATION_NOT_ALLOWED` |
| `pending` | `RejectCommand` | `rejected` | kill switch有効で対象操作不可 | `KILL_SWITCH_ENABLED` |
| `accepted` | `PublishCommandEvent` | `published` | 対象状態の永続化成功 | - |
| `accepted` | `MarkDuplicate` | `duplicate` | 同一identifier処理済み | `IDEMPOTENCY_DUPLICATE_EVENT` |
| `accepted` | `RejectCommand` | `rejected` | 発行失敗確定 | `DEPENDENCY_TIMEOUT` / `DEPENDENCY_UNAVAILABLE` |
| `pending` | `CompleteQuery` | `completed` | クエリ条件妥当 + 参照成功 | - |
| `pending` | `FailQuery` | `failed` | クエリ条件不正/依存失敗 | `REQUEST_VALIDATION_FAILED` / `DEPENDENCY_UNAVAILABLE` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-BFF-001` | `AccessDecision` | `result=deny` のとき `reasonCode` 必須 | コマンド拒否 |
| `INV-BFF-002` | `CommandIntake` | `status=published` のとき `publishedEvent` 必須 | コマンド拒否 |
| `INV-BFF-003` | `CommandIntake` | 同一 `identifier` の副作用は1回のみ | 冪等扱い |
| `INV-BFF-004` | `CommandIntake` | `status=rejected` のとき `reasonCode` 必須 | コマンド拒否 |
| `INV-BFF-005` | `ReadModelQuery` | 参照系クエリは状態更新イベントを発行しない | コマンド拒否 |
| `INV-BFF-006` | `CommandIntake` | `identifier` は生成後不変 | コマンド拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `bff.access.decision.recorded` | `AccessDecision` | 認可判定確定時 | `identifier`, `trace`, `user`, `endpoint`, `result`, `reasonCode` | `identifier` |
| `bff.command.accepted` | `CommandIntake` | 更新系コマンド受付時 | `identifier`, `trace`, `commandType`, `target` | `identifier` |
| `bff.command.rejected` | `CommandIntake` | 更新系コマンド拒否時 | `identifier`, `trace`, `commandType`, `reasonCode` | `identifier` |
| `bff.query.completed` | `ReadModelQuery` | 参照クエリ完了時 | `identifier`, `trace`, `queryType`, `resultCount` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| `market.collect.requested` | `data-collector`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `operation.kill_switch.changed` | `risk-guard`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `insight.collect.requested` | `insight-collector`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `hypothesis.retest.requested` | `agent-orchestrator`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |
| `orders.proposed` | `risk-guard`, `audit-log` | AsyncAPI | eventual consistency | max3 + DLQ |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 運用サイクル起動 | `RunCycle` | `POST /commands/run-cycle` | `market.collect.requested`（発行） | 受付後に発行 |
| インサイト収集起動 | `RunInsightCycle` | `POST /commands/run-insight-cycle` | `insight.collect.requested`（発行） | 受付後に発行 |
| 緊急停止切替 | `ToggleKillSwitch` | `POST /operations/kill-switch` | `operation.kill_switch.changed`（発行） | 状態更新後に発行 |
| 注文承認（手動） | `ApproveOrder` | `POST /orders/{identifier}/approve` | なし（`risk-guard` が `orders.approved` を発行） | `risk-guard` 内部コマンドAPIへ委譲 |
| 注文却下（手動） | `RejectOrder` | `POST /orders/{identifier}/reject` | なし（`risk-guard` が `orders.rejected` を発行） | `risk-guard` 内部コマンドAPIへ委譲 |
| 失敗注文再送 | `RetryOrder` | `POST /orders/{identifier}/retry` | `orders.proposed`（発行） | `FAILED -> PROPOSED` 再送 |
| 仮説再検証要求 | `RetestHypothesis` | `POST /hypotheses/{identifier}/retest` | `hypothesis.retest.requested`（発行） | 受付後に発行 |
| 参照系取得 | `QueryReadModels` | `GET /dashboard/summary` ほか | なし | 状態変更なし |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `AccessDecision` | `bff` | `Firestore:audit_logs` | `identifier` 単位 | `trace`, `identifier`, `user`, `endpoint`, `result`, `reasonCode` |
| `CommandIntake` | `bff` | `Firestore:idempotency_keys` | `identifier` 単位 | `trace`, `identifier`, `commandType`, `processedAt` |
| `OperationsState` | `bff` | `Firestore:operations` | `runtime` ドキュメント単位 | `trace`, `user`, `actionReasonCode` |
| `StrategySettings` | `bff` | `Firestore:settings` | `strategy` ドキュメント単位 | `trace`, `user` |
| `ComplianceControls` | `bff` | `Firestore:compliance_controls` | `trading` ドキュメント単位 | `trace`, `user`, `actionReasonCode` |

- 他集約更新は同一Txで行わない。
- 集約間整合は発行イベントと `idempotency_keys` で実現する。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-BFF-001` | acceptance | `RULE-BFF-001` | 非保護API以外でJWT必須 |
| `TST-BFF-002` | acceptance | `RULE-BFF-002` | 権限不足時 `AUTH_FORBIDDEN` |
| `TST-BFF-003` | acceptance | `RULE-BFF-003` | 更新系で `trace`,`identifier` が採番/記録 |
| `TST-BFF-004` | domain event | `RULE-BFF-004` | 永続化成功後のみイベント発行 |
| `TST-BFF-005` | idempotency | `RULE-BFF-005` | 同一identifier重複で副作用なし |
| `TST-BFF-006` | contract | `RULE-BFF-006` | retry受付で `orders.proposed` 発行 |
| `TST-BFF-007` | acceptance | `RULE-BFF-007` | kill switch有効時に対象操作拒否 |
| `TST-BFF-008` | acceptance | `RULE-BFF-008` | 参照系で状態更新なし |
| `TST-BFF-009` | contract | `RULE-BFF-009` | OpenAPI/AsyncAPI/Domain Modelで `identifier` 命名統一 |

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

- JWT必須判定と権限判定の責務境界が明確か。
- 更新系APIで `trace` / `identifier` / `user` が欠損しないか。
- 永続化とイベント発行順序（更新後発行）が保証されるか。
- `POST /orders/{identifier}/retry` の `orders.proposed` 再送が状態遷移設計と一致するか。
- 参照系クエリが副作用を持たないことを担保できるか。
- Rule→Scenario→Model→Contract→Test のトレースが切れていないか。

## 12. 参照（調査ソース）

- `documents/内部設計/md/DDD仕様駆動ドメインモデルテンプレート.md`
- `documents/外部設計/services/bff.md`
- `documents/内部設計/services/bff.md`
- `documents/内部設計/json/bff.json`
- `documents/外部設計/api/openapi.yaml`
- `documents/外部設計/api/asyncapi.yaml`
- `documents/外部設計/state/状態遷移設計.md`
- `documents/外部設計/security/認証認可設計.md`
- `documents/外部設計/security/authz-matrix.json`
- `documents/外部設計/db/firestore設計.md`
- `documents/外部設計/error/error-codes.json`
- `documents/外部設計/operations/運用設計.md`
