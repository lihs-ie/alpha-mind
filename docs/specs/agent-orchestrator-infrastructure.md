# Spec: agent-orchestrator-infrastructure

## Goal

- `agent-orchestrator` の **インフラ層のみ** を実装する。
- ドメイン層が定義した 5 つのリポジトリ型クラス（`SkillRegistryRepository`, `InstructionProfileRepository`, `CodeReferenceTemplateRepository`, `FailureKnowledgeRepository`, `HypothesisProposalRepository`）および `OrchestrationDispatchRepository` の Firestore 実装を `Infrastructure.Firestore.*` モジュールとして提供する。
- `hypothesis.proposed` / `hypothesis.proposal.failed` の CloudEvents 互換 JSON を Pub/Sub へ発行する `HypothesisEventPublisher` を `Infrastructure.PubSub.HypothesisEventPublisher` モジュールとして提供する。
- プレゼンテーション層・`Main.hs` の DI 配線は対象外とし、ユースケース層・ドメイン層は変更しない。

---

## Must (満たさなければ done でない)

### モジュール存在・cabal 登録

- [ ] **Must-01** 以下の 7 モジュールが対応するファイルパスに存在し、`agent-orchestrator.cabal` の `library` セクションの `exposed-modules` に追加される。
  - `Infrastructure.Firestore.SkillRegistryRepository`
  - `Infrastructure.Firestore.InstructionProfileRepository`
  - `Infrastructure.Firestore.CodeReferenceTemplateRepository`
  - `Infrastructure.Firestore.FailureKnowledgeRepository`
  - `Infrastructure.Firestore.HypothesisProposalRepository`
  - `Infrastructure.Firestore.OrchestrationDispatchRepository`
  - `Infrastructure.PubSub.HypothesisEventPublisher`

### Firestore 環境設定（FirestoreEnv）

- [ ] **Must-02** `Infrastructure.Firestore.Env` モジュール（または各リポジトリモジュール内の定義）に `FirestoreEnv` レコードが存在し、以下のフィールドを持つ。
  - `firestoreExecute :: CollectionReference -> DocumentReference -> FirestoreRequest -> IO FirestoreResponse` — テストでモック差し替え可能な Firestore トランスポート関数（gogol-firestore の具体型をラップした型エイリアスでも可）。
  - `projectIdentifier :: Text` — GCP プロジェクト ID（環境変数 `GCP_PROJECT_ID` から読み込む値; `FirestoreEnv` 自体は純粋なレコード）。
  - `databaseIdentifier :: Text` — Firestore データベース ID（`"(default)"` または名前付きデータベース）。
- [ ] **Must-03** 環境変数名 `GCP_PROJECT_ID` がモジュール内定数または Haddock コメントに明記される。

### SkillRegistryRepository — Firestore 実装

- [ ] **Must-04** `Infrastructure.Firestore.SkillRegistryRepository` に `SkillRegistryRepository` 型クラスの `IO` インスタンスが実装され、以下 3 メソッドを充足する。
  - `find :: Text -> IO (Maybe Skill)` — コレクション `skill_registry`、ドキュメント ID `identifier` で点取得する。ドキュメントが存在しない場合は `Nothing` を返す。
  - `findByStatus :: SkillStatus -> IO [Skill]` — `status` フィールドで等値フィルタをかけて一覧取得する。
  - `search :: SkillSearchCriteria -> IO [Skill]` — `nameFilter`・`statusFilter`・`limitCount` を適用して取得する。
- [ ] **Must-05** Firestore ドキュメントフィールド `status` は `"active"` / `"deprecated"` / `"draft"` のみを受け付け、未知値はデコードエラーとして `Left DomainError` または例外に変換する。

### InstructionProfileRepository — Firestore 実装

- [ ] **Must-06** `Infrastructure.Firestore.InstructionProfileRepository` に `InstructionProfileRepository` 型クラスの `IO` インスタンスが実装され、以下 3 メソッドを充足する。
  - `find :: Text -> IO (Maybe InstructionProfile)` — コレクション `instruction_profiles`、ドキュメント ID `identifier` で点取得する。
  - `findByVersion :: Text -> IO (Maybe InstructionProfile)` — `version` フィールドで等値フィルタをかけて最初の 1 件を取得する。
  - `search :: InstructionProfileSearchCriteria -> IO [InstructionProfile]` — `nameFilter`・`limitCount` を適用して取得する。
- [ ] **Must-07** Firestore ドキュメントフィールド `contentPath` を `InstructionProfile.content` へマッピングする際、フィールド欠損は `DomainError`（`MissingRequiredFields ["contentPath"] ResourceNotFound` 相当）として返す。

### CodeReferenceTemplateRepository — Firestore 実装

- [ ] **Must-08** `Infrastructure.Firestore.CodeReferenceTemplateRepository` に `CodeReferenceTemplateRepository` 型クラスの `IO` インスタンスが実装され、以下 3 メソッドを充足する。
  - `find :: Text -> IO (Maybe CodeReferenceTemplate)` — コレクション `code_reference_templates`、ドキュメント ID `identifier` で点取得する。
  - `findByScope :: Text -> IO [CodeReferenceTemplate]` — `scope` フィールドで等値フィルタをかけて一覧取得する（複合インデックス `scope ASC, updatedAt DESC` に依存する）。
  - `search :: CodeReferenceTemplateSearchCriteria -> IO [CodeReferenceTemplate]` — `scopeFilter`・`limitCount` を適用して取得する。
- [ ] **Must-09** Firestore ドキュメントフィールド `markdownPath` を `CodeReferenceTemplate.content` へマッピングする際、フィールド欠損は `DomainError` として返す。

### FailureKnowledgeRepository — Firestore 実装

- [ ] **Must-10** `Infrastructure.Firestore.FailureKnowledgeRepository` に `FailureKnowledgeRepository` 型クラスの `IO` インスタンスが実装され、以下 4 メソッドを充足する。
  - `find :: FailureKnowledgeIdentifier -> IO (Maybe FailureKnowledge)` — コレクション `failure_knowledge`、ドキュメント ID `identifier.value`（ULID 文字列）で点取得する。
  - `findByReasonCode :: ReasonCode -> IO [FailureKnowledge]` — `reasonCode` フィールドで等値フィルタをかけて取得する。
  - `search :: FailureKnowledgeSearchCriteria -> IO [FailureKnowledge]` — `reasonCodeFilter`・`similarityHashFilter`・`limitCount` を適用して取得する（複合インデックス `similarityHash ASC, createdAt DESC` に依存する）。
  - `persist :: FailureKnowledge -> IO ()` — ドキュメント ID `identifier.value` で upsert する。`markdownSummary`・`similarityHash` を必ず書き込む。
- [ ] **Must-11** `persist` 時にドキュメントフィールド `createdAt` は RFC3339（ISO8601 UTC）形式のタイムスタンプとして書き込む。

### HypothesisProposalRepository — Firestore 実装

- [ ] **Must-12** `Infrastructure.Firestore.HypothesisProposalRepository` に `HypothesisProposalRepository` 型クラスの `IO` インスタンスが実装され、以下 5 メソッドを充足する。
  - `find :: HypothesisProposalIdentifier -> IO (Maybe HypothesisProposal)` — コレクション `hypothesis_registry`、ドキュメント ID `identifier.value`（ULID 文字列）で点取得する。
  - `findByStatus :: ProposalStatus -> IO [HypothesisProposal]` — `status` フィールドで等値フィルタをかけ `updatedAt DESC` で取得する（複合インデックス `status ASC, updatedAt DESC` に依存する）。
  - `search :: ProposalSearchCriteria -> IO [HypothesisProposal]` — `statusFilter`・`symbolFilter`・`limitCount` を適用して取得する。
  - `persist :: HypothesisProposal -> IO ()` — ドキュメント ID `identifier.value` で upsert する。`symbol`・`instrumentType`・`title`・`sourceEvidence`・`skillVersion`・`instructionProfileVersion`・`insiderRisk`・`mnpiSelfDeclared`・`status`・`reasonCode`・`trace`・`updatedAt` をすべて書き込む。
  - `terminate :: HypothesisProposalIdentifier -> IO ()` — ドキュメントを Firestore から物理削除する（またはソフトデリートフィールドを設定する; ソフトデリート採用の場合は Open questions に記載）。
- [ ] **Must-13** Firestore ドキュメントフィールド `status` は `"draft"` / `"backtested"` / `"demo"` / `"live"` / `"rejected"` に対応するが、`HypothesisProposal` のドメインステータス（`pending | proposed | blocked | failed`）とのマッピングテーブルを実装内に明記し、未知値はデコードエラーとして `DomainError` を返す。
- [ ] **Must-14** `persist` 時に `updatedAt` は現在時刻（`UTCTime`）を RFC3339 形式で書き込み、`createdAt` は新規作成時のみ書き込む（upsert のセマンティクス上、既存ドキュメントの `createdAt` を上書きしない）。

### OrchestrationDispatchRepository — Firestore 実装

- [ ] **Must-15** `Infrastructure.Firestore.OrchestrationDispatchRepository` に `OrchestrationDispatchRepository` 型クラスの `IO` インスタンスが実装され、以下 3 メソッドを充足する。
  - `find :: OrchestrationDispatchIdentifier -> IO (Maybe OrchestrationDispatch)` — コレクション `idempotency_keys`、ドキュメント ID `"agent-orchestrator:{identifier.value}"` で点取得する（Firestore 設計 §3.8 のサービスプレフィックス規約に従う）。
  - `persist :: OrchestrationDispatch -> IO ()` — ドキュメント ID `"agent-orchestrator:{identifier.value}"` で upsert する。フィールド `identifier`・`service`（固定値 `"agent-orchestrator"`）・`processedAt`・`trace`・`expiresAt`（30 日後のタイムスタンプ）・`updatedAt` を書き込む。
  - `terminate :: OrchestrationDispatchIdentifier -> IO ()` — ドキュメントを物理削除する。
- [ ] **Must-16** `persist` 時にドキュメントフィールド `expiresAt` は `processedAt` から 30 日後の `UTCTime` を RFC3339 形式で書き込む（Firestore TTL 設計 §6 に準拠）。

### HypothesisEventPublisher — Pub/Sub 実装

- [ ] **Must-17** `Infrastructure.PubSub.HypothesisEventPublisher` モジュールに `HypothesisEventPublisher` newtype が以下の形で定義される。
  ```
  newtype HypothesisEventPublisher m a =
    HypothesisEventPublisher { unHypothesisEventPublisher :: ReaderT HypothesisPublisherEnv m a }
  ```
  `runHypothesisEventPublisher :: HypothesisPublisherEnv -> HypothesisEventPublisher m a -> m a` が公開される。
- [ ] **Must-18** `HypothesisPublisherEnv` レコードが以下のフィールドを持つ。
  - `topicName :: Text` — Pub/Sub トピック名（環境変数 `PUBSUB_TOPIC_HYPOTHESIS` から読み込む値; `HypothesisPublisherEnv` 自体は純粋なレコード）。
  - `pubsubPublish :: Text -> ByteString -> IO ()` — トピック名とメッセージ本文を受け取るモック差し替え可能なトランスポート関数。
- [ ] **Must-19** 環境変数名 `PUBSUB_TOPIC_HYPOTHESIS` がモジュール内定数または Haddock コメントに明記される。
- [ ] **Must-20** `publishHypothesisProposed` 関数が実装され、`HypothesisProposal`（`status=Proposed`）を受け取り、以下の CloudEvents 互換 JSON 構造を持つメッセージを Pub/Sub へ発行する。

  ```json
  {
    "identifier": "<ULID>",
    "eventType": "hypothesis.proposed",
    "occurredAt": "<ISO8601 UTC>",
    "trace": "<ULID>",
    "schemaVersion": "1.0.0",
    "skillVersion": "<string>",
    "instructionProfileVersion": "<string>",
    "payload": {
      "hypothesis": "<HypothesisProposalIdentifier ULID>",
      "symbol": "<string>",
      "instrumentType": "ETF" | "STOCK",
      "title": "<string>",
      "sourceEvidence": ["<string>", ...],
      "insiderRisk": "low" | "medium" | "high" | null,
      "mnpiSelfDeclared": true | false | null,
      "reportPath": "<string>" | null
    }
  }
  ```

  フィールド `identifier` はイベント固有の新規 ULID（`HypothesisProposal.identifier` とは別）、`payload.hypothesis` は `HypothesisProposal.identifier.value` の ULID 文字列とする。

- [ ] **Must-21** `publishHypothesisProposalFailed` 関数が実装され、`HypothesisProposal`（`status=Failed` または `status=Blocked`）と `ReasonCode` を受け取り、以下の CloudEvents 互換 JSON 構造を持つメッセージを Pub/Sub へ発行する。

  ```json
  {
    "identifier": "<ULID>",
    "eventType": "hypothesis.proposal.failed",
    "occurredAt": "<ISO8601 UTC>",
    "trace": "<ULID>",
    "schemaVersion": "1.0.0",
    "payload": {
      "hypothesis": "<HypothesisProposalIdentifier ULID>",
      "reasonCode": "<ReasonCode string>",
      "dispatch": "<dispatch ULID string>"
    }
  }
  ```

- [ ] **Must-22** 発行メッセージの `identifier` フィールドには ULID を新規採番し（`Data.ULID.getULID` 相当）、発行ごとに一意になる。
- [ ] **Must-23** `publishHypothesisProposed` に渡された `HypothesisProposal` の `status` が `Proposed` 以外の場合は `Left (InvalidStateTransition ...)` 相当の `DomainError` を返し、Pub/Sub へ発行しない。
- [ ] **Must-24** `publishHypothesisProposalFailed` に渡された `HypothesisProposal` の `status` が `Failed` でも `Blocked` でもない場合は `Left (InvalidStateTransition ...)` 相当の `DomainError` を返し、Pub/Sub へ発行しない。

### テスト分離（フェイク Firestore・Pub/Sub）

- [ ] **Must-25** 各リポジトリの hspec テストファイル（`test/Infrastructure/Firestore/*Spec.hs`）が存在し、`cabal test agent-orchestrator` でパスする。
- [ ] **Must-26** 全テストは `FirestoreEnv.firestoreExecute` フィールドをインメモリのモック関数で差し替えて実行し、実 GCP Firestore へのネットワーク呼び出しを一切行わない。
  - 確認方法: テストコードに `newManager` / `googleApplicationCredentials` / `GOOGLE_APPLICATION_CREDENTIALS` への参照が存在しないことを `grep` で確認。
- [ ] **Must-27** `HypothesisEventPublisher` の hspec テストファイル（`test/Infrastructure/PubSub/HypothesisEventPublisherSpec.hs`）が存在し、`cabal test agent-orchestrator` でパスする。
- [ ] **Must-28** `HypothesisEventPublisher` のテストは `HypothesisPublisherEnv.pubsubPublish` フィールドをモック関数で差し替えて実行し、実 Pub/Sub エンドポイントへのネットワーク呼び出しを一切行わない。
- [ ] **Must-29** 各リポジトリのテストは以下の最低限ケースを含む。
  - `find` 正常系: モックが有効な Firestore ドキュメント JSON を返す → `Just <entity>` を返す。
  - `find` ドキュメント不在: モックが 404 相当を返す → `Nothing` を返す。
  - `persist` 正常系: モックが成功を返す → `IO ()` が例外なく完了する。
  - フィールド欠損デコードエラー: モックが必須フィールドを欠いた JSON を返す → `DomainError` が返る（または例外が throw される）。
- [ ] **Must-30** `HypothesisEventPublisher` のテストは以下の最低限ケースを含む。
  - `publishHypothesisProposed` 正常系: `status=Proposed` の `HypothesisProposal` を渡す → モックの受け取ったバイト列が有効な JSON かつ `eventType="hypothesis.proposed"` かつ全必須フィールドを含むことを assert する。
  - `publishHypothesisProposalFailed` 正常系: `status=Failed` の `HypothesisProposal` を渡す → `eventType="hypothesis.proposal.failed"` が含まれることを assert する。
  - ガード違反: `status=Pending` の `HypothesisProposal` を `publishHypothesisProposed` に渡す → 発行せず `Left DomainError` を返すことを assert する。

### ビルド・品質

- [ ] **Must-31** `cd backend && cabal build agent-orchestrator` がゼロエラーで完了する。
- [ ] **Must-32** `cd backend && cabal test agent-orchestrator` がゼロ失敗で完了する。
- [ ] **Must-33** `hlint backend/agent-orchestrator/src/Infrastructure/ backend/agent-orchestrator/test/Infrastructure/` がゼロ警告（または `ci/allowlist.yml` 登録済み例外のみ）で終了する。
- [ ] **Must-34** 各インフラモジュールのインポートに `UseCase.*` モジュールが含まれない（インフラ層はドメイン層ポートのみに依存する）。
- [ ] **Must-35** `Main.hs` は本 Issue のスコープで変更しない（`src/Main.hs` に diff が生じない）。

---

## Should (望ましいが必須でない)

- gogol-firestore のレスポンスのデコードに失敗した場合は `katip` 経由で `ErrorS` レベルのログを出力し、`fieldPath`・`docId`・`rawValue` を構造化フィールドに含める。
- `findByStatus`・`findByScope`・`findByReasonCode` 等の一覧取得に `limit` (デフォルト 50) を付与し、無制限スキャンを防ぐ（Firestore 設計 §9 の方針に準拠）。
- `persist` 実装に楽観ロック用 `version` フィールドの書き込みを含める（`hypothesis_registry` は `version` フィールドを持つ; 書き込み競合の検出は将来課題としても可）。
- `publishHypothesisProposed` / `publishHypothesisProposalFailed` 呼び出し時に `katip` 経由でメッセージの `eventType`・`identifier`・`trace` を構造化ログ出力する。
- `FirestoreEnv` と `HypothesisPublisherEnv` の構築関数（環境変数読み込み）をモジュール内に定義し、`Main.hs` の配線コストを下げる（ただし結線自体は Non-goal）。

---

## 受入条件 (acceptance — Must の確認方法)

- **Must-01** → `grep -rn "Infrastructure.Firestore\.\|Infrastructure.PubSub\." backend/agent-orchestrator/agent-orchestrator.cabal` が 7 行以上を返す。各 `.hs` ファイルの存在を `ls backend/agent-orchestrator/src/Infrastructure/Firestore/` と `ls backend/agent-orchestrator/src/Infrastructure/PubSub/HypothesisEventPublisher.hs` で確認する。
- **Must-02** → `grep -n "firestoreExecute\|projectIdentifier\|databaseIdentifier" backend/agent-orchestrator/src/Infrastructure/Firestore/Env.hs` が 3 行以上を返す（または各リポジトリファイル内での確認）。
- **Must-03** → `grep "GCP_PROJECT_ID" backend/agent-orchestrator/src/Infrastructure/Firestore/Env.hs` が 1 行以上を返す。
- **Must-04** → `grep -n "instance SkillRegistryRepository" backend/agent-orchestrator/src/Infrastructure/Firestore/SkillRegistryRepository.hs` が 1 行を返す。`cabal test agent-orchestrator` の `SkillRegistryRepositorySpec` テストがパスする。
- **Must-05** → `cabal test agent-orchestrator` の `SkillRegistryRepositorySpec` デコードエラーテストケース（未知 `status` 値）が `Left DomainError` または例外を返すことを assert してパスする。
- **Must-06** → `grep -n "instance InstructionProfileRepository" backend/agent-orchestrator/src/Infrastructure/Firestore/InstructionProfileRepository.hs` が 1 行を返す。`cabal test agent-orchestrator` の `InstructionProfileRepositorySpec` テストがパスする。
- **Must-07** → `cabal test agent-orchestrator` の `InstructionProfileRepositorySpec` フィールド欠損テストケース（`contentPath` 欠損）が `DomainError` を返すことを assert してパスする。
- **Must-08** → `grep -n "instance CodeReferenceTemplateRepository" backend/agent-orchestrator/src/Infrastructure/Firestore/CodeReferenceTemplateRepository.hs` が 1 行を返す。`cabal test agent-orchestrator` の `CodeReferenceTemplateRepositorySpec` テストがパスする。
- **Must-09** → `cabal test agent-orchestrator` の `CodeReferenceTemplateRepositorySpec` フィールド欠損テストケース（`markdownPath` 欠損）が `DomainError` を返すことを assert してパスする。
- **Must-10** → `grep -n "instance FailureKnowledgeRepository" backend/agent-orchestrator/src/Infrastructure/Firestore/FailureKnowledgeRepository.hs` が 1 行を返す。`cabal test agent-orchestrator` の `FailureKnowledgeRepositorySpec` テストがパスする。
- **Must-11** → `cabal test agent-orchestrator` の `FailureKnowledgeRepositorySpec` `persist` テストケースにて、モックの受け取ったドキュメント JSON の `createdAt` フィールドが RFC3339 形式の文字列であることを assert してパスする。
- **Must-12** → `grep -n "instance HypothesisProposalRepository" backend/agent-orchestrator/src/Infrastructure/Firestore/HypothesisProposalRepository.hs` が 1 行を返す。`cabal test agent-orchestrator` の `HypothesisProposalRepositorySpec` テストがパスする。
- **Must-13** → `cabal test agent-orchestrator` の `HypothesisProposalRepositorySpec` デコードエラーテストケース（未知 `status` 値）が `DomainError` を返すことを assert してパスする。
- **Must-14** → `cabal test agent-orchestrator` の `HypothesisProposalRepositorySpec` `persist` テストケースにて、モックの受け取った JSON に `updatedAt` が含まれ RFC3339 形式であることを assert する。既存ドキュメントへの upsert テストケースで `createdAt` が上書きされないことを assert してパスする。
- **Must-15** → `grep -n "instance OrchestrationDispatchRepository" backend/agent-orchestrator/src/Infrastructure/Firestore/OrchestrationDispatchRepository.hs` が 1 行を返す。`cabal test agent-orchestrator` の `OrchestrationDispatchRepositorySpec` テストがパスする。
- **Must-16** → `cabal test agent-orchestrator` の `OrchestrationDispatchRepositorySpec` `persist` テストケースにて、モックの受け取った JSON の `expiresAt` が `processedAt` から 30 日後の RFC3339 タイムスタンプであることを assert してパスする。またドキュメント ID に `"agent-orchestrator:"` プレフィックスが含まれることを assert してパスする。
- **Must-17** → `grep -n "newtype HypothesisEventPublisher\|runHypothesisEventPublisher" backend/agent-orchestrator/src/Infrastructure/PubSub/HypothesisEventPublisher.hs` が 2 行を返す。
- **Must-18** → `grep -n "topicName\|pubsubPublish" backend/agent-orchestrator/src/Infrastructure/PubSub/HypothesisEventPublisher.hs` が 2 行以上を返す。
- **Must-19** → `grep "PUBSUB_TOPIC_HYPOTHESIS" backend/agent-orchestrator/src/Infrastructure/PubSub/HypothesisEventPublisher.hs` が 1 行以上を返す。
- **Must-20** → `cabal test agent-orchestrator` の `HypothesisEventPublisherSpec` `publishHypothesisProposed` 正常系テストケースにて、モックの受け取ったバイト列を `aeson` でパースし `eventType == "hypothesis.proposed"` かつ `payload.symbol`・`payload.sourceEvidence`・`payload.instrumentType` が非空であることを assert してパスする。
- **Must-21** → `cabal test agent-orchestrator` の `HypothesisEventPublisherSpec` `publishHypothesisProposalFailed` 正常系テストケースにて、`eventType == "hypothesis.proposal.failed"` かつ `payload.reasonCode` が非空文字列であることを assert してパスする。
- **Must-22** → `cabal test agent-orchestrator` の `HypothesisEventPublisherSpec` において、`publishHypothesisProposed` を 2 回連続で呼び出したとき 2 つのメッセージの `identifier` フィールドが異なることを assert してパスする。
- **Must-23** → `cabal test agent-orchestrator` の `HypothesisEventPublisherSpec` ガード違反テストケース（`status=Proposed` 以外を `publishHypothesisProposed` に渡す）が発行せず `Left DomainError` を返すことを assert してパスする。
- **Must-24** → `cabal test agent-orchestrator` の `HypothesisEventPublisherSpec` ガード違反テストケース（`status=Pending` を `publishHypothesisProposalFailed` に渡す）が発行せず `Left DomainError` を返すことを assert してパスする。
- **Must-25** → `ls backend/agent-orchestrator/test/Infrastructure/Firestore/` にて `SkillRegistryRepositorySpec.hs`, `InstructionProfileRepositorySpec.hs`, `CodeReferenceTemplateRepositorySpec.hs`, `FailureKnowledgeRepositorySpec.hs`, `HypothesisProposalRepositorySpec.hs`, `OrchestrationDispatchRepositorySpec.hs` の 6 ファイルが存在することを確認する。`cd backend && cabal test agent-orchestrator 2>&1 | tail -5` に `0 failures` が含まれる。
- **Must-26** → `grep -rn "newManager\|googleApplicationCredentials\|GOOGLE_APPLICATION_CREDENTIALS" backend/agent-orchestrator/test/Infrastructure/` の結果がゼロ行。
- **Must-27** → `ls backend/agent-orchestrator/test/Infrastructure/PubSub/HypothesisEventPublisherSpec.hs` が終了コード 0 を返す。`cd backend && cabal test agent-orchestrator 2>&1 | tail -5` に `0 failures` が含まれる。
- **Must-28** → `grep -rn "newManager\|pubsub.googleapis.com\|GOOGLE_APPLICATION_CREDENTIALS" backend/agent-orchestrator/test/Infrastructure/PubSub/` の結果がゼロ行。
- **Must-29** → `cd backend && cabal test agent-orchestrator --test-show-details=streaming` の出力に各 `*RepositorySpec` の `find 正常系`・`find ドキュメント不在`・`persist 正常系`・`フィールド欠損デコードエラー` ケースがすべて `✓` で表示される。
- **Must-30** → `cd backend && cabal test agent-orchestrator --test-show-details=streaming` の出力に `HypothesisEventPublisherSpec` の `publishHypothesisProposed 正常系`・`publishHypothesisProposalFailed 正常系`・`ガード違反` ケースがすべて `✓` で表示される。
- **Must-31** → `cd backend && cabal build agent-orchestrator 2>&1 | grep -c "^Error"` が `0` を返す。
- **Must-32** → `cd backend && cabal test agent-orchestrator 2>&1 | tail -5` に `0 failures` が含まれる。
- **Must-33** → `hlint backend/agent-orchestrator/src/Infrastructure/ backend/agent-orchestrator/test/Infrastructure/ 2>&1 | grep -c "^src\|^test"` が `0` を返す（または `ci/allowlist.yml` 登録済み警告のみ）。
- **Must-34** → `grep -rn "^import UseCase" backend/agent-orchestrator/src/Infrastructure/` の結果がゼロ行。
- **Must-35** → `git diff HEAD -- backend/agent-orchestrator/src/Main.hs` の出力が空。

---

## Non-goals (今回やらない)

- `Main.hs` への DI 配線（各インフラモジュールのエントリポイント結線はプレゼンテーション層 Issue の責務）。
- 実 GCP Firestore・Pub/Sub を使った統合テスト・E2E テスト。
- `HypothesisReportRepository`（Cloud Storage 書き込み）の実装（別 Issue）。
- `SkillExecutorT`（ACL 層）の変更（`agent-orchestrator-acl` Issue で完結済み）。
- ユースケース層・ドメイン層のコード変更。
- Terraform / Firestore インデックス定義ファイル（`firestore.indexes.json`）の変更。
- `insight-collector`, `hypothesis-lab`, `bff` など他サービスへの変更。
- Firestore セキュリティルール（`firestore.rules`）の変更。
- gogol-firestore のバージョンアップ対応（現行 `1.0.0` を前提とする）。

---

## Risk

- level: high-risk
- escalate_to_opus: true
- 理由: 以下の境界領域に触れる。
  - `schema`: Firestore ドキュメントフィールド名・型・TTL の実装誤りは `hypothesis_registry`・`idempotency_keys`・`failure_knowledge` 等の本番データ破損に直結する。
  - `event subscription` / `background job`: Pub/Sub 発行メッセージの JSON フィールド名・`eventType` 文字列の誤りは下流サービス（`hypothesis-lab` 等）の受信処理を無音で破壊する。
  - `DI`: `FirestoreEnv.firestoreExecute` と `HypothesisPublisherEnv.pubsubPublish` のシグネチャ誤りはプレゼンテーション層の DI 結線不能を招く。
  - `public export`: `exposed-modules` に追加される各インフラモジュールのシグネチャ変更は下位互換破壊を招く。
  - `migration`: `idempotency_keys` ドキュメント ID の命名規約（`"agent-orchestrator:{ulid}"`）はデータ設計上の不変条件であり、変更は既存レコードの重複チェック不能を招く。

---

## Open questions (あれば)

- **OQ-01** `HypothesisProposal.terminate` の実装をドキュメント物理削除とするかソフトデリート（`deleted: true` フィールド追加）とするか未確定。Firestore 設計書に明記がないため人間判断が必要。
- **OQ-02** `publishHypothesisProposed` の `schemaVersion` 値を `"1.0.0"` で固定するか、環境変数または `HypothesisPublisherEnv` フィールドで注入可能にするか未確定。AsyncAPI 仕様との突合が必要。
- **OQ-03** gogol-firestore `1.0.0` の `runFirestore` / `execute` の具体的なシグネチャが確認できていない。`FirestoreEnv.firestoreExecute` の型エイリアスはライブラリ API 確認後に確定させること（HLint 3.8 との互換性含む）。
