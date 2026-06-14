# Spec: execution presentation layer — Pub/Sub subscriber + DI wiring + real entrypoint

## Goal

`svc-execution` のプレゼンテーション層を実装する。
`orders.approved` Pub/Sub push を受信してデコードし、全 Port インスタンスを組み立てた上で `executeOrder` を呼び出す。
`backend/execution/src/Main.hs` を real entrypoint として完成させ、`haskell-usecase-wired-into-entrypoint` ルールを waiver なしで満たす。

---

## Must (満たさなければ done でない)

### ファイル構成

- [ ] **Must-01** 以下のファイルが存在する:
  - `backend/execution/src/Presentation/AppM.hs`
  - `backend/execution/src/Presentation/Api.hs`
  - `backend/execution/src/Presentation/PubSubHandler.hs`
  - `backend/execution/src/Main.hs` (実entrypoint、スタブ除去済み)

### Pub/Sub push エンドポイント

- [ ] **Must-02** `Presentation/Api.hs` に `ExecutionAPI` 型が定義され、`POST /pubsub/events` エンドポイントが宣言される。形式: `"pubsub" :> "events" :> ReqBody '[JSON] Value :> Post '[JSON] PubSubPushResponse`。`GET /healthz` は `App.Bootstrap.runHttpService` が提供する `StandardHealthAPI` に委ねる。

- [ ] **Must-03** `Presentation/PubSubHandler.hs` に `processPubSubPush :: AppEnv -> ByteString -> IO PubSubPushResult` が実装される。デコード連鎖:
  1. HTTP ボディ → `Messaging.PubSub.decodePubSubPush @Value` → `CloudEvent Value`
  2. `CloudEvent Value` → `ApprovedOrderEvent`（payload から `identifier`, `symbol`, `side`, `qty`, `trace`, `occurredAt` を取り出す）
  3. `runAppM appEnv $ executeOrder currentTime approvedOrderEvent`

- [ ] **Must-04** `PubSubPushResult` 型が以下のバリアントを持つ: `PubSubPushExecutionSucceeded`, `PubSubPushExecutionDuplicate`, `PubSubPushSchemaInvalid Text`, `PubSubPushExecutionRetryable Text`, `PubSubPushExecutionFailed Text`。HTTP ステータスマッピング (RULE-EX-PRS-001):
  - `PubSubPushExecutionSucceeded` → HTTP 200
  - `PubSubPushExecutionDuplicate` → HTTP 200
  - `PubSubPushSchemaInvalid _` → HTTP 200 (永続的失敗、再配信不要)
  - `PubSubPushExecutionRetryable _` → HTTP 500 (Pub/Sub が再配信)
  - `PubSubPushExecutionFailed _` → HTTP 200 (恒久的失敗、再配信不要)

- [ ] **Must-05** `executeOrder` の結果 (`ExecuteOrderResult`) から `PubSubPushResult` への変換:
  - `ExecuteOrderSucceeded` → `PubSubPushExecutionSucceeded`
  - `ExecuteOrderDuplicate` → `PubSubPushExecutionDuplicate`
  - `ExecuteOrderRetryable` → `PubSubPushExecutionRetryable "retryable"`
  - `ExecuteOrderFailed _ True` → `PubSubPushExecutionRetryable reasonCodeText` (HTTP 500)
  - `ExecuteOrderFailed _ False` → `PubSubPushExecutionFailed reasonCodeText` (HTTP 200)

- [ ] **Must-06** `CloudEvent Value` から `ApprovedOrderEvent` への変換では、payload JSON オブジェクトから以下を取り出す: `identifier` (ULID 文字列 → `OrderExecutionIdentifier`)。`ExecutionRequest` は `symbol`, `side`, `qty` (payload 内) から構築する。`trace` は `cloudEvent.trace` から `Trace` 型に変換。`occurredAt` は `cloudEvent.occurredAt`。変換失敗時は `PubSubPushSchemaInvalid` を返す。

### DI 配線（AppM / AppEnv）

- [ ] **Must-07** `Presentation/AppM.hs` に `AppEnv` レコードと `AppM`（`newtype AppM a = AppM { unAppM :: ReaderT AppEnv IO a }`）が定義される。`AppM` は `executeOrder` の型クラス制約をすべて満たすインスタンスを提供する:
  - `OrderExecutionRepository AppM` → `FirestoreOrderExecutionRepositoryT` へ委譲
  - `BrokerPort AppM` → `BrokerT` へ委譲
  - `ExecutionEventPublisher AppM` → `PubSubExecutionEventPublisherT` へ委譲

- [ ] **Must-08** `AppEnv` は以下のサブ環境フィールドを持つ:
  - `firestoreOrderExecutionEnv :: FirestoreOrderExecutionEnv`
  - `brokerEnv :: BrokerEnv`
  - `pubSubExecutionEnv :: PubSubExecutionEventPublisherEnv`
  - `logEnv :: LogEnv`

- [ ] **Must-09** `buildAppEnv :: IO AppEnv` が実装され、以下の環境変数を読み込む。いずれかが欠損した場合は起動失敗する:
  - `GCP_PROJECT_ID` または `GOOGLE_CLOUD_PROJECT` (CommonRuntimeEnv 経由)
  - `PORT` (CommonRuntimeEnv 経由、デフォルト 8080)
  - `SERVICE_VERSION`
  - `BROKER_API_TOKEN`
  - `BROKER_BASE_URL`
  - `PUBSUB_EXECUTED_TOPIC`
  - `PUBSUB_EXECUTION_FAILED_TOPIC`
  - `PUBSUB_DEMO_COMPLETED_TOPIC`
  - `FIRESTORE_DATABASE_ID` (省略時 `"(default)"`)

### real entrypoint（Main.hs）

- [ ] **Must-10** `backend/execution/src/Main.hs` を全面置換し、以下の構造とする:
  ```haskell
  main :: IO ()
  main = do
    appEnv <- buildAppEnv
    runHttpService
      HttpServiceOptions { serviceName = "execution", ... }
      executionApiProxy
      (executionServer appEnv)
  ```
  現在のスタブ実装（`healthCheckHandler` / `statusHandler` を直接 `run` する形式）はすべて除去する。

- [ ] **Must-11** `Main.hs` が `Presentation.Api.executionApiProxy` と `Presentation.Api.executionServer` を import し `runHttpService` に渡すことで、`wiring_manifest.yml` の `haskell-usecase-wired-into-entrypoint` ルールを **waiver なし** で満たす。

### ヘルスチェック

- [ ] **Must-12** `GET /healthz` が HTTP 200 とプレーンテキスト `"ok"` を返す。`App.Bootstrap.runHttpService` が提供する `StandardHealthAPI` として実装される。

### 構造化ログ

- [ ] **Must-13** `processPubSubPush` は以下のイベントで `logInfoWith` / `logErrorWith` を呼び出し、`LogContext { service = "execution", trace, identifier, ... }` を含める:
  - Pub/Sub push 受信時: `"pubsub_push_received"`
  - 処理完了時: `"pubsub_push_processed"` (result フィールドあり)
  - デコード失敗時: `"pubsub_decode_failed"` (logErrorWith)

---

## Tests

- [ ] **TST-PRES-001** `processApprovedOrderEvent` (または `processPubSubPushWith`) の unit test: 成功ケース → `PubSubPushExecutionSucceeded`
- [ ] **TST-PRES-002** デコード失敗（不正 JSON body）→ `PubSubPushSchemaInvalid`
- [ ] **TST-PRES-003** `executeOrderResultToPushResult` 変換の全5バリアントのテスト
- [ ] **TST-PRES-004** `/healthz` smoke test: `cabal run execution -- +RTS -N` 起動後 `curl -fsS localhost:8080/healthz` が `"ok"` を返す（CI integration test で実行）

---

## Non-goals

- `CompleteDemoRun` usecase の DI 配線（DemoRunEvaluationRepository は未実装 infra）— waiver 許可
- Servant JWT 認証ミドルウェア（BFF が外部認証を担う）
- メトリクスエンドポイント実装

---

## Wiring waivers

- `DemoCompletionEventPublisher AppM`: `PubSubExecutionEventPublisherT` の `publishHypothesisDemoCompleted` メソッドは実装済みだが、`completeDemoRun` usecase の `DemoRunEvaluationRepository` 具象実装が未完のため AppM インスタンス提供を延期する。`AppM` に `DemoCompletionEventPublisher` インスタンスは追加するが `completeDemoRun` への入口は Issue #49 スコープ外とする。
