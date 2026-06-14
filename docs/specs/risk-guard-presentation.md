# Spec: risk-guard presentation layer

- Layer: Presentation
- Service: svc-risk-guard
- Issue: #44
- Depends on: #41 (domain), #42 (usecase), #43 (infra)

## Goal

`svc-risk-guard` のプレゼンテーション層を実装する。
`orders.proposed` / `operation.kill_switch.changed` Pub/Sub メッセージを受信してユースケースを呼び出す 2 つのサブスクライバ、
および `GET /healthz` と `POST /internal/orders/{identifier}/approve|reject` を提供する Servant HTTP サーバーを構築する。
`Main.hs` で全インフラアダプタを DI 配線し、HTTP サーバーと Pub/Sub サブスクライバを並列実行する。

---

## Must (満たさなければ done でない)

### Pub/Sub サブスクライバ

- [ ] **Must-01** `[TST-PRES-001]`: `backend/risk-guard/src/Presentation/Subscriber/PubSubOrderRiskSubscriber.hs` が存在し、`module Presentation.Subscriber.PubSubOrderRiskSubscriber` を宣言する。`orders.proposed` Pub/Sub プッシュエンベロープを受け取り `UseCase.CheckOrderRisk.checkOrderRisk` を呼ぶ関数（`handleOrdersProposed` または相当）をエクスポートする。

- [ ] **Must-02** `[TST-PRES-002]`: `backend/risk-guard/src/Presentation/Subscriber/PubSubKillSwitchSubscriber.hs` が存在し、`module Presentation.Subscriber.PubSubKillSwitchSubscriber` を宣言する。`operation.kill_switch.changed` Pub/Sub プッシュエンベロープを受け取り `UseCase.SyncKillSwitch.syncKillSwitch` を呼ぶ関数（`handleKillSwitchChanged` または相当）をエクスポートする。

### HTTP API (Servant)

- [ ] **Must-03** `[TST-PRES-003]`: `backend/risk-guard/src/Presentation/Api.hs` に `type RiskGuardApi` として Servant 型レベル API が定義される。定義には以下の 3 ルートをすべて含む:
  - `GET /healthz`
  - `POST /internal/orders/{identifier}/approve`
  - `POST /internal/orders/{identifier}/reject`

- [ ] **Must-04** `[TST-PRES-004]`: `GET /healthz` に対して HTTP 200 と JSON ボディ `{"status":"ok"}` を返す。

- [ ] **Must-05** `[TST-PRES-005]`: `POST /internal/orders/{identifier}/approve` ハンドラが `UseCase.CheckOrderRisk.checkOrderRisk` を `ManualApproval` アクション理由コードで呼ぶ。成功時は HTTP 200 と `{"success":true,"trace":"<ULID>"}` を返す。審査済み（`CheckOrderRiskDuplicate`）の場合は HTTP 409 を返す。

- [ ] **Must-06** `[TST-PRES-006]`: `POST /internal/orders/{identifier}/reject` ハンドラが `UseCase.CheckOrderRisk.checkOrderRisk` を `ManualRejection` アクション理由コードで呼ぶ。成功時は HTTP 200 と `{"success":true,"trace":"<ULID>"}` を返す。審査済み（`CheckOrderRiskDuplicate`）の場合は HTTP 409 を返す。actionReasonCode が欠落する場合は HTTP 400 を返す。

### Main.hs — DI 配線と並列実行

- [ ] **Must-07** `[TST-PRES-007]`: `backend/risk-guard/src/Main.hs` が存在し、以下をすべて行う:
  - 環境変数から設定を読み込み `AppEnv` を構築する。
  - `FirestoreRiskAssessmentRepositoryT`, `FirestoreIdempotencyKeyRepositoryT`, `FirestoreRiskSettingsRepository`, `FirestoreKillSwitchStateRepository`, `PubSubRiskEventPublisherT` の各インフラアダプタを結線する。
  - Warp HTTP サーバーと Pub/Sub サブスクライバ 2 本（`orders.proposed` / `operation.kill_switch.changed`）を `Control.Concurrent.Async.concurrently_` または同等の機構で並列実行する。

### CloudEvents デコードと ack/nack

- [ ] **Must-08** `[TST-PRES-008]`: Pub/Sub サブスクライバはメッセージボディを CloudEvents 互換 JSON（`identifier`, `eventType`, `occurredAt`, `trace`, `schemaVersion`, `payload` の各フィールドを持つ）としてデコードする。デコード失敗時は HTTP 200（ack）を返してループから除去する（再配信しない）。デコード成功時はユースケースを呼び、成功 / 重複は HTTP 200（ack）、リトライ可能な失敗は HTTP 500（nack）を返す。

### 環境変数

- [ ] **Must-09** `[TST-PRES-009]`: `Main.hs` または `Presentation/AppM.hs`（相当するモジュール）が以下の環境変数を読み込む。いずれかが欠落している場合は起動時に `error` / `die` で即時終了する:
  - `PUBSUB_PROJECT_ID` — Pub/Sub GCP プロジェクト ID
  - `ORDERS_PROPOSED_SUBSCRIPTION` — `orders.proposed` のサブスクリプション名
  - `KILL_SWITCH_SUBSCRIPTION` — `operation.kill_switch.changed` のサブスクリプション名
  - `PORT` — HTTP サーバーポート（デフォルト `8080` を許容）
  - `FIRESTORE_PROJECT_ID` — Firestore GCP プロジェクト ID（または `GOOGLE_CLOUD_PROJECT` / `GCP_PROJECT_ID` で共通化してもよい）

### 依存方向の制約

- [ ] **Must-10** `[TST-PRES-010]`: `Presentation/` 配下のモジュールが直接 `Domain.` 型クラスや `Infrastructure.` 具象型をインポートしない。許可されるインポート先は `UseCase.*`, `Presentation.*`（同層内相互参照）, `Messaging.*`, `Observability.*`, `Config.*`（共通ライブラリ） および `Servant`/`Warp` のみ。確認: `grep -rn "import Domain\.\|import Infrastructure\." backend/risk-guard/src/Presentation/` が 0 件。

### リトライ

- [ ] **Must-11** `[TST-PRES-011]`: Pub/Sub サブスクライバはユースケース呼び出し（`checkOrderRisk` / `syncKillSwitch`）が一時障害（`CheckOrderRiskFailed _ True` / `SyncKillSwitchFailed _ True`）を返した場合、指数バックオフで最大 3 回再試行する。再試行の実装は `Resilience.Retry.withRetry` を用いる（data-collector パターン踏襲）。3 回失敗後は HTTP 500（nack）で返す。

### .cabal 更新

- [ ] **Must-12** `[TST-PRES-012]`: `backend/risk-guard/risk-guard.cabal` の executable `risk-guard` の `build-depends` に `async`（または `unliftio` の `UnliftIO.Async`）が追加される。library の `exposed-modules` に以下が追加される:
  - `Presentation.Subscriber.PubSubOrderRiskSubscriber`
  - `Presentation.Subscriber.PubSubKillSwitchSubscriber`
  - `Presentation.Api`
  - `Presentation.AppM`

---

## Should (望ましいが必須でない)

- `Presentation.AppM` は `data-collector` と同様に `newtype AppM a = AppM { unAppM :: ReaderT AppEnv IO a }` パターンを採用し、`runAppM :: AppEnv -> AppM a -> IO a` を提供する。
- Pub/Sub サブスクライバは受信・処理完了・エラーを `Observability.Logging.logInfoWith` / `logErrorWith` で構造化ログ出力する。フィールドは `service = "risk-guard"`, `trace`, `identifier`, `eventType`, `result`。
- HTTP レスポンスのエラーは RFC 9457 互換 `application/problem+json` 形式とする。
- `GET /healthz` ハンドラは `App.Bootstrap.runHttpService` の標準ヘルスエンドポイントで実装する（data-collector パターン踏襲）。
- `POST /internal/orders/{identifier}/approve|reject` は GCP IAM によるサービス間認証を前提とし、外部公開しない（Cloud Run の internal ingress 設定は Terraform スコープ）。
- HLint RecordDot 括弧制約（`ci/allowlist.yml` 登録済み）に適合したスタイルを踏襲する。

---

## 受入条件 (acceptance — Must の確認方法)

- **Must-01** → `ls backend/risk-guard/src/Presentation/Subscriber/PubSubOrderRiskSubscriber.hs` が exit code 0。かつ `grep -n "handleOrdersProposed\|checkOrderRisk" backend/risk-guard/src/Presentation/Subscriber/PubSubOrderRiskSubscriber.hs` が 1 件以上ヒット。
- **Must-02** → `ls backend/risk-guard/src/Presentation/Subscriber/PubSubKillSwitchSubscriber.hs` が exit code 0。かつ `grep -n "handleKillSwitchChanged\|syncKillSwitch" backend/risk-guard/src/Presentation/Subscriber/PubSubKillSwitchSubscriber.hs` が 1 件以上ヒット。
- **Must-03** → `grep -n "type RiskGuardApi\|healthz\|approve\|reject" backend/risk-guard/src/Presentation/Api.hs` が 4 件以上ヒット（型名 + 3 ルート）。
- **Must-04** → TST-PRES-004: Servant テストまたは hspec `WaiSession` で `GET /healthz` が `200` と `{"status":"ok"}` を返すことをアサート。
- **Must-05** → TST-PRES-005: モック `AppEnv` を使った hspec で `POST /internal/orders/<ULID>/approve` が `checkOrderRisk` を `ManualApproval` で呼ぶことを確認し、200 レスポンスの `success = true` をアサート。`CheckOrderRiskDuplicate` を注入した場合は 409 をアサート。
- **Must-06** → TST-PRES-006: モック `AppEnv` を使った hspec で `POST /internal/orders/<ULID>/reject` が `checkOrderRisk` を `ManualRejection` で呼ぶことを確認し、200 レスポンスの `success = true` をアサート。`CheckOrderRiskDuplicate` を注入した場合は 409 をアサート。
- **Must-07** → `grep -n "concurrently_\|Async\|ORDERS_PROPOSED_SUBSCRIPTION\|KILL_SWITCH_SUBSCRIPTION" backend/risk-guard/src/Main.hs` が 1 件以上ヒット。かつ `cd backend && cabal build risk-guard` が exit code 0。
- **Must-08** → TST-PRES-008: 不正 JSON ボディを注入した場合に HTTP 200（ack）が返ることを hspec でアサート。有効 CloudEvents ボディを注入した場合にユースケースが呼ばれることをアサート。
- **Must-09** → `grep -n "PUBSUB_PROJECT_ID\|ORDERS_PROPOSED_SUBSCRIPTION\|KILL_SWITCH_SUBSCRIPTION\|FIRESTORE_PROJECT_ID" backend/risk-guard/src/Main.hs backend/risk-guard/src/Presentation/AppM.hs` が合計 5 件以上ヒット（各変数名が 1 件以上）。
- **Must-10** → `grep -rn "import Domain\.\|import Infrastructure\." backend/risk-guard/src/Presentation/` が 0 件。
- **Must-11** → TST-PRES-011: `withRetry` を呼ぶコードパスが `Presentation/Subscriber/PubSubOrderRiskSubscriber.hs` または `PubSubKillSwitchSubscriber.hs` に存在することを `grep -n "withRetry" backend/risk-guard/src/Presentation/` で確認。かつリトライ可能な失敗を注入した場合にユースケースが 3 回呼ばれることを hspec でアサート。
- **Must-12** → `grep -n "async\|Presentation.Subscriber.PubSubOrderRiskSubscriber\|Presentation.Subscriber.PubSubKillSwitchSubscriber\|Presentation.Api\|Presentation.AppM" backend/risk-guard/risk-guard.cabal` が 5 件以上ヒット。

### ビルド / Lint 受入条件

- `cd backend && cabal build risk-guard` が exit code 0。
- `hlint backend/risk-guard/src/Presentation/` が exit code 0（`ci/allowlist.yml` 例外を除く）。
- `fourmolu --mode check backend/risk-guard/src/Presentation/` が exit code 0。
- `cabal test risk-guard --test-option="--format=checks"` で TST-PRES-001〜012 の全 describe/it が green。

---

## Non-goals (今回やらない)

- オペレーター承認 HTTP エンドポイント (`POST /operations/kill-switch`, `GET/PUT /compliance/controls`) — BFF 経由の別サービス呼び出しで処理する。本 issue ではスコープ外。
- `svc-execution` / `svc-audit-log` の Pub/Sub サブスクライバ実装。
- Cloud Logging / メトリクス出力（`risk_approved_total` 等の Prometheus メトリクス）。
- Firestore インデックス JSON (`firestore.indexes.json`) の更新。
- OpenAPI / AsyncAPI スキーマ更新。
- ドメイン層・ユースケース層・インフラ層の変更（`Domain/` / `UseCase/` / `Infrastructure/` 配下は Issue #41〜#43 完了済み）。
- Terraform / Cloud Run デプロイ設定（ingress=internal 等）。
- Python サービス（`feature-engineering`, `signal-generator`）との連携。
- SLO 計測（p95 遅延 1000ms 等の runtime 計測）。

---

## アーキテクチャノート

### Pub/Sub サブスクライバパターン

data-collector の `Presentation.PubSubHandler` パターンに準拠する。

```
HTTP POST /pubsub/orders-proposed
  └─ PubSubOrderRiskSubscriber.handleOrdersProposed
       ├─ decodePubSubPush (Messaging.PubSub) → CloudEvent
       ├─ decode failure → 200 ack (スキーマ不正の再配信を防ぐ)
       ├─ withRetry (Resilience.Retry, max 3, exponential backoff)
       │    └─ runAppM appEnv $ checkOrderRisk currentTime ... payload
       ├─ CheckOrderRiskApproved / Duplicate → 200 ack
       └─ CheckOrderRiskFailed _ True (retryable) → 500 nack (3回失敗後)
          CheckOrderRiskFailed _ False (non-retryable) → 200 ack
```

`PubSubKillSwitchSubscriber` も同パターンで `syncKillSwitch` を呼ぶ。

### Servant API パターン

data-collector の `Presentation.Api` / `Presentation.AppM` パターンに準拠する。

```haskell
type RiskGuardApi
  =    "healthz" :> Get '[JSON] HealthResponse
  :<|> "internal" :> "orders" :> Capture "identifier" Text
         :> "approve" :> ReqBody '[JSON] ApproveOrderRequest
         :> Post '[JSON] OperationResult
  :<|> "internal" :> "orders" :> Capture "identifier" Text
         :> "reject"  :> ReqBody '[JSON] RejectOrderRequest
         :> Post '[JSON] OperationResult
```

### AppM パターン

`Presentation.AppM` は `newtype AppM a = AppM { unAppM :: ReaderT AppEnv IO a }` として定義し、
`OrderRiskAssessmentRepository`, `IdempotencyKeyRepository`, `RiskEventPublisher` の各型クラスインスタンスを実装する。
各インスタンスはインフラアダプタの `run*T` 関数を呼ぶ（data-collector の `Presentation.AppM` に準拠）。

### 並列実行パターン (Main.hs)

```haskell
main :: IO ()
main = do
  appEnv <- buildAppEnv
  concurrently_
    (concurrently_
      (runOrdersProposedSubscriber appEnv)
      (runKillSwitchSubscriber appEnv))
    (runHttpService ... riskGuardApiProxy (riskGuardServer appEnv))
```

---

## Risk

- level: high-risk
- escalate_to_opus: true
- 理由:
  - `DI`: `Main.hs` が全インフラアダプタを具象型で結線する唯一の場所であり、型ミスマッチは即座にビルドエラーを引き起こすが、結線漏れはサイレント障害になりうる。
  - `event subscription`: `orders.proposed` サブスクライバは注文の自動審査トリガーであり、ack/nack の誤実装は注文の消失（重複 ack）またはループ（永続 nack）を招く。
  - `routing`: Servant `RiskGuardApi` の型定義は BFF が呼び出す内部 API の公開契約であり、ルートの変更はダウンストリームの呼び出し破損につながる。
  - `background job`: Pub/Sub サブスクライバは Cloud Run のバックグラウンドパスであり、`concurrently_` の誤用でサーバー停止時にサブスクライバが孤立するリスクがある。
  - `config`: 環境変数の欠落チェックが不十分な場合、`Nothing` サイレント扱いになってトピック名などがゼロ値になりうる。

---

## Open questions

- **OQ-1**: `loadRiskExposure` の責務（infra-spec OQ-1 の継続）。`checkOrderRisk` は `RiskExposure` を引数として受け取るが、プレゼンテーション層でサブスクライバが `orders.proposed` ペイロードから注入するのか、それとも `FirestoreRiskSettingsRepository.loadRiskExposure` を呼んで Firestore から取得するのかが未確定。実装者は Issue #44 着手前に人間の判断を仰ぐこと。
- **OQ-2**: `POST /internal/orders/{identifier}/approve|reject` の認証方法。GCP IAM の Service Account トークン検証を Servant ミドルウェアで行うか、Cloud Run の ingress=internal のみで代替するか。本 spec では実装を必須化しないが、セキュリティレビュー前に確認が必要。
- **OQ-3**: Pub/Sub プッシュサブスクリプション vs プルサブスクリプション。data-collector はプッシュ（HTTP POST）を採用しているが、risk-guard も同じ方式を使うかプル（`pullMessages` ポーリング）に変えるかが仕様で明示されていない。本 spec はプッシュ（HTTP POST エンドポイント）を前提として記述しているが、変更がある場合は Must-01/02/08 の受入条件を修正する必要がある。
