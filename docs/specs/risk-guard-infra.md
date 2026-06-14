# Spec: risk-guard infrastructure layer

## Goal

`svc-risk-guard` のインフラストラクチャ層を実装する。
ドメイン層・ユースケース層が要求するポート型クラス（`OrderRiskAssessmentRepository`、`IdempotencyKeyRepository`、`RiskEventPublisher`）の具象実装を提供し、Firestore 5 コレクションへの CRUD と Pub/Sub 2 トピックへの CloudEvents 発行を担う。
本 issue のスコープはインフラ層のみ（`Infrastructure/` 配下）。`Main.hs` DI 配線・Pub/Sub サブスクライバはプレゼンテーション層 Issue #44。

---

## Must (満たさなければ done でない)

### モジュール構成

- [ ] **Must-01**: 以下のモジュールファイルが存在する:
  - `backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskAssessmentRepository.hs`
  - `backend/risk-guard/src/Infrastructure/Repository/FirestoreIdempotencyKeyRepository.hs`
  - `backend/risk-guard/src/Infrastructure/Publisher/PubSubRiskEventPublisher.hs`

### Firestore: `risk_assessments` コレクション (OrderRiskAssessmentRepository)

- [ ] **Must-02**: `FirestoreRiskAssessmentRepositoryT` が `ReaderT FirestoreRiskAssessmentEnv m` を包む newtype として定義され、`OrderRiskAssessmentRepository (FirestoreRiskAssessmentRepositoryT IO)` インスタンスを実装する。
- [ ] **Must-03**: `FirestoreRiskAssessmentEnv` が `firestoreContext :: FirestoreContext` フィールドを持つ。
- [ ] **Must-04**: `find` が コレクション `risk_assessments`、ドキュメント ID `identifier.value`（ULID 文字列）で 1 件取得し、存在しない場合は `Nothing` を返す。
- [ ] **Must-05**: `findByStatus` が `decision` フィールド相当の Firestore フィルタで絞り込み、該当するすべての `OrderRiskAssessment` を返す。
- [ ] **Must-06**: `search` が `RiskAssessmentSearchCriteria.statusFilter` / `limitCount` を Firestore クエリに変換し、`evaluatedAt DESC` 順で返す（`limitCount` 未指定時デフォルト 50）。
- [ ] **Must-07**: `persist` が `upsertDocument` を呼ぶ際に `withRetry defaultRetryPolicyConfig isRetryableForPersist` でラップし、`version` フィールドを楽観ロック用に書き込む。
- [ ] **Must-08**: `terminate` が `deleteDocument` で `risk_assessments/{identifier}` を削除する。
- [ ] **Must-09**: `RiskAssessmentDocument` の Firestore フィールド名が設計書（`documents/外部設計/db/firestore設計.md` §3.18）と一致する: `identifier`, `order`, `decision`, `reasonCode`(optional), `actionReasonCode`(optional), `trace`, `evaluatedAt`, `version`。
- [ ] **Must-10**: `isRetryableForPersist :: FirestoreError -> Bool` が定義され、`FirestoreErrorDecode` は `False`、transport/5xx/429 は `True` を返す（data-collector パターン踏襲）。

### Firestore: `idempotency_keys` コレクション (IdempotencyKeyRepository)

- [ ] **Must-11**: `FirestoreIdempotencyKeyRepositoryT` が `ReaderT FirestoreIdempotencyKeyEnv m` を包む newtype として定義され、`IdempotencyKeyRepository (FirestoreIdempotencyKeyRepositoryT IO)` インスタンスを実装する。
- [ ] **Must-12**: `FirestoreIdempotencyKeyEnv` が `firestoreContext :: FirestoreContext` フィールドを持つ。
- [ ] **Must-13**: `find serviceText eventKeyText` が `idempotency_keys/{service}:{eventKey}` を Firestore から取得し、`processedAt` が `Just _` なら `True`、それ以外（ドキュメント不存在 / `processedAt = Nothing`）は `False` を返す。これはユースケース層の `IdempotencyKeyRepository.find :: Text -> Text -> m Bool` シグネチャに対応する。
- [ ] **Must-14**: `persist serviceText eventKeyText` が `idempotency_keys/{service}:{eventKey}` を upsert し、`processedAt = Just now`、`expiresAt = now + 30日`、`updatedAt = now` を書き込む。
- [ ] **Must-15**: `terminate serviceText eventKeyText` が `deleteDocument` で `idempotency_keys/{service}:{eventKey}` を削除する。

### Firestore 読み取り専用: settings / operations / compliance_controls

- [ ] **Must-16**: `backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskSettingsRepository.hs` が存在し、`RiskSettingsPort` に対する具象実装を提供する（`UseCase.CheckOrderRisk` が要求する `loadRiskLimits`, `loadCompliancePolicy`, `loadRiskExposure`, `loadKillSwitchState` の 4 関数）。
- [ ] **Must-17**: `loadRiskLimits` が `settings/strategy` から `dailyLossLimit`, `positionConcentrationLimit`, `dailyOrderLimit`, `version` を取得し `RiskLimits` に変換する。
- [ ] **Must-18**: `loadKillSwitchState` が `operations/runtime` から `killSwitchEnabled` (boolean) を取得し `Bool` を返す。
- [ ] **Must-19**: `loadCompliancePolicy` が `compliance_controls/trading` から `restrictedSymbols`, `partnerRestrictedSymbols`, `blackoutWindows` を取得し `CompliancePolicy` に変換する。`blackoutWindows` の各要素は `{ symbol, startAt, endAt, actionReasonCode }` を持つ。
- [ ] **Must-20**: `backend/risk-guard/src/Infrastructure/Repository/FirestoreKillSwitchStateRepository.hs` が存在し、`KillSwitchStatePort`（`UseCase.SyncKillSwitch` が要求する `persistKillSwitchState`, `loadKillSwitchState`）の具象実装を提供する。`persistKillSwitchState` は `operations/runtime` の `killSwitchEnabled` フィールドを upsert する。

### Pub/Sub: RiskEventPublisher

- [ ] **Must-21**: `PubSubRiskEventPublisherT` が `ReaderT PubSubRiskEventPublisherEnv m` を包む newtype として定義され、`RiskEventPublisher (PubSubRiskEventPublisherT IO)` インスタンスを実装する。
- [ ] **Must-22**: `PubSubRiskEventPublisherEnv` が `publisher :: PubSubPublisher`, `approvedTopicName :: TopicName`, `rejectedTopicName :: TopicName` の 3 フィールドを持つ。
- [ ] **Must-23**: `publishOrdersApproved` が `orders.approved` トピックへ CloudEvents 互換 JSON を発行する。エンベロープ必須フィールドは `identifier`(新規 ULID), `eventType = "orders.approved"`, `occurredAt`(ISO8601 UTC), `trace`, `schemaVersion = "1.0.0"`, `payload`。payload フィールドは `identifier`, `decision = "approved"`, `reasonCode`(optional), `actionReasonCode`(optional)（AsyncAPI `OrdersApprovedEvent` 準拠）。
- [ ] **Must-24**: `publishOrdersRejected` が `orders.rejected` トピックへ CloudEvents 互換 JSON を発行する。payload には `identifier`, `decision = "rejected"`, `reasonCode`(必須) が含まれる（AsyncAPI `OrdersRejectedEvent` 準拠）。
- [ ] **Must-25**: `buildOrdersApprovedEvent` および `buildOrdersRejectedEvent` が純粋関数として export され、IO なしでエンベロープを構築できる（コントラクトテスト用）。

### インフラ分離の確認

- [ ] **Must-26**: `Infrastructure/` 配下のモジュールがドメイン型クラス（`OrderRiskAssessmentRepository`, `IdempotencyKeyRepository`, `RiskEventPublisher`）を実装するにあたり、ドメイン層が gogol/Persistence 等を import しないことを維持する。確認: `grep -rn "gogol\|Firestore\|PubSub" backend/risk-guard/src/Domain/ backend/risk-guard/src/UseCase/` が 0 件。

### .cabal 更新

- [ ] **Must-27**: `backend/risk-guard/risk-guard.cabal` の library `exposed-modules` に以下が追加される:
  - `Infrastructure.Repository.FirestoreRiskAssessmentRepository`
  - `Infrastructure.Repository.FirestoreIdempotencyKeyRepository`
  - `Infrastructure.Repository.FirestoreRiskSettingsRepository`
  - `Infrastructure.Repository.FirestoreKillSwitchStateRepository`
  - `Infrastructure.Publisher.PubSubRiskEventPublisher`
- [ ] **Must-28**: `risk-guard.cabal` の `build-depends` に `shared`（common/haskell）, `gogol` 相当パッケージ（gogol-firestore/gogol-pubsub）, `unordered-containers`, `Persistence.Firestore` / `Messaging.PubSub` / `Resilience.Retry` が含まれる（data-collector.cabal の依存パターンに準拠）。

### ワイヤーフォーマット (codec)

- [ ] **Must-29**: `ReasonCode` → wire string の変換が以下のマッピングに従う（AsyncAPI `ReasonCode` スキーマ準拠）:
  - `KillSwitchEnabled` → `"KILL_SWITCH_ENABLED"`
  - `RiskLimitExceeded` → `"RISK_LIMIT_EXCEEDED"`
  - `ComplianceRestrictedSymbol` → `"COMPLIANCE_RESTRICTED_SYMBOL"`
  - `ComplianceBlackoutActive` → `"COMPLIANCE_BLACKOUT_ACTIVE"`
  - `RiskEvaluationUnavailable` → `"RISK_EVALUATION_UNAVAILABLE"`
- [ ] **Must-30**: `Decision` → wire string の変換が `Approved' → "approved"`, `Rejected' → "rejected"` に従う（AsyncAPI `OrdersDecisionPayload.decision` enum 準拠）。

### 統合テスト

- [ ] **Must-31**: 以下のテストケースが `backend/risk-guard/test/` 配下に存在し、`cabal test risk-guard` がパスする:
  - **TST-INFRA-001**: `toDocument` / `documentToAssessment` 純粋ラウンドトリップ: 任意の `OrderRiskAssessment`（approved/rejected 両方）を encode → decode で元の値が復元される（IO なし）
  - **TST-INFRA-002**: `RiskAssessmentDocument` フィールド名が Firestore 設計書のフィールド名と一致する（`identifier`, `order`, `decision`, `reasonCode`, `actionReasonCode`, `trace`, `evaluatedAt`, `version` の存在をコード上で確認）
  - **TST-INFRA-003**: `isRetryableForPersist (FirestoreErrorDecode "x") == False`
  - **TST-INFRA-004**: `isRetryableForPersist (FirestoreErrorTransport "timeout") == True`
  - **TST-INFRA-005**: `buildOrdersApprovedEvent` が `eventType = "orders.approved"`, `schemaVersion = "1.0.0"`, payload に `decision = "approved"` を含む（IO なし）
  - **TST-INFRA-006**: `buildOrdersRejectedEvent` が `eventType = "orders.rejected"`, payload に `decision = "rejected"` および `reasonCode` を含む（IO なし）
  - **TST-INFRA-007**: `reasonCodeToWire KillSwitchEnabled == "KILL_SWITCH_ENABLED"` 等 5 件の wire 変換を確認
  - **TST-INFRA-008**: `idempotency_keys` の `find` において `processedAt = Just _` なら `True`、`processedAt = Nothing` なら `False` を返すロジックが純粋関数として単体確認できる

### ビルド / Lint

- [ ] **Must-32**: `cd backend && cabal build risk-guard` がエラーなし（exit code 0）。
- [ ] **Must-33**: `hlint backend/risk-guard/src/Infrastructure/` が警告 0 件（`ci/allowlist.yml` 例外を除く）。
- [ ] **Must-34**: `fourmolu --mode check backend/risk-guard/src/Infrastructure/` がエラーなし（exit code 0）。

---

## Should (望ましいが必須でない)

- `FirestoreRiskAssessmentRepositoryT` に `MonadIO` / `MonadReader` インスタンスを `deriving newtype` で付与し、利用側で `liftIO` を直接扱えるようにする。
- `toDocument` / `documentToAssessment` の純粋関数を cabal test-suite のみでなく library からも export し、将来の migration スクリプトで再利用できるようにする。
- `FirestoreRiskSettingsRepository` の Firestore 取得失敗時に structured logging（`Observability.Logging`）でエラー詳細を出力する。
- `blackoutWindows` のデシリアライズで `actionReasonCode` が未知の文字列のとき `Left ("unknown actionReasonCode: " <> code)` を返し、 `FirestoreErrorDecode` として伝搬させる。
- `loadRiskExposure` の実装戦略（`positions` コレクションから計算するか、`settings/strategy` の派生値を参照するか）を明示する（現時点ではユースケース呼び出し側が注入するため、infra 実装の責務外である可能性がある — Open questions 参照）。
- HLint RecordDot 括弧制約（`ci/allowlist.yml` 登録済み）に適合したスタイルを踏襲する。

---

## 受入条件 (acceptance — Must の確認方法)

- **Must-01** → `ls backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskAssessmentRepository.hs backend/risk-guard/src/Infrastructure/Repository/FirestoreIdempotencyKeyRepository.hs backend/risk-guard/src/Infrastructure/Publisher/PubSubRiskEventPublisher.hs` が全て exit code 0。
- **Must-02** → `grep -n "FirestoreRiskAssessmentRepositoryT\|OrderRiskAssessmentRepository" backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskAssessmentRepository.hs` が各 1 件以上ヒット。
- **Must-03** → `grep -n "firestoreContext" backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskAssessmentRepository.hs` が 1 件以上ヒット。
- **Must-04/05/06/07/08** → TST-INFRA-001 が `cabal test risk-guard` でパスする。かつ `grep -n "find\|findByStatus\|search\|persist\|terminate" backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskAssessmentRepository.hs` で 5 メソッドが確認できる。
- **Must-09** → TST-INFRA-002 が `cabal test risk-guard` でパスする。
- **Must-10** → TST-INFRA-003/004 が `cabal test risk-guard` でパスする。
- **Must-11/12** → `grep -n "FirestoreIdempotencyKeyRepositoryT\|IdempotencyKeyRepository" backend/risk-guard/src/Infrastructure/Repository/FirestoreIdempotencyKeyRepository.hs` が各 1 件以上ヒット。
- **Must-13** → TST-INFRA-008 が `cabal test risk-guard` でパスする。
- **Must-14/15** → `grep -n "persist\|terminate\|upsertDocument\|deleteDocument" backend/risk-guard/src/Infrastructure/Repository/FirestoreIdempotencyKeyRepository.hs` が 1 件以上ヒット。
- **Must-16** → `ls backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskSettingsRepository.hs` が exit code 0。
- **Must-17** → `grep -n "settings/strategy\|dailyLossLimit\|positionConcentrationLimit\|dailyOrderLimit" backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskSettingsRepository.hs` が 1 件以上ヒット。
- **Must-18** → `grep -n "operations/runtime\|killSwitchEnabled" backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskSettingsRepository.hs` が 1 件以上ヒット。
- **Must-19** → `grep -n "compliance_controls/trading\|restrictedSymbols\|blackoutWindows" backend/risk-guard/src/Infrastructure/Repository/FirestoreRiskSettingsRepository.hs` が 1 件以上ヒット。
- **Must-20** → `ls backend/risk-guard/src/Infrastructure/Repository/FirestoreKillSwitchStateRepository.hs` が exit code 0。かつ `grep -n "persistKillSwitchState\|loadKillSwitchState\|operations/runtime" backend/risk-guard/src/Infrastructure/Repository/FirestoreKillSwitchStateRepository.hs` が 1 件以上ヒット。
- **Must-21/22** → `grep -n "PubSubRiskEventPublisherT\|RiskEventPublisher\|approvedTopicName\|rejectedTopicName" backend/risk-guard/src/Infrastructure/Publisher/PubSubRiskEventPublisher.hs` が各 1 件以上ヒット。
- **Must-23/24** → TST-INFRA-005/006 が `cabal test risk-guard` でパスする。
- **Must-25** → `grep -n "buildOrdersApprovedEvent\|buildOrdersRejectedEvent" backend/risk-guard/src/Infrastructure/Publisher/PubSubRiskEventPublisher.hs` が各 1 件以上ヒット（export リストに含まれること）。
- **Must-26** → `grep -rn "gogol\|Firestore\|PubSub" backend/risk-guard/src/Domain/ backend/risk-guard/src/UseCase/` が 0 件。
- **Must-27** → `grep -n "Infrastructure.Repository.FirestoreRiskAssessmentRepository\|Infrastructure.Repository.FirestoreIdempotencyKeyRepository\|Infrastructure.Publisher.PubSubRiskEventPublisher" backend/risk-guard/risk-guard.cabal` が各 1 件ヒット。
- **Must-28** → `grep -n "shared\|gogol" backend/risk-guard/risk-guard.cabal` が 1 件以上ヒット。
- **Must-29** → TST-INFRA-007 が `cabal test risk-guard` でパスする。
- **Must-30** → TST-INFRA-005/006 の payload 内 `decision` フィールドが `"approved"` / `"rejected"` 文字列であることをアサートで確認。
- **Must-31** → `cabal test risk-guard --test-option="--format=checks"` で TST-INFRA-001〜008 の全 describe/it が green。
- **Must-32** → `cd backend && cabal build risk-guard` が exit code 0。
- **Must-33** → `hlint backend/risk-guard/src/Infrastructure/` が exit code 0（allowlist 適用後）。
- **Must-34** → `fourmolu --mode check backend/risk-guard/src/Infrastructure/` が exit code 0。

---

## Non-goals (今回やらない)

- `Main.hs` へのDI配線（`FirestoreRiskAssessmentRepositoryT` / `PubSubRiskEventPublisherT` の具体型を `main` に結線する作業）— プレゼンテーション層 Issue #44
- Pub/Sub サブスクライバ実装（`orders.proposed` / `operation.kill_switch.changed` の受信・デシリアライズ）— Issue #44
- Servant HTTP エンドポイントの実装（`POST /internal/orders/{identifier}/approve|reject`, `POST /operations/kill-switch`, `GET/PUT /compliance/controls`）— Issue #44
- `AuditTrailWriter` の Cloud Logging 実装（ユースケース層でのポート定義のみ存在、実装はスコープ外）
- ドメイン層・ユースケース層の変更（`Domain/` / `UseCase/` 配下は Issue #41・#42 完了済み）
- `loadRiskExposure` の Firestore 実装（現在のユースケース層は `RiskExposure` を引数として受け取るため、infra 層で独立して実装する可能性は Open questions に委ねる）
- Firestore インデックス JSON (`firestore.indexes.json`) の更新
- Cloud Logging / メトリクス出力（`risk_approved_total` 等）
- SLO 計測 (p95 遅延 1000ms)
- OpenAPI / AsyncAPI スキーマ更新
- Python サービス（`feature-engineering`, `signal-generator`）との連携

---

## Risk

- level: high-risk
- escalate_to_opus: true
- 理由:
  - `schema`: Firestore の `risk_assessments` ドキュメント codec は AsyncAPI `OrdersDecisionPayload` と Firestore 設計書の両方に直結するスキーマ境界である。`decision` / `reasonCode` のワイヤー文字列ミスはサイレントなデータ不整合を引き起こす。
  - `event subscription`: `publishOrdersApproved` / `publishOrdersRejected` が生成する CloudEvents エンベロープは `svc-execution` および `svc-audit-log` の Pub/Sub サブスクライバが直接消費する公開契約である。フィールド名・`eventType` 文字列の誤りはダウンストリームサービスの無音障害につながる。
  - `DI`: `FirestoreRiskAssessmentRepositoryT` 等の具象型は Issue #44 の DI 配線が依存するパブリックエクスポートであり、型シグネチャの変更は即座に配線破損を招く。
  - `config`: `settings/strategy`・`operations/runtime`・`compliance_controls/trading` の読み取りは kill switch・リスク上限・コンプライアンス制御の根拠データであり、フィールドマッピングの誤りは資産損失リスクに直結する。
  - `background job`: Pub/Sub publish は Pub/Sub サブスクライバ（Issue #44）から呼び出されるバックグラウンドパスの出口であり、publish 失敗が DLQ 転送を経由して監査証跡に影響する。

---

## Open questions

- **OQ-1**: `loadRiskExposure` の責務所在。現行の `UseCase.CheckOrderRisk.checkOrderRisk` は `RiskExposure` を引数として受け取るため（プレゼンテーション層 Issue #44 が Pub/Sub メッセージから注入する想定）、`FirestoreRiskSettingsRepository` に `loadRiskExposure` を実装するかどうかは Issue #44 の設計に依存する。本 spec では `RiskSettingsPort` の 4 関数（`loadRiskLimits`, `loadCompliancePolicy`, `loadRiskExposure`, `loadKillSwitchState`）の具象実装を Must-16 に含めているが、`loadRiskExposure` の Firestore 実装源泉コレクション（`positions` コレクションの集計 vs 別途スナップショット）が未確定。Issue #44 の spec 策定前に確認が必要。
