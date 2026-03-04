# STG環境構築設計

最終更新日: 2026-02-28

## 1. 目的

- STG（staging）環境を構築するために、インフラ実装前の確定事項を段階的に定義する。
- 本書は「不足項目を一つずつ埋める」ための正本とする。

## 2. 進め方

- 1項目ずつ `pending -> decided` に更新する。
- `decided` になった項目のみ IaC/実装へ反映する。

## 3. 項目管理

| ID | 項目 | 状態 | 備考 |
|---|---|---|---|
| INF-001 | 環境境界（プロジェクト/リージョン/ドメイン/分離方針） | decided | 本書 4章 |
| INF-002 | Cloud Run/Cloud Run Job 実行パラメータ（CPU/Memory/Timeout/Concurrency） | decided | 本書 5章 |
| INF-003 | IAM（Service Account と Role 割当） | decided | 本書 6章 |
| INF-004 | Pub/Sub 実体（topic/subscription/DLQ/retry） | decided | 本書 7章 |
| INF-005 | Scheduler 実体（cron/timezone/target） | decided | 本書 8章 |
| INF-006 | Secret/環境変数マトリクス | decided | 本書 9章 |
| INF-007 | CI/CD と Artifact Registry | decided | 本書 10章 |
| INF-008 | Terraform 構成（monitoring以外） | decided | 本書 11章 |

## 4. INF-001 環境境界（decided）

### 4.1 環境一覧

| 環境 | GCP Project ID | Region | BFF URL | 用途 |
|---|---|---|---|---|
| STG | `alpha-mind-stg` | `asia-northeast1` | `https://staging.api.alpha-mind.dev` | 検証・受入 |
| PROD | `alpha-mind-prod` | `asia-northeast1` | `https://api.alpha-mind.dev` | 本番運用 |

### 4.2 分離方針

1. STGとPRODは**別プロジェクト**で完全分離する。
2. Firestore / Pub/Sub / Cloud Storage / Secret Manager / Cloud Run は環境ごとに分離する。
3. STGのデータ・シークレット・権限をPRODと共有しない。
4. IAMは環境ごとに別Service Accountを作成し、最小権限で付与する。
5. リリースは「STG検証完了後にPRODへ昇格」の順序を必須とする。

### 4.3 既存設計との対応

- OpenAPIのserver定義と一致:
  - `production`: `https://api.alpha-mind.dev`
  - `staging`: `https://staging.api.alpha-mind.dev`
- 参照: `外部設計/api/openapi.yaml`

## 5. INF-002 実行パラメータ（decided）

### 5.1 Cloud Run Service（STG初期値）

| Service | CPU | Memory | Request Timeout | Concurrency | Min Instances | Max Instances | Ingress |
|---|---:|---:|---:|---:|---:|---:|---|
| `bff` | 1 vCPU | 512Mi | 30s | 80 | 0 | 10 | all |
| `audit-log` | 1 vCPU | 512Mi | 30s | 80 | 0 | 10 | internal |
| `portfolio-planner` | 1 vCPU | 1Gi | 120s | 20 | 0 | 10 | internal |
| `risk-guard` | 1 vCPU | 512Mi | 10s | 20 | 0 | 20 | internal |
| `execution` | 1 vCPU | 1Gi | 60s | 10 | 0 | 10 | internal |
| `agent-orchestrator` | 2 vCPU | 2Gi | 300s | 4 | 0 | 5 | internal |

補足:

1. `bff` は外部公開のため `ingress=all`、その他は内部通信用で `ingress=internal`。
2. コスト最適化方針に合わせ、STGは全サービス `min instances=0` とする。
3. `agent-orchestrator` はLLM連携を想定し、他サービスより長いtimeoutを割り当てる。

### 5.2 Cloud Run Job（STG初期値）

| Job | CPU | Memory | Task Timeout | Max Retries | Task Count | Parallelism |
|---|---:|---:|---:|---:|---:|---:|
| `data-collector` | 2 vCPU | 2Gi | 1200s | 1 | 1 | 1 |
| `feature-engineering` | 2 vCPU | 4Gi | 1800s | 1 | 1 | 1 |
| `signal-generator` | 2 vCPU | 2Gi | 1200s | 1 | 1 | 1 |
| `insight-collector` | 2 vCPU | 2Gi | 1800s | 1 | 1 | 1 |
| `hypothesis-lab` | 4 vCPU | 8Gi | 7200s | 1 | 1 | 1 |

補足:

1. Jobは再実行制御をINF-005（Scheduler）/INF-004（Pub/Sub再送）で行うため `max retries=1` とする。
2. STGでは検証の再現性優先で `taskCount=1`, `parallelism=1` を初期値とする。

### 5.3 STG適用ルール

1. 上記はSTGの初期値であり、PRODは負荷実測後に上方調整を許可する。
2. パラメータ変更はPull Requestで理由（SLO改善/コスト改善）を明記する。
3. 変更後は `SLO-001`〜`SLO-011` への影響を週次レビューで確認する。

## 6. INF-003 IAM（decided）

### 6.1 Service Account命名

1. 実行用SA: `sa-{service}-stg@alpha-mind-stg.iam.gserviceaccount.com`
2. 監視/運用用SA: `sa-ops-stg@alpha-mind-stg.iam.gserviceaccount.com`
3. 人手利用アカウントと実行用SAは兼用しない。

### 6.2 共通ロール（全runtime SA）

| Role | Scope | 用途 |
|---|---|---|
| `roles/logging.logWriter` | project | 構造化ログ出力 |
| `roles/monitoring.metricWriter` | project | カスタムメトリクス送信 |
| `roles/datastore.user` | project | Firestore read/write（各サービス所有データ） |

### 6.3 サービス別追加ロール

| Service Account | 追加Role | Scope | 用途 |
|---|---|---|---|
| `sa-bff-stg` | `roles/pubsub.publisher` | project（topic詳細はINF-004） | 運用コマンドイベント発行 |
| `sa-bff-stg` | `roles/secretmanager.secretAccessor` | project（secret詳細はINF-006） | JWT鍵/OIDC設定参照 |
| `sa-bff-stg` | `roles/run.invoker` | `risk-guard` service | 内部コマンドAPI呼び出し |
| `sa-data-collector-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | 収集要求受信/結果発行 |
| `sa-data-collector-stg` | `roles/storage.objectAdmin` | `raw_market_data` bucket | 生データ保存 |
| `sa-data-collector-stg` | `roles/secretmanager.secretAccessor` | project（INF-006） | 外部APIキー参照 |
| `sa-feature-engineering-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | 生成要求受信/結果発行 |
| `sa-feature-engineering-stg` | `roles/storage.objectViewer` | `raw_market_data` bucket | 生データ読取 |
| `sa-feature-engineering-stg` | `roles/storage.objectAdmin` | `feature_store` bucket | 特徴量保存 |
| `sa-signal-generator-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | 生成要求受信/結果発行 |
| `sa-signal-generator-stg` | `roles/storage.objectViewer` | `feature_store` bucket | 特徴量読取 |
| `sa-signal-generator-stg` | `roles/storage.objectAdmin` | `signal_store` bucket | シグナル保存 |
| `sa-signal-generator-stg` | `roles/secretmanager.secretAccessor` | project（INF-006） | Model Registry接続情報参照 |
| `sa-portfolio-planner-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | シグナル受信/注文提案発行 |
| `sa-risk-guard-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | 注文提案受信/承認結果発行 |
| `sa-execution-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | 承認受信/執行結果発行 |
| `sa-execution-stg` | `roles/secretmanager.secretAccessor` | project（INF-006） | ブローカー鍵参照 |
| `sa-audit-log-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | 全イベント監査受信/任意通知 |
| `sa-insight-collector-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | 収集要求受信/結果発行 |
| `sa-insight-collector-stg` | `roles/storage.objectAdmin` | `insight_raw`, `insight_processed` bucket | 収集成果保存 |
| `sa-insight-collector-stg` | `roles/secretmanager.secretAccessor` | project（INF-006） | 外部APIキー参照 |
| `sa-agent-orchestrator-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | 入力受信/仮説イベント発行 |
| `sa-agent-orchestrator-stg` | `roles/storage.objectAdmin` | `hypothesis_reports` bucket | 生成レポート保存 |
| `sa-agent-orchestrator-stg` | `roles/secretmanager.secretAccessor` | project（INF-006） | LLM実行基盤キー参照 |
| `sa-hypothesis-lab-stg` | `roles/pubsub.subscriber`, `roles/pubsub.publisher` | project（INF-004） | 仮説受信/判定結果発行 |
| `sa-hypothesis-lab-stg` | `roles/storage.objectAdmin` | `backtest_artifacts`, `demo_artifacts` bucket | 検証成果保存 |
| `sa-scheduler-stg` | Cloud Run Job実行権限（`run.jobs.run`） | `data-collector`, `insight-collector` job | 定期実行 |

### 6.4 IAM運用ルール

1. IAM付与はグループ直接付与ではなく、Service Account単位で管理する。
2. オーナー/エディタなどの広域ロールをruntime SAへ付与しない。
3. `project` スコープ付与後、INF-004/INF-006でtopic/secret/bucket単位へ段階的に絞る。

## 7. INF-004 Pub/Sub（decided）

### 7.1 命名規則

1. topic: `event-{event-type-dash}-v1`
2. subscription: `sub-{consumer}-event-{event-type-dash}-v1`
3. DLQ topic: `dlq-{consumer}-event-{event-type-dash}-v1`
4. DLQ subscription: `sub-dlq-{consumer}-event-{event-type-dash}-v1`

補足:

- `event-type-dash` は `orders.approved` のような eventType を `orders-approved` に変換した値。

### 7.2 イベント配線（STG）

| Event Type | Publisher | Subscriber |
|---|---|---|
| `market.collect.requested` | `bff` | `data-collector`, `audit-log` |
| `market.collected` | `data-collector` | `feature-engineering`, `audit-log` |
| `market.collect.failed` | `data-collector` | `audit-log` |
| `features.generated` | `feature-engineering` | `signal-generator`, `audit-log` |
| `features.generation.failed` | `feature-engineering` | `audit-log` |
| `signal.generated` | `signal-generator` | `portfolio-planner`, `audit-log` |
| `signal.generation.failed` | `signal-generator` | `audit-log` |
| `orders.proposed` | `portfolio-planner`, `bff` | `risk-guard`, `audit-log` |
| `orders.proposal.failed` | `portfolio-planner` | `audit-log` |
| `orders.approved` | `risk-guard` | `execution`, `audit-log` |
| `orders.rejected` | `risk-guard` | `audit-log` |
| `orders.executed` | `execution` | `audit-log` |
| `orders.execution.failed` | `execution` | `audit-log` |
| `operation.kill_switch.changed` | `bff` | `risk-guard`, `audit-log` |
| `insight.collect.requested` | `bff` | `insight-collector`, `audit-log` |
| `insight.collected` | `insight-collector` | `agent-orchestrator`, `audit-log` |
| `insight.collect.failed` | `insight-collector` | `audit-log` |
| `hypothesis.retest.requested` | `bff` | `agent-orchestrator`, `audit-log` |
| `hypothesis.proposed` | `agent-orchestrator` | `hypothesis-lab`, `audit-log` |
| `hypothesis.proposal.failed` | `agent-orchestrator` | `audit-log` |
| `hypothesis.demo.completed` | `execution` | `hypothesis-lab`, `audit-log` |
| `hypothesis.backtested` | `hypothesis-lab` | `audit-log` |
| `hypothesis.promoted` | `hypothesis-lab` | `audit-log` |
| `hypothesis.rejected` | `hypothesis-lab` | `audit-log` |
| `audit.recorded` | `audit-log` | `audit-view`（任意） |

### 7.3 Subscription/DLQ ポリシー

1. 1イベント×1購読者ごとにsubscriptionを作成する。
2. 各subscriptionに専用DLQ topicを作成する。
3. `maxDeliveryAttempts`: `5`
4. `minimumBackoff`: `10s`
5. `maximumBackoff`: `600s`
6. `ackDeadlineSeconds`: `60`
7. message retention: `7日`
8. message ordering: `無効`（ordering key未使用）

### 7.4 運用ルール

1. 追加イベント時は AsyncAPI更新と同時に topic/subscription/DLQ を追加する。
2. DLQ滞留は `RB-OPS-001` または対象Runbookで復旧する。
3. subscription設定変更はPull Requestで差分レビューする。

## 8. INF-005 Scheduler（decided）

### 8.1 命名規則

1. Scheduler Job: `sch-{purpose}-stg`
2. timezone: `Asia/Tokyo`（全ジョブ共通）
3. retry: `maxRetryAttempts=3`, `minBackoff=60s`, `maxBackoff=600s`

### 8.2 定期実行ジョブ（STG）

| Scheduler Job | Cron | Target | 実行SA | 目的 |
|---|---|---|---|---|
| `sch-market-collect-weekday-stg` | `45 5 * * 1-5` | Cloud Run Job `data-collector` | `sa-scheduler-stg` | 07:00 JST締切（SLO-002）に向けた市場データ収集 |
| `sch-insight-collect-weekday-stg` | `0 6 * * 1-5` | Cloud Run Job `insight-collector` | `sa-scheduler-stg` | 取引開始前の定性インサイト収集 |

### 8.3 STG運用ルール

1. STGのSchedulerはデフォルト `PAUSED` で作成し、検証時のみ `ENABLED` にする。
2. 本番昇格前に、STGで少なくとも5営業日連続でジョブ完了を確認する。
3. Scheduler追加・cron変更はPull Requestで理由（SLO/コスト）を明記する。

## 9. INF-006 Secret/環境変数（decided）

### 9.1 Secret命名規則

1. Secret ID: `stg-{service}-{key}`
2. 例: `stg-bff-jwt-private-key`, `stg-data-collector-jquants-api-key`
3. Secret値は環境変数へ直接埋め込まず、Secret Manager参照で注入する。

### 9.2 Secretマトリクス（STG）

| Service | ENV Key | Secret ID | 必須 |
|---|---|---|---|
| `bff` | `OIDC_CLIENT_SECRET` | `stg-bff-oidc-client-secret` | 必須 |
| `bff` | `JWT_PRIVATE_KEY` | `stg-bff-jwt-private-key` | 必須 |
| `bff` | `JWT_PUBLIC_KEY` | `stg-bff-jwt-public-key` | 必須 |
| `data-collector` | `JQUANTS_API_KEY` | `stg-data-collector-jquants-api-key` | 必須 |
| `data-collector` | `ALPACA_API_KEY` | `stg-data-collector-alpaca-api-key` | 任意 |
| `data-collector` | `ALPACA_API_SECRET` | `stg-data-collector-alpaca-api-secret` | 任意 |
| `execution` | `BROKER_API_KEY` | `stg-execution-broker-api-key` | 必須 |
| `execution` | `BROKER_API_SECRET` | `stg-execution-broker-api-secret` | 必須 |
| `insight-collector` | `X_API_BEARER_TOKEN` | `stg-insight-collector-x-api-bearer-token` | 任意 |
| `insight-collector` | `YOUTUBE_API_KEY` | `stg-insight-collector-youtube-api-key` | 任意 |
| `agent-orchestrator` | `LLM_API_KEY` | `stg-agent-orchestrator-llm-api-key` | 必須 |
| `signal-generator` | `MLFLOW_TRACKING_TOKEN` | `stg-signal-generator-mlflow-tracking-token` | 任意 |

### 9.3 非秘密ENV（共通）

| ENV Key | 値（STG） | 用途 |
|---|---|---|
| `APP_ENV` | `stg` | 実行環境識別 |
| `GCP_PROJECT_ID` | `alpha-mind-stg` | GCPプロジェクト |
| `GCP_REGION` | `asia-northeast1` | リージョン |
| `FIRESTORE_DATABASE` | `(default)` | Firestore接続先 |
| `PUBSUB_TOPIC_PREFIX` | `event-` | topic命名プレフィックス |

### 9.4 運用ルール

1. Secret更新は新バージョン追加で行い、上書き更新しない。
2. ローテーション周期は四半期を標準とする。
3. Secret参照失敗時は fail-closed で処理を停止し、監査ログへ記録する。

## 10. INF-007 CI/CD と Artifact Registry（decided）

### 10.1 方針

1. STGデプロイは `main` へのマージを起点に自動実行する。
2. PRODデプロイは STG実績確認後の手動承認で実行する。
3. デプロイ対象イメージは「同一digestの昇格」のみ許可し、PRODで再buildしない。
4. API契約（OpenAPI/AsyncAPI）変更は lint/validate 成功を必須ゲートとする。

### 10.2 Artifact Registry 設計

| 項目 | STG | PROD | ルール |
|---|---|---|---|
| Project | `alpha-mind-stg` | `alpha-mind-prod` | 環境分離 |
| Region | `asia-northeast1` | `asia-northeast1` | INF-001に準拠 |
| Repository | `alpha-mind-app` | `alpha-mind-app` | docker形式 |
| Image Path | `{region}-docker.pkg.dev/{project}/alpha-mind-app/{service}` | 同左 | service名は `bff` など統一命名 |
| Tag | `git-{shortSha}` / `stg-{yyyyMMddHHmm}` | `prod-{yyyyMMddHHmm}` | 運用可読性と追跡性を両立 |

補足:

1. デプロイ時はtagではなくdigestを固定指定する。
2. SBOM/脆弱性スキャン結果はPRに添付し、criticalはデプロイブロックする。

### 10.3 パイプライン（必須）

1. `validate`:
- Haskell APIサービスのビルド/テスト（例: `cabal build` / `cabal test`）
- Python学習/推論サービスの静的検査/テスト（例: `ruff` / `pytest`）
- `pnpm --package=@redocly/cli dlx redocly lint documents/外部設計/api/openapi.yaml`
- `pnpm --package=@asyncapi/cli dlx asyncapi validate documents/外部設計/api/asyncapi.yaml`
- Terraform差分がある場合は `terraform fmt -check` と `terraform validate`

2. `build-and-push-stg`:
- コンテナbuild
- 脆弱性スキャン
- Artifact Registryへpush
- digestを成果物として保存

3. `deploy-stg`:
- digest固定でCloud Run Service/Jobへ反映
- `/healthz` と主要イベント疎通をスモーク確認

4. `promote-prod`（手動承認）:
- STGでの5営業日連続ジョブ完了（INF-005）を確認
- STGで使用中のdigestをそのままPRODへ昇格
- デプロイ後にSLO-001/SLO-004監視を強化

### 10.4 CI/CD 用 IAM

| SA | 主なRole | 用途 |
|---|---|---|
| `sa-cicd-stg` | `roles/artifactregistry.writer`, `roles/run.admin`, `roles/iam.serviceAccountUser` | STG build/deploy |
| `sa-cicd-prod` | `roles/artifactregistry.reader`, `roles/run.admin`, `roles/iam.serviceAccountUser` | PROD昇格deploy |

運用ルール:

1. CI/CD SAに `owner/editor` を付与しない。
2. `iam.serviceAccountUser` は実行対象runtime SAに限定する。
3. デプロイ実行者（人）と実行SA（機械）を分離する。

### 10.5 ロールバック

1. 直前の正常digestを保持し、`run deploy --image=<previousDigest>` で即時復旧可能にする。
2. SEV1/SEV2時は新規デプロイを停止し、ロールバックを優先する。
3. ロールバック実施時は `trace`, `actionReasonCode`, `user` を監査ログに必須記録する。

## 11. INF-008 Terraform構成（monitoring以外）（decided）

### 11.1 分割方針

1. `infra/monitoring` は既存設計（`Terraform監視設定設計.md`）を継続利用する。
2. 監視以外は `infra/platform` rootで管理し、責務を分離する。
3. `envs/stg` と `envs/prod` を分離し、環境差分は `terraform.tfvars` のみに閉じ込める。

### 11.2 推奨ディレクトリ構成

```text
infra/
  platform/
    versions.tf
    providers.tf
    backend.hcl
    envs/
      stg/
        main.tf
        variables.tf
        outputs.tf
        terraform.tfvars
      prod/
        main.tf
        variables.tf
        outputs.tf
        terraform.tfvars
    modules/
      project-services/
      artifact-registry/
      service-accounts/
      iam-bindings/
      cloud-run-services/
      cloud-run-jobs/
      pubsub/
      scheduler/
      storage/
      secrets/
      firestore/
  monitoring/
    ...（既存）
```

### 11.3 module責務

| module | 管理対象 | 備考 |
|---|---|---|
| `project-services` | 必要API有効化 | Run/PubSub/Secret/Firestore等 |
| `artifact-registry` | Docker repository | INF-007連携 |
| `service-accounts` | runtime/ops/cicd SA | 命名はINF-003準拠 |
| `iam-bindings` | SAへのrole付与 | 最小権限 |
| `cloud-run-services` | Service定義 | CPU/Memory等はINF-002準拠 |
| `cloud-run-jobs` | Job定義 | timeout/retries等はINF-002準拠 |
| `pubsub` | topic/sub/DLQ | INF-004準拠 |
| `scheduler` | 定期ジョブ | INF-005準拠 |
| `storage` | bucket/lifecycle | raw/feature/signal/audit等 |
| `secrets` | Secret metadata/IAM | 値投入は別手順 |
| `firestore` | DB作成/TTL/index関連設定 | rules/indexファイルと整合 |

### 11.4 State管理

1. backendはGCSを利用し、`platform` と `monitoring` のstateを分離する。
2. state bucketは環境ごとに分離する（例: `tfstate-alpha-mind-stg-platform`）。
3. Object Versioningを有効化し、state手編集を禁止する。

### 11.5 適用順序（STG）

1. `bootstrap`（state bucket, cicd SA）
2. `platform/base`（project-services, artifact-registry, service-accounts）
3. `platform/runtime`（iam-bindings, cloud-run, pubsub, scheduler, storage, secrets, firestore）
4. `monitoring`（既存 `infra/monitoring` root）

### 11.6 運用ルール

1. `plan -> 承認 -> apply` を必須とし、直接applyは禁止する。
2. `apply` は保存済みplanファイルのみ許可する。
3. drift確認として週次 `terraform plan` を実行する。
4. module追加時は本書のINF番号（002〜006）との対応表をPRに添付する。
