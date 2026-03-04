# hypothesis-lab-frontend ドメインモデル設計

最終更新日: 2026-03-01
対象Bounded Context: `hypothesis-lab-frontend`
ドキュメント版: `v0.1.0`
作成者: `codex`
レビュー状態: `draft`

## 1. 目的とスコープ

- 目的: SCR-007（仮説ラボ）画面における表示/操作/ガードを、BFF契約に整合するドメインモデルとして定義する。
- スコープ内:
1. 仮説一覧・詳細の表示モデル投影
2. 再検証/昇格申請/MNPI自己申告更新/却下の操作モデル
3. コンプライアンス制約を含む画面ガード
4. `trace`, `identifier`, `actionReasonCode` を含む監査可能なUI操作記録
- スコープ外:
1. 仮説評価（backtest/demo）や昇格判定ロジック本体
2. 自動昇格判定の最終決定（バックエンド責務）
3. 仮説生成アルゴリズム

## 2. 戦略設計（Strategic DDD）

### 2.1 Bounded Context定義

- Context名: `Hypothesis Lab Screen Interaction`
- ミッション: 仮説ライフサイクルの画面操作を安全に実行し、バックエンド判定を誤読なく可視化する。
- コア/支援/汎用サブドメイン区分: `supporting`

### 2.2 Ubiquitous Language（用語集）

| 用語 | 定義 | 使用箇所 | 禁止/注意 |
|---|---|---|---|
| Hypothesis Card | 仮説一覧の1行表示モデル | SCR-007 一覧 | 生DTOを直接描画しない |
| Hypothesis Detail View | 仮説詳細の表示モデル | SCR-007 詳細 | 欠損時に推測値を表示しない |
| Promotion Gate | 昇格操作のUI事前判定状態 | 昇格モーダル | 最終判定はBFF結果を正とする |
| Mnpi Declaration | MNPI自己申告更新の入力値 | `PUT /hypotheses/{identifier}/mnpi-self-declaration` | `status=demo` 以外で更新しない |
| Command Intent | 画面の更新系操作意図 | retest/promote/reject/update-mnpi | 送信前検証を必須化 |
| Identifier | 画面内識別子 | `identifier` | `id` / `Id` を使わない |
| Trace | 操作とバックエンド処理の相関識別子 | 更新系操作 | 欠落時は送信しない |

### 2.3 Context Map

| 相手Context | 関係 | インターフェース | 変換方針 |
|---|---|---|---|
| `Operator` | Upstream (`Customer-Supplier`) | 画面操作 | 操作を `HypothesisCommandIntent` に正規化 |
| `bff` | Upstream (`OHS+PL`) | OpenAPI（`/hypotheses*`） | DTO -> `HypothesisProjection`（ACL） |
| `hypothesis-lab`（backend） | Upstream（間接） | BFF経由の応答 | `promotionMode`, `autoPromotionEligible` を表示へ反映 |
| `security/compliance` | Upstream（間接） | `ReasonCode`, 認可/制約設計 | UIガードへマッピング |

## 3. 仕様駆動（Specification-Driven）

### 3.1 ビジネスルール一覧（Rule）

| Rule ID | ルール | 優先度 | 集約境界内/外 |
|---|---|---|---|
| `RULE-HLF-001` | 認証済みユーザーのみ本画面を操作可能 | must | inside |
| `RULE-HLF-002` | 一覧/詳細は `GET /hypotheses`, `GET /hypotheses/{identifier}` の投影モデルで描画する | must | outside |
| `RULE-HLF-003` | 再検証は `status != live` のときのみ実行可能 | must | inside |
| `RULE-HLF-004` | 昇格申請は `status=demo` かつ `instrumentType=STOCK` かつ `demoPeriod>=30日` かつ `requiresComplianceReview=false` かつ `mnpiSelfDeclared=true` のときのみ実行可能 | must | inside |
| `RULE-HLF-005` | MNPI自己申告更新は `status=demo` のときのみ実行可能 | must | inside |
| `RULE-HLF-006` | 却下操作は `actionReasonCode` 必須 | must | inside |
| `RULE-HLF-007` | 更新系操作は `trace` と対象 `identifier` を送信前に保持する | must | inside |
| `RULE-HLF-008` | 同一操作の多重送信は `submissionIdentifier` で重複抑止する | must | inside |
| `RULE-HLF-009` | `status=live` かつ `promotionMode=auto` 反映時に自動昇格成功メッセージを表示可能 | should | outside |
| `RULE-HLF-010` | 識別子命名は `identifier` を使用し `Id` を禁止する | must | inside |

### 3.2 受け入れ仕様（Gherkin）

```gherkin
Feature: promote action guard
  Rule: 昇格申請はUI条件を満たすときのみ可能
    Example: STOCK demo ready
      Given status が demo の仮説詳細を表示している
      And instrumentType が STOCK
      And requiresComplianceReview が false
      And mnpiSelfDeclared が true
      And demoPeriod が 30日以上
      When 運用者が昇格申請を実行する
      Then POST /hypotheses/{identifier}/promote が1回送信される
```

```gherkin
Feature: mnpi declaration update
  Rule: MNPI自己申告は demo 状態のみ更新可能
    Example: non-demo blocked
      Given status が backtested の仮説詳細を表示している
      When 運用者が自己申告チェックを更新する
      Then 更新リクエストは送信されない
      And 操作不可メッセージを表示する
```

```gherkin
Feature: command deduplication
  Rule: 同一操作の多重送信を抑止する
    Example: double click retest
      Given status が demo の仮説詳細を表示している
      When 再検証ボタンを連続クリックする
      Then POST /hypotheses/{identifier}/retest は1回のみ送信される
      And 2回目は duplicate として無害化される
```

### 3.3 仕様トレーサビリティ

| Rule ID | Scenario | Aggregate | API/Event | Test ID |
|---|---|---|---|---|
| `RULE-HLF-001` | `SCN-HLF-001` | `HypothesisLabSession` | 保護API全般 | `TST-HLF-001` |
| `RULE-HLF-002` | `SCN-HLF-002` | `HypothesisProjection` | `GET /hypotheses*` | `TST-HLF-002` |
| `RULE-HLF-003` | `SCN-HLF-003` | `HypothesisCommandInteraction` | `POST /hypotheses/{identifier}/retest` | `TST-HLF-003` |
| `RULE-HLF-004` | `SCN-HLF-004` | `HypothesisCommandInteraction` | `POST /hypotheses/{identifier}/promote` | `TST-HLF-004` |
| `RULE-HLF-005` | `SCN-HLF-005` | `HypothesisCommandInteraction` | `PUT /hypotheses/{identifier}/mnpi-self-declaration` | `TST-HLF-005` |
| `RULE-HLF-006` | `SCN-HLF-006` | `HypothesisCommandInteraction` | `POST /hypotheses/{identifier}/reject` | `TST-HLF-006` |
| `RULE-HLF-007` | `SCN-HLF-007` | `HypothesisCommandInteraction` | 更新系OpenAPI | `TST-HLF-007` |
| `RULE-HLF-008` | `SCN-HLF-008` | `HypothesisCommandInteraction` | 更新系OpenAPI | `TST-HLF-008` |
| `RULE-HLF-009` | `SCN-HLF-009` | `HypothesisProjection` | `GET /hypotheses/{identifier}` | `TST-HLF-009` |
| `RULE-HLF-010` | `SCN-HLF-010` | `HypothesisLabSession` | OpenAPI/画面モデル | `TST-HLF-010` |

## 4. 戦術設計（Tactical DDD）

### 4.1 Aggregate設計

| Aggregate | Aggregate Root | 責務 | 一貫性境界（同一Tx） | 不変条件 |
|---|---|---|---|---|
| `HypothesisLabSession` | `HypothesisLabSession` | 認証状態・選択仮説・画面状態を管理 | `screen session` | 保護操作の事前条件整合 |
| `HypothesisCommandInteraction` | `HypothesisCommandInteraction` | 更新系操作意図と送信状態管理 | `interaction scope` | 単一送信・必須入力保証 |
| `HypothesisProjection` | `HypothesisProjection` | BFF応答の表示モデル投影 | `view scope` | DTO非露出・表示一貫性 |

#### Aggregate詳細: `HypothesisLabSession`

- root: `HypothesisLabSession`
- 参照先集約: `HypothesisProjection`（`identifier` 参照のみ）
- 生成コマンド: `StartHypothesisLabSession`
- 更新コマンド: `AuthenticateSession`, `SelectHypothesis`, `SetFilter`, `RefreshSessionState`
- 削除/無効化コマンド: `TerminateHypothesisLabSession`
- 不変条件:
1. `authState=unauthenticated` の場合、更新系操作を実行しない。
2. `selectedHypothesis` は `HypothesisCard` の `identifier` と一致する。
3. `identifier` は生成後不変。

#### 4.1.1 Aggregate Rootフィールド定義（HypothesisLabSession）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 画面セッション識別子（ULID） | `1` |
| `user` | `string` | 操作ユーザー識別子 | `0..1` |
| `authState` | `enum(unauthenticated, authenticated, expired)` | 認証状態 | `1` |
| `trace` | `string` | 直近操作トレース（ULID） | `0..1` |
| `screenState` | `enum(initial,loading,ready,empty,error)` | 画面状態 | `1` |
| `selectedHypothesis` | `string` | 選択中仮説の識別子 | `0..1` |
| `filter` | `HypothesisFilter` | 一覧フィルタ条件 | `0..1` |
| `updatedAt` | `datetime` | 更新時刻 | `1` |

#### 4.1.2 集約内要素の保持（HypothesisLabSession）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `permissionSnapshot` | `PermissionSnapshot` | 操作可否判定用権限情報 | `0..1` |
| `operationGuard` | `HypothesisOperationGuard` | 操作ガード判定結果 | `1` |

#### Aggregate詳細: `HypothesisCommandInteraction`

- root: `HypothesisCommandInteraction`
- 参照先集約: `HypothesisLabSession`（`identifier` 参照のみ）
- 生成コマンド: `CreateHypothesisCommandIntent`
- 更新コマンド: `ValidateIntent`, `SubmitIntent`, `AcknowledgeIntent`, `RejectIntent`, `MarkDuplicateIntent`
- 削除/無効化コマンド: `TerminateHypothesisCommandInteraction`
- 不変条件:
1. 同一 `submissionIdentifier` は1回のみ送信可能。
2. `status=accepted/rejected` のとき `responseCode` 必須。
3. 更新系操作は `trace` と対象 `identifier` を必須保持。

#### 4.1.1 Aggregate Rootフィールド定義（HypothesisCommandInteraction）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 操作識別子（ULID） | `1` |
| `submissionIdentifier` | `string` | 重複抑止識別子（ULID） | `1` |
| `trace` | `string` | 相関識別子（ULID） | `1` |
| `target` | `string` | 対象仮説 `identifier` | `1` |
| `commandType` | `enum(retest,promote,reject,updateMnpiSelfDeclaration)` | 操作種別 | `1` |
| `status` | `enum(draft,validated,submitting,accepted,rejected,duplicate)` | 送信状態 | `1` |
| `actionReasonCode` | `enum(OperatorActionReasonCode)` | 操作理由コード | `0..1` |
| `mnpiSelfDeclared` | `boolean` | 自己申告値（更新時） | `0..1` |
| `comment` | `string` | コメント（SafeComment） | `0..1` |
| `responseCode` | `integer` | BFF応答コード | `0..1` |
| `reasonCode` | `enum(ReasonCode)` | 失敗理由コード | `0..1` |

#### Aggregate詳細: `HypothesisProjection`

- root: `HypothesisProjection`
- 参照先集約: なし
- 生成コマンド: `ProjectHypothesisList`, `ProjectHypothesisDetail`
- 更新コマンド: `RefreshProjection`, `FailProjection`
- 削除/無効化コマンド: `TerminateHypothesisProjection`
- 不変条件:
1. `status=ready` のとき `cards` または `detail` のどちらか必須。
2. 生DTOを内部保持しない。

#### 4.1.1 Aggregate Rootフィールド定義（HypothesisProjection）

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 投影識別子（ULID） | `1` |
| `status` | `enum(initial,loading,ready,empty,error)` | 投影状態 | `1` |
| `cards` | `List<HypothesisCard>` | 一覧表示モデル | `0..n` |
| `detail` | `HypothesisDetailView` | 詳細表示モデル | `0..1` |
| `cursor` | `string` | 次ページカーソル | `0..1` |
| `limit` | `integer` | 取得件数 | `0..1` |
| `updatedAt` | `datetime` | 最終更新時刻 | `1` |

### 4.2 Entity

| Entity | 識別子 | ライフサイクル | 主な振る舞い |
|---|---|---|---|
| `HypothesisCard` | `identifier` | `created -> rendered -> stale` | `render`, `markStale` |
| `HypothesisDetailView` | `identifier` | `created -> refreshed -> stale` | `refreshMetrics`, `applyPromotionSnapshot` |
| `HypothesisCommandIntent` | `identifier` | `draft -> validated -> submitting -> accepted/rejected/duplicate` | `validate`, `submit`, `acknowledge`, `reject`, `dedupe` |

#### Entity詳細: `HypothesisCard`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 仮説識別子 | `1` |
| `symbol` | `string` | 銘柄コード | `1` |
| `instrumentType` | `enum(ETF, STOCK)` | 商品種別 | `1` |
| `status` | `enum(draft,backtested,demo,live,rejected)` | ライフサイクル状態 | `1` |
| `title` | `string` | 仮説タイトル | `1` |
| `updatedAt` | `datetime` | 更新時刻 | `1` |

#### Entity詳細: `HypothesisDetailView`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `identifier` | `string` | 仮説識別子 | `1` |
| `costAdjustedReturn` | `number` | コスト控除後リターン | `0..1` |
| `dsr` | `number` | DSR | `0..1` |
| `pbo` | `number` | PBO | `0..1` |
| `demoPeriod` | `string` | demo期間表示値（例: `45d`） | `0..1` |
| `insiderRisk` | `enum(low,medium,high)` | インサイダーリスク | `0..1` |
| `requiresComplianceReview` | `boolean` | コンプライアンス追加審査要否 | `0..1` |
| `mnpiSelfDeclared` | `boolean` | MNPI自己申告状態 | `0..1` |
| `autoPromotionEligible` | `boolean` | 自動昇格候補 | `0..1` |
| `promotionMode` | `enum(manual,auto)` | 昇格モード | `0..1` |

### 4.3 Value Object

| Value Object | 属性 | 等価性 | 不変性 |
|---|---|---|---|
| `HypothesisFilter` | `status`, `cursor`, `limit` | 値比較 | immutable |
| `HypothesisOperationGuard` | `canRetest`, `canPromote`, `canReject`, `canUpdateMnpi` | 値比較 | immutable |
| `PromotionGateSnapshot` | `demoPeriod`, `requiresComplianceReview`, `mnpiSelfDeclared`, `instrumentType` | 値比較 | immutable |
| `MnpiDeclarationInput` | `mnpiSelfDeclared`, `actionReasonCode`, `comment` | 値比較 | immutable |
| `ApiProblem` | `status`, `reasonCode`, `detail` | 値比較 | immutable |
| `PermissionSnapshot` | `role`, `permissions` | 値比較 | immutable |

#### Value Object詳細: `HypothesisOperationGuard`

| フィールド名 | 型 | 説明 | 保持数 |
|---|---|---|---|
| `canRetest` | `boolean` | 再検証可否 | `1` |
| `canPromote` | `boolean` | 昇格申請可否（手動昇格対象） | `1` |
| `canReject` | `boolean` | 却下可否 | `1` |
| `canUpdateMnpi` | `boolean` | MNPI更新可否 | `1` |
| `blockReasonCode` | `enum(ReasonCode)` | ブロック理由 | `0..1` |

### 4.4 Domain Service / Application Service

| Service | 種別 | 責務 | 置いてはいけないもの |
|---|---|---|---|
| `HypothesisActionPolicy` | domain | 画面操作可否判定（status/商品種別/自己申告等） | HTTP呼び出し |
| `HypothesisProjectionTranslator` | application | OpenAPI DTO -> 画面表示モデル変換（ACL） | 業務判定本体 |
| `HypothesisCommandOrchestrator` | application | 更新系送信、重複抑止、応答反映 | 画面描画 |
| `HypothesisMessageResolver` | application | `reasonCode` -> 画面メッセージ変換 | API送信 |

### 4.5 Repository / Factory / Specification

| パターン | 名称 | 用途 | I/F定義 |
|---|---|---|---|
| Repository | `HypothesisProjectionRepository` | 投影状態の保持 | `Find`, `FindByStatus`, `Search`, `Persist`, `Terminate` |
| Repository | `HypothesisInteractionRepository` | 送信状態の保持 | `Find`, `FindBySubmissionIdentifier`, `Persist`, `Terminate` |
| Factory | `HypothesisCommandIntentFactory` | 操作意図生成 | `create(commandType, target, trace)` |
| Specification | `PromoteActionAllowedSpecification` | 昇格申請可否判定 | `isSatisfiedBy(detail)` |
| Specification | `MnpiUpdateAllowedSpecification` | MNPI更新可否判定 | `isSatisfiedBy(detail)` |

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
| `initial` | `ProjectHypothesisList` | `loading` | 認証済み | `AUTH_UNAUTHORIZED` |
| `loading` | `ProjectHypothesisList` 成功 | `ready` | items > 0 | - |
| `loading` | `ProjectHypothesisList` 成功 | `empty` | items = 0 | - |
| `loading` | `ProjectHypothesisList` 失敗 | `error` | なし | `REQUEST_VALIDATION_FAILED` ほか |
| `draft` | `SubmitIntent` | `submitting` | `HypothesisActionPolicy` が真 | `OPERATION_NOT_ALLOWED` |
| `submitting` | `AcknowledgeIntent` | `accepted` | BFF 2xx/202 | - |
| `submitting` | `RejectIntent` | `rejected` | BFF 4xx/5xx | `ReasonCode` |
| `submitting` | `MarkDuplicateIntent` | `duplicate` | 同一 `submissionIdentifier` | `DUPLICATE_COMMAND` |

### 5.2 不変条件テーブル

| Invariant ID | 対象Aggregate | 条件 | 破壊時の扱い |
|---|---|---|---|
| `INV-HLF-001` | `HypothesisCommandInteraction` | 更新系送信時は `trace` と `target(identifier)` 必須 | 送信拒否 |
| `INV-HLF-002` | `HypothesisCommandInteraction` | 同一 `submissionIdentifier` の送信は1回のみ | duplicate扱い |
| `INV-HLF-003` | `HypothesisProjection` | 生DTO非露出（表示モデルのみ保持） | 投影失敗 |
| `INV-HLF-004` | `HypothesisActionPolicy` | `status=demo` 以外で MNPI 更新不可 | 操作拒否 |
| `INV-HLF-005` | `HypothesisActionPolicy` | 昇格申請は手動条件（STOCK + gate条件）不達時に不可 | 操作拒否 |

## 6. ドメインイベント設計

### 6.1 Domain Event（境界内）

| eventType | 発行主体 | 発行タイミング | payload | 冪等キー |
|---|---|---|---|---|
| `ui.hypothesis.command.submitted` | `HypothesisCommandInteraction` | 送信開始時 | `commandType`, `target`, `trace` | `submissionIdentifier` |
| `ui.hypothesis.command.completed` | `HypothesisCommandInteraction` | 応答確定時 | `status`, `responseCode`, `reasonCode` | `submissionIdentifier` |
| `ui.hypothesis.projection.refreshed` | `HypothesisProjection` | 一覧/詳細更新時 | `status`, `cardCount`, `selectedIdentifier` | `identifier` |

### 6.2 Integration Event（境界外）

| eventType | 公開先 | 契約 | 整合性 | リトライ/DLQ |
|---|---|---|---|---|
| なし（HTTP同期呼び出し） | `bff` | OpenAPI | request/response | UI再試行ポリシー |

## 7. API/イベント契約マッピング

| ユースケース | Command/Query | OpenAPI | AsyncAPI | 備考 |
|---|---|---|---|---|
| 仮説一覧表示 | `LoadHypotheses` | `GET /hypotheses` | なし | SCR-007 |
| 仮説詳細表示 | `LoadHypothesisDetail` | `GET /hypotheses/{identifier}` | なし | SCR-007 |
| 再検証 | `RetestHypothesis` | `POST /hypotheses/{identifier}/retest` | なし | `202 accepted` |
| 昇格申請 | `PromoteHypothesis` | `POST /hypotheses/{identifier}/promote` | なし | `mnpiSelfDeclared=true` を送信 |
| MNPI更新 | `UpdateMnpiDeclaration` | `PUT /hypotheses/{identifier}/mnpi-self-declaration` | なし | `status=demo` のみ |
| 却下 | `RejectHypothesis` | `POST /hypotheses/{identifier}/reject` | なし | `actionReasonCode` 必須 |

## 8. 永続化と整合性

| 保存対象 | オーナー | 保存先 | トランザクション境界 | 監査項目 |
|---|---|---|---|---|
| `HypothesisLabSession` | `frontend-sol` | in-memory | 単一セッション更新 | `trace`, `user`, `screen` |
| `HypothesisCommandInteraction` | `frontend-sol` | in-memory | 単一操作更新 | `trace`, `identifier`, `actionReasonCode` |
| `HypothesisProjection` | `frontend-sol` | in-memory cache | 単一投影更新 | `trace`, `identifier`, `result` |

- System of Record はBFF/バックエンドであり、フロント保持はキャッシュ用途に限定する。
- 操作完了後は `GET /hypotheses/{identifier}` 再取得で表示を収束させる。

## 9. テスト設計（仕様と同型）

| Test ID | 種別 | 対応Rule | 観測点 |
|---|---|---|---|
| `TST-HLF-001` | acceptance | `RULE-HLF-001` | 未認証時に画面保護 |
| `TST-HLF-002` | contract | `RULE-HLF-002` | DTO -> 表示モデル変換整合 |
| `TST-HLF-003` | acceptance | `RULE-HLF-003` | `status=live` で再検証不可 |
| `TST-HLF-004` | acceptance | `RULE-HLF-004` | 昇格申請ガード条件 |
| `TST-HLF-005` | acceptance | `RULE-HLF-005` | demo以外でMNPI更新不可 |
| `TST-HLF-006` | acceptance | `RULE-HLF-006` | 却下で理由コード必須 |
| `TST-HLF-007` | contract | `RULE-HLF-007` | 更新系送信に `trace`/`identifier` 含有 |
| `TST-HLF-008` | idempotency | `RULE-HLF-008` | 多重送信抑止 |
| `TST-HLF-009` | acceptance | `RULE-HLF-009` | 自動昇格表示メッセージ条件 |
| `TST-HLF-010` | contract | `RULE-HLF-010` | `identifier` 命名統一 |

## 10. 実装規約（このプロジェクト向け）

- 画面モデル/コマンドモデルも `identifier` 命名規約を適用する（`Id` 禁止）。
- 更新系操作は `trace` を必須とし、未設定なら送信しない。
- `ReasonCode` / `OperatorActionReasonCode` は OpenAPI正本に追従する。
- BFF DTO をそのまま描画せず、ACLで `HypothesisProjection` へ投影する。

## 11. オニオンアーキテクチャ適用（本画面）

| 層 | 主要要素 | 依存方向 |
|---|---|---|
| Domain | Aggregate, Entity, Value Object, Specification | 内向きのみ |
| Application | ProjectionTranslator, CommandOrchestrator, MessageResolver | Domain に依存 |
| Interface Adapters | SCR-007 ルート、Presenter、UIイベントハンドラ | Application に依存 |
| Infrastructure | BFF API Client、ローカルキャッシュ、Telemetry | Port 実装のみ |

## 12. レビュー観点

- SCR-007要件（操作条件/表示項目/メッセージ）と矛盾がないか。
- `conditions for promote` が security設計と一致しているか。
- BFF契約変更時にACLで局所吸収できるか。
- `trace`, `identifier`, `actionReasonCode` の監査情報欠落がないか。
