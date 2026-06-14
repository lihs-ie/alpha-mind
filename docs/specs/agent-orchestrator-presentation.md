# Spec: agent-orchestrator-presentation

## Goal

- `agent-orchestrator` の **プレゼンテーション層** を実装し、サービスを実際に起動可能な状態にする。
- `insight.collected` と `hypothesis.retest.requested` の Pub/Sub push メッセージを受信する HTTP エンドポイント (`POST /pubsub/events`) を Servant で提供する。
- すべてのインフラ層・ユースケース層をフラットな `ReaderT AppEnv IO` モナド (`AppM`) で結線し、`buildAppEnv` が環境変数から `AppEnv` を構築する。
- `src/Main.hs` を `data-collector` と同じ `buildAppEnv → runHttpService` パターンで置き換える。

---

## Must (満たさなければ done でない)

### モジュール構成

- [ ] **Must-01** 以下の 3 モジュールが対応するファイルパスに存在し、`agent-orchestrator.cabal` の `executable agent-orchestrator` セクションの `other-modules` または `library` セクションの `exposed-modules` に追加（もしくはインライン実装）される。
  - `Presentation.AppM` — `AppEnv`, `AppM`, `runAppM`, `buildAppEnv`
  - `Presentation.Api` — `AgentOrchestratorAPI`, `agentOrchestratorApiProxy`, `agentOrchestratorServer`
  - `Presentation.PubSubHandler` — `handlePubSubPush`, `processPubSubPush`, `processPubSubPushWith`, `PubSubPushResult`
- [ ] **Must-02** `src/Main.hs` が以下の構造で完全に置き換えられる（プレースホルダーの `ServiceStatus` / `statusHandler` /<br>`HealthCheckAPI` のインライン定義は削除される）。
  ```haskell
  main :: IO ()
  main = do
    appEnv <- buildAppEnv
    runHttpService
      HttpServiceOptions
        { serviceName = "agent-orchestrator"
        , serviceVersion = "0.1.0"
        , metricsPath = Nothing
        , middlewareStack = []
        , beforeRun = pure ()
        }
      agentOrchestratorApiProxy
      (agentOrchestratorServer appEnv)
  ```
  `GET /healthz` は `App.Bootstrap.runHttpService` が `StandardHealthAPI` として自動マウントするため、`Main.hs` に再実装しない。

### buildAppEnv — 環境変数読み込み

- [ ] **Must-03** `buildAppEnv :: IO AppEnv` が以下の環境変数をすべて読み込む。欠損した場合は `throwIO (MissingEnv "<NAME>")` で即時終了する。

  | 変数名 | 必須/任意 | デフォルト | 用途 |
  |---|---|---|---|
  | `GCP_PROJECT_ID` または `GOOGLE_CLOUD_PROJECT` | 必須 | — | Firestore `projectIdentifier` |
  | `SERVICE_VERSION` | 必須 | — | `HttpServiceOptions.serviceVersion` |
  | `PORT` | 任意 | `8080` | Warp listen port |
  | `FIRESTORE_DATABASE_ID` | 任意 | `"(default)"` | Firestore `databaseIdentifier` |
  | `PUBSUB_TOPIC_HYPOTHESIS` | 必須 | — | `HypothesisPublisherEnv.topicName` |
  | `SKILL_EXECUTOR_ENDPOINT` | 必須 | — | `SkillExecutorEnv.endpointUrl` |
  | `LOG_LEVEL` | 任意 | `"info"` | katip ログレベル |

  環境変数名の定数は既存モジュール (`Infrastructure.Firestore.Env.gcpProjectIdEnvVar`, `Infrastructure.Firestore.Env.firestoreDatabaseIdEnvVar`, `Infrastructure.PubSub.HypothesisEventPublisher.hypothesisPubSubTopicEnvVar`, `Infrastructure.ACL.SkillExecutorT.skillExecutorEndpointEnvVar`) を参照し、文字列リテラルの重複定義を行わない。

- [ ] **Must-04** `buildAppEnv` は `Config.Env.loadCommonRuntimeEnv "agent-orchestrator"` を呼び出し、`CommonRuntimeEnv` を取得してから各サブ環境を構築する。`LogEnv` は `Observability.Logging.initLogger runtimeEnv` で初期化する。

### AppEnv / AppM — DI 結線

- [ ] **Must-05** `AppEnv` レコードが以下のフィールドを持つ。

  | フィールド名 | 型 |
  |---|---|
  | `firestoreEnv` | `Infrastructure.Firestore.Env.FirestoreEnv` |
  | `skillExecutorEnv` | `Infrastructure.ACL.SkillExecutorT.SkillExecutorEnv` |
  | `hypothesisPublisherEnv` | `Infrastructure.PubSub.HypothesisEventPublisher.HypothesisPublisherEnv` |
  | `logEnv` | `Observability.Logging.LogEnv` |

- [ ] **Must-06** `AppM` は `newtype AppM a = AppM { unAppM :: ReaderT AppEnv IO a }` として定義され、`Functor`, `Applicative`, `Monad`, `MonadIO` を `deriving newtype` で導出する。
- [ ] **Must-07** `AppM` が以下のドメインポート型クラスのインスタンスをすべて持ち、各インスタンスは対応するインフラ実装の `run*T` 関数にデリゲートする。

  | 型クラス | デリゲート先 |
  |---|---|
  | `OrchestrationDispatchRepository` | `Infrastructure.Firestore.OrchestrationDispatchRepository` の実行関数 |
  | `HypothesisProposalRepository` | `Infrastructure.Firestore.HypothesisProposalRepository` の実行関数 |
  | `SkillRegistryRepository` | `Infrastructure.Firestore.SkillRegistryRepository` の実行関数 |
  | `InstructionProfileRepository` | `Infrastructure.Firestore.InstructionProfileRepository` の実行関数 |
  | `FailureKnowledgeRepository` | `Infrastructure.Firestore.FailureKnowledgeRepository` の実行関数 |
  | `SkillExecutor` | `Infrastructure.ACL.SkillExecutorT.runSkillExecutorT` |

  各インスタンスメソッドは `AppM $ do { env <- ask; liftIO $ run*T env.<subEnv> action }` のパターンで実装する。

### Servant API 型 — Pub/Sub エンドポイント

- [ ] **Must-08** `AgentOrchestratorAPI` が以下の型を持つ。
  ```haskell
  type AgentOrchestratorAPI =
    "pubsub" :> "events" :> ReqBody '[JSON] Value :> Post '[JSON] PubSubPushResponse
  ```
  `PubSubPushResponse` は `{ result :: Text }` フィールドを持ち `ToJSON` インスタンスを持つ。
- [ ] **Must-09** `agentOrchestratorServer :: AppEnv -> Server AgentOrchestratorAPI` が存在し、受け取った `Value` を `Data.Aeson.encode` で `ByteString` に変換してから `handlePubSubPush` へ渡す。

### Pub/Sub ハンドラ — CloudEvents デコード

- [ ] **Must-10** `processPubSubPushWith` が以下のシグネチャで存在する（`data-collector` の同名関数に倣う）。
  ```haskell
  processPubSubPushWith ::
    LogEnv ->
    (UTCTime -> OrchestrationDispatchIdentifier -> HypothesisProposalIdentifier ->
     FailureKnowledgeIdentifier -> CloudEventPayload -> IO OrchestrationResult) ->
    ByteString ->
    IO PubSubPushResult
  ```
  ユースケース実行関数を引数で受け取ることで、テスト時にモックに差し替え可能なシームを提供する。`CloudEventPayload` はデコード済みの `eventType`・`identifier`・`trace`・`occurredAt`・`payload` を持つ中間型とする。

- [ ] **Must-11** Pub/Sub push ボディのデコードチェーンが以下の順序で実行される。
  1. 生 HTTP ボディ → `Messaging.PubSub.decodePubSubPush` → `CloudEvent Value`
  2. `CloudEvent.eventType` が `"insight.collected"` → `InsightCollectedEvent` として解釈
  3. `CloudEvent.eventType` が `"hypothesis.retest.requested"` → `RetestRequestedEvent` として解釈
  4. `CloudEvent.eventType` がそれ以外 → `PubSubPushUnknownEventType` として処理し、HTTP 200 で返す（ack、再配信しない）
  5. `CloudEvent.payload` の JSON パース失敗 → `PubSubPushSchemaInvalid` として処理し、HTTP 200 で返す
  6. 上記成功後、対応するユースケース関数 (`orchestrateFromInsight` / `orchestrateFromRetest`) を呼び出す

- [ ] **Must-12** `CloudEvent.identifier` (ULID) から `OrchestrationDispatchIdentifier` を、新規 ULID から `HypothesisProposalIdentifier` と `FailureKnowledgeIdentifier` をそれぞれ生成して、ユースケース関数に渡す。ULID の採番は `Data.ULID.getULID` で行う。

- [ ] **Must-13** `PubSubPushResult` 型が以下のコンストラクタを持ち、HTTP ステータスマッピングが次のとおりになる。

  | コンストラクタ | HTTP ステータス | 理由 |
  |---|---|---|
  | `PubSubPushOrchestrationSucceeded` | 200 | 正常完了 |
  | `PubSubPushOrchestrationDuplicate` | 200 | 冪等済み (AlreadyProcessed) — 再配信不要 |
  | `PubSubPushSchemaInvalid Text` | 200 | 永続的デコードエラー — 再配信しても同じ結果 |
  | `PubSubPushUnknownEventType Text` | 200 | 対象外イベント — ack して無視 |
  | `PubSubPushOrchestrationFailed Text` | 500 | 一時的エラー (DependencyTimeout 等) — 再配信させる |

- [ ] **Must-14** `DomainError` を `PubSubPushResult` にマッピングする際、`NonRetryableReasonSpecification.isSatisfiedBy` を使って `ResourceNotFound` / `RequestValidationFailed` を `PubSubPushSchemaInvalid` (200)、それ以外を `PubSubPushOrchestrationFailed` (500) に振り分ける。`AlreadyProcessed IdempotencyDuplicateEvent` は `PubSubPushOrchestrationDuplicate` (200) にマッピングする。

### ヘルスチェックエンドポイント

- [ ] **Must-15** `GET /healthz` エンドポイントが存在し、HTTP 200 とボディ `"ok"` を返す。このエンドポイントは `App.Bootstrap.runHttpService` が `StandardHealthAPI` として自動マウントするため、`Presentation.Api` モジュールの `AgentOrchestratorAPI` 型には含めない。

### ログ出力

- [ ] **Must-16** Pub/Sub メッセージ受信時に `logInfoWith` で構造化ログを出力する。`LogContext` フィールドに `service = "agent-orchestrator"`, `trace`, `identifier`, `eventType` を含める。
- [ ] **Must-17** 処理完了時（成功・失敗問わず）に `logInfoWith` / `logErrorWith` で `result` フィールドを含む構造化ログを出力する。

### cabal 変更

- [ ] **Must-18** `agent-orchestrator.cabal` の `executable agent-orchestrator` セクションの `build-depends` に、プレゼンテーション層が必要とする以下のパッケージが追加される。
  - `shared` (App.Bootstrap, Config.Env, Messaging.PubSub, Observability.Logging)
  - `http-client-tls` (`newTlsManager` 使用のため)
  - 既存: `servant-server`, `warp`, `aeson`, `bytestring`, `text`, `time`, `ulid`

### 統合テスト — プロセス内、実 GCP 呼び出しなし

- [ ] **Must-19** `test/Presentation/PubSubHandlerSpec.hs` が存在し、`cabal test agent-orchestrator` でパスする。
- [ ] **Must-20** `PubSubHandlerSpec` のすべてのテストケースは `processPubSubPushWith` の第 2 引数（ユースケース実行関数）をインメモリのスタブに差し替えて実行し、Firestore・Pub/Sub・SkillExecutor への実ネットワーク呼び出しを一切行わない。
  - 確認方法: テストコードに `newTlsManager` / `googleApplicationCredentials` / `GOOGLE_APPLICATION_CREDENTIALS` / `pubsub.googleapis.com` / `firestore.googleapis.com` への参照が存在しないことを `grep` で確認。
- [ ] **Must-21** `PubSubHandlerSpec` が以下の最低限テストケースを含む。
  - `insight.collected` 正常系: 有効な Pub/Sub push ボディ（`eventType="insight.collected"` の CloudEvents JSON を base64 エンコードしたもの）を `processPubSubPushWith` に渡す → スタブが `Right ()` を返す → `PubSubPushOrchestrationSucceeded` が返る。
  - `insight.collected` 冪等済み: スタブが `Left (AlreadyProcessed IdempotencyDuplicateEvent)` を返す → `PubSubPushOrchestrationDuplicate` が返る。
  - `hypothesis.retest.requested` 正常系: `eventType="hypothesis.retest.requested"` の push ボディ → `PubSubPushOrchestrationSucceeded` が返る。
  - スキーマ無効: 不正な JSON ボディ → `PubSubPushSchemaInvalid` が返る。
  - 非再試行エラー: スタブが `Left (InvariantViolation _ _ ResourceNotFound)` を返す → `PubSubPushSchemaInvalid` (200) が返る。
  - 再試行可能エラー: スタブが `Left (InvariantViolation _ _ DependencyTimeout)` を返す → `PubSubPushOrchestrationFailed` (500) が返る。
  - 未知 eventType: `eventType="unknown.event"` の push ボディ → `PubSubPushUnknownEventType` が返る。
- [ ] **Must-22** `test/Presentation/` 配下の spec ファイルが `agent-orchestrator.cabal` の `test-suite agent-orchestrator-test` セクションの `other-modules` に追加される。

### ビルド・品質

- [ ] **Must-23** `cd backend && cabal build agent-orchestrator 2>&1 | grep -c "^Error"` が `0` を返す。
- [ ] **Must-24** `cd backend && cabal test agent-orchestrator 2>&1 | tail -5` に `0 failures` が含まれる。
- [ ] **Must-25** `hlint backend/agent-orchestrator/src/Presentation/ backend/agent-orchestrator/test/Presentation/ 2>&1 | grep -c "Warning\|Error"` が `0` を返す（または `ci/allowlist.yml` 登録済み例外のみ）。
- [ ] **Must-26** `Presentation.AppM` は `Domain.*` および `Infrastructure.*` モジュールのみをインポートし、`UseCase.*` のユースケース関数は `Presentation.PubSubHandler` 経由でのみ呼び出す。`Presentation.AppM` は直接 `UseCase.*` をインポートしない。
- [ ] **Must-27** `src/Main.hs` に `StatusAPI`, `ServiceStatus`, `statusHandler` の定義が存在しない（プレースホルダーコードが削除されている）ことを `grep -n "ServiceStatus\|statusHandler\|StatusAPI" backend/agent-orchestrator/src/Main.hs` が 0 行を返すことで確認する。

---

## Should (望ましいが必須でない)

- `processPubSubPushWith` の `LogContext` に `payloadSummary` フィールドとして `eventType` と `identifier` の組み合わせ文字列を含める。
- `buildAppEnv` の HTTP マネージャ (`newTlsManager`) を Firestore・SkillExecutor 間で共有し、接続数を削減する。
- `AppEnv` に `serviceName :: Text` フィールドを持たせ、ログ出力時の `LogContext.service` に使用する（`data-collector` パターンとの統一）。
- `PubSubHandlerSpec` にプロパティベーステスト (QuickCheck) を追加し、ランダムな不正 JSON に対して常に `PubSubPushSchemaInvalid` または `PubSubPushUnknownEventType` が返ることを検証する。

---

## 受入条件 (acceptance — Must の確認方法)

- **Must-01** → `ls backend/agent-orchestrator/src/Presentation/` の出力に `AppM.hs`, `Api.hs`, `PubSubHandler.hs` の 3 ファイルが含まれる。
- **Must-02** → `cat backend/agent-orchestrator/src/Main.hs` の出力に `buildAppEnv`, `runHttpService`, `agentOrchestratorApiProxy`, `agentOrchestratorServer` が含まれ、`ServiceStatus` が含まれない。
- **Must-03** → `grep -n "requireTextEnv\|optionalTextEnv\|loadCommonRuntimeEnv" backend/agent-orchestrator/src/Presentation/AppM.hs` が 5 行以上を返す。`SKILL_EXECUTOR_ENDPOINT`, `PUBSUB_TOPIC_HYPOTHESIS` が参照されていることを同ファイル内で `grep` 確認。
- **Must-04** → `grep "loadCommonRuntimeEnv\|initLogger" backend/agent-orchestrator/src/Presentation/AppM.hs` が各 1 行以上を返す。
- **Must-05** → `grep -n "firestoreEnv\|skillExecutorEnv\|hypothesisPublisherEnv\|logEnv" backend/agent-orchestrator/src/Presentation/AppM.hs` が 4 行以上を返す。
- **Must-06** → `grep "newtype AppM\|ReaderT AppEnv IO" backend/agent-orchestrator/src/Presentation/AppM.hs` が 1 行以上を返す。
- **Must-07** → `grep -n "instance.*Repository\|instance.*SkillExecutor" backend/agent-orchestrator/src/Presentation/AppM.hs` が 6 行以上を返す。`cd backend && cabal build agent-orchestrator` がゼロエラーで完了する（型クラスインスタンスの網羅性チェックを GHC が通過する）。
- **Must-08** → `grep "AgentOrchestratorAPI\|pubsub.*events\|ReqBody" backend/agent-orchestrator/src/Presentation/Api.hs` が 3 行以上を返す。
- **Must-09** → `grep "agentOrchestratorServer\|handlePubSubPush" backend/agent-orchestrator/src/Presentation/Api.hs` が 2 行以上を返す。
- **Must-10** → `grep "processPubSubPushWith" backend/agent-orchestrator/src/Presentation/PubSubHandler.hs` が 1 行以上を返す。
- **Must-11** → `cd backend && cabal test agent-orchestrator --test-show-details=streaming` の `PubSubHandlerSpec` 出力に `insight.collected` および `hypothesis.retest.requested` のデコード正常系テストケースが `✓` で表示される。
- **Must-12** → `grep "getULID" backend/agent-orchestrator/src/Presentation/PubSubHandler.hs` が 1 行以上を返す（ULID 採番の存在確認）。
- **Must-13** → `grep -n "PubSubPushOrchestrationSucceeded\|PubSubPushOrchestrationDuplicate\|PubSubPushSchemaInvalid\|PubSubPushUnknownEventType\|PubSubPushOrchestrationFailed" backend/agent-orchestrator/src/Presentation/PubSubHandler.hs` が 5 行を返す。
- **Must-14** → `cd backend && cabal test agent-orchestrator --test-show-details=streaming` の `PubSubHandlerSpec` に `ResourceNotFound → 200`, `DependencyTimeout → 500`, `AlreadyProcessed → 200` の各テストケースが `✓` で表示される。
- **Must-15** → `curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/healthz`（サービス起動時）が `200` を返す。またはテストコード内で `App.Bootstrap.mkApplication` を使って WAI テストを実行し、`GET /healthz` が 200 を返すことを assert する。
- **Must-16** → `grep "logInfoWith\|logEnv\|LogContext" backend/agent-orchestrator/src/Presentation/PubSubHandler.hs` が 3 行以上を返す。
- **Must-17** → `grep "logErrorWith\|result\s*=" backend/agent-orchestrator/src/Presentation/PubSubHandler.hs` が 1 行以上を返す。
- **Must-18** → `grep "http-client-tls\|shared" backend/agent-orchestrator/agent-orchestrator.cabal` が executable セクションに 2 行以上を返す。
- **Must-19** → `ls backend/agent-orchestrator/test/Presentation/PubSubHandlerSpec.hs` が終了コード 0 を返す。
- **Must-20** → `grep -rn "newTlsManager\|googleApplicationCredentials\|GOOGLE_APPLICATION_CREDENTIALS\|pubsub.googleapis.com\|firestore.googleapis.com" backend/agent-orchestrator/test/Presentation/` の結果がゼロ行。
- **Must-21** → `cd backend && cabal test agent-orchestrator --test-show-details=streaming` の `PubSubHandlerSpec` セクションに Must-21 で列挙した 7 ケースがすべて `✓` で表示される。
- **Must-22** → `grep "Presentation.PubSubHandlerSpec" backend/agent-orchestrator/agent-orchestrator.cabal` が 1 行を返す。
- **Must-23** → `cd backend && cabal build agent-orchestrator 2>&1 | grep -c "^Error"` が `0` を返す。
- **Must-24** → `cd backend && cabal test agent-orchestrator 2>&1 | tail -5` に `0 failures` が含まれる。
- **Must-25** → `hlint backend/agent-orchestrator/src/Presentation/ backend/agent-orchestrator/test/Presentation/ 2>&1 | grep -c "Warning\|Error"` が `0` を返す（または `ci/allowlist.yml` 登録済み例外のみ）。
- **Must-26** → `grep -rn "^import UseCase" backend/agent-orchestrator/src/Presentation/AppM.hs` の結果がゼロ行。
- **Must-27** → `grep -n "ServiceStatus\|statusHandler\|StatusAPI" backend/agent-orchestrator/src/Main.hs` の結果がゼロ行。

---

## Non-goals (今回やらない)

- ドメイン層・ユースケース層・インフラ層のコード変更（前 Issue で完結済み）。
- `hypothesis.proposed` / `hypothesis.proposal.failed` の Pub/Sub 発行ロジック（`HypothesisEventPublisher` はインフラ層で実装済み。プレゼンテーション層はユースケースの `Right ()` 結果を HTTP 200 にマッピングするのみで、発行責任はユースケース層が持つ）。
- 実 GCP Firestore・Pub/Sub・SkillExecutor への統合テスト / E2E テスト。
- Terraform / Cloud Run デプロイ設定の変更。
- `HypothesisReportRepository`（Cloud Storage 書き込み）の実装。
- 認証・認可ミドルウェア（Pub/Sub push は GCP IAM で保護するためアプリ層の JWT 検証不要）。
- メトリクスエンドポイント (`/metrics`) の追加（`HttpServiceOptions.metricsPath = Nothing` で無効化）。
- `insight-collector`, `hypothesis-lab`, `bff` など他サービスへの変更。

---

## Risk

- level: high-risk
- escalate_to_opus: true
- 理由: 以下の境界領域に触れる。
  - `DI`: `AppM` の型クラスインスタンス実装誤りは、全 6 ポートのインフラ実装が正しく呼び出されない無音バグを生む。
  - `event subscription`: Pub/Sub push デコードチェーン・`eventType` の文字列分岐の誤りは、`insight.collected` が無視されるかログなし DLQ 送りになる。
  - `routing`: HTTP ステータスマッピング誤り（500 を返すべきところで 200 を返す）は Pub/Sub の再配信ループを止め、障害が隠蔽される。
  - `config`: `buildAppEnv` で必須環境変数の読み込み漏れは、サービス起動後に実行時エラーとして顕在化し、`SKILL_EXECUTOR_ENDPOINT` 未設定なら全ユースケースが失敗する。
  - `background job`: `orchestrateFromInsight` の呼び出しが行われないまま 200 を返す実装ミスは、仮説生成が無音で停止する。

---

## Open questions (あれば)

- **OQ-01** `processPubSubPushWith` のユースケース実行関数シグネチャ内の中間型 (`CloudEventPayload`) を独立した型として定義するか、既存の `InsightCollectedEvent` / `RetestRequestedEvent` を直和型でラップするかは実装者に委ねる。スペックは「ユースケース実行関数が差し替え可能なシームであること」を要求するが、具体的な型の形は要求しない。
- **OQ-02** `AppEnv` の `http-client` TLS マネージャを Firestore と SkillExecutor で共有する場合、`FirestoreEnv.firestoreExecute.transportGetDocument` 等のトランスポート関数に `Manager` を閉じ込める実装か、`AppEnv` 直下に `httpManager :: Manager` フィールドを持たせる実装かは未確定。どちらでも `Must-05` を満たせるが、テストのモック差し替えに影響するため選択を明確にすること。
- **OQ-03** `HypothesisEventPublisher.publishHypothesisProposed` / `publishHypothesisProposalFailed` の呼び出しタイミングについて — 現在のユースケース実装 (`HypothesisOrchestrationService`) は `SkillExecutor` を実行した後に `OrchestrationDispatch.markPublished` を呼び出すが、Pub/Sub への実際の発行は `HypothesisEventPublisher` が担う。プレゼンテーション層がユースケース完了後に別途 `publishHypothesisProposed` を呼び出す設計か、ユースケース層の型クラス制約に `HypothesisEventPublisher` の型クラスを追加する設計かが確定していない。人間判断が必要。
