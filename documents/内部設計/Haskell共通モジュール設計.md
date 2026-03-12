# Haskell共通モジュール設計

最終更新日: 2026-03-07

## 1. 目的

- Haskell で実装するバックエンドサービスに共通する基盤処理を洗い出し、先に共通モジュールの責務を定義する。
- 現時点で重複している `Main.hs` の起動処理だけでなく、各サービス内部設計書で繰り返し現れる Pub/Sub、Firestore、認証、可観測性の責務を共通化候補として整理する。
- ドメインロジックはサービス側に残し、Cloud Run / Cloud Run Job 上の Haskell サービスに共通する基盤機能だけを切り出す。

## 2. 対象サービス

本設計の対象は、内部設計書上で Haskell 実装と定義されている以下のサービスとする。

| サービス | 実行形態 | 主な役割 |
|---|---|---|
| `bff` | Cloud Run | Web コンソール向け HTTP API |
| `data-collector` | Cloud Run Job | 市場データ収集と `market.collected` 発行 |
| `execution` | Cloud Run | 承認済み注文の執行 |
| `insight-collector` | Cloud Run Job | 定性データ収集とインサイト生成 |
| `portfolio-planner` | Cloud Run | シグナルから注文候補生成 |
| `risk-guard` | Cloud Run | リスク審査と承認/却下 |
| `audit-log` | Cloud Run | 全イベントの監査記録 |

補足:

- `agent-orchestrator` は内部設計書では Python サービスのため、本設計の対象外とする。
- 現在の実装は多くのサービスで `Main.hs` の health check のみだが、共通化対象は内部設計書に書かれている将来責務まで含めて定義する。

## 3. 現状の重複と設計書から見える共通責務

### 3.1 現在コード上ですでに重複しているもの

各 Haskell サービスの `src/Main.hs` では、ほぼ同一の実装が重複している。

- `PORT` 読み取り
- Warp 起動
- `GET /healthz`
- `GET /`
- `ServiceStatus { service, status }` レスポンス
- Servant API 型定義

これは最初に共通化できる最小単位である。

### 3.2 内部設計書で繰り返し出ているもの

各サービス内部設計書を横断すると、以下の責務が繰り返し登場する。

- Pub/Sub イベントの subscribe / publish
- CloudEvents 互換のイベントエンベロープ検証
- `identifier` を使った冪等性制御
- Firestore 永続化
- Cloud Storage 入出力
- 指数バックオフ再試行
- `trace`, `identifier`, `service` を含む構造化ログ
- Secret Manager や外部 API 資格情報のロード
- private HTTP 用のサービス間認証

したがって、共通モジュールは「今の health check 重複を解消するだけの薄いライブラリ」ではなく、今後の Haskell サービス群の基盤パッケージとして設計するべきである。

## 4. 共通モジュールとして定義可能なもの

### 4.1 Cloud Run / Servant アプリ起動基盤

現状:

- すべての Haskell サービスが `Warp + Servant` の最小構成を個別定義している。

共通化する範囲:

- `PORT` 読み取りとデフォルト値処理
- サービス名を含む起動ログ
- health check / status API の共通型
- `ServiceStatus` レスポンス型
- Warp 起動ラッパー
- 共通 middleware 組み込み点

サービス側に残す範囲:

- 業務 API 型
- 業務ハンドラー
- サービス固有の route 構成

### 4.2 環境変数 / 設定ロード

内部設計書上の共通要件:

- 全サービスが Cloud Run / Cloud Run Job 上で起動し、Pub/Sub、Firestore、Cloud Storage、外部 API、Secret Manager 連携を行う。

共通化する範囲:

- 必須 / 任意環境変数の安全な取得
- `PORT`, `GCP_PROJECT_ID`, `PUBSUB_*`, `FIRESTORE_*` 等の共通設定型
- 設定ロード失敗時の一貫した例外 / エラー表現
- サービス名を埋め込んだ設定レコード

サービス側に残す範囲:

- J-Quants, Broker API, YouTube API などサービス固有の設定項目

### 4.3 Health / Status / Runtime Metadata

現状:

- 各 `Main.hs` で `status = "running"` の JSON を返している。

共通化する範囲:

- `HealthResponse`
- `ServiceStatusResponse`
- 必要であれば version, revision, environment を含む標準レスポンス
- `GET /healthz` と `GET /` の共通 server

補足:

- BFF 以外も Cloud Run 上で最低限の readiness を返すため、専用 module として持つ価値が高い。

### 4.4 CloudEvents / Pub/Sub エンベロープ

内部設計書と `共通設計.md` で共通化できる理由:

- 全イベントが `identifier`, `eventType`, `occurredAt`, `trace`, `schemaVersion`, `payload` を持つ。
- `identifier` は ULID、`occurredAt` は ISO8601 UTC の共通制約がある。
- 失敗イベントと成功イベントで envelope 自体は共通。

共通化する範囲:

- CloudEvent エンベロープ型
- ULID / 時刻のバリデーション
- JSON encode / decode
- `eventType` を型または newtype で扱う土台
- 共通エラーモデル

サービス側に残す範囲:

- payload 型
- eventType ごとの業務ルール
- domain event から payload への変換

### 4.5 Pub/Sub Subscriber / Publisher 基盤

内部設計書上の対象:

- `data-collector`, `execution`, `insight-collector`, `portfolio-planner`, `risk-guard`, `audit-log` はイベント subscribe / publish を持つ。
- `bff` も publish 側を持つ。

共通化する範囲:

- Pub/Sub push 受信 body のデコード
- Pub/Sub publish 用 metadata 組み立て
- ack / nack 判定の共通ポリシー
- retryable / non-retryable エラーの HTTP 返却戦略
- topic 名と project id から publish 先を解決する helper

サービス側に残す範囲:

- payload のデコード
- どの失敗を non-retryable とみなすかの業務判断
- topic 名の定義

### 4.6 Firestore 永続化の共通土台

内部設計書上の共通性:

- 多くの Haskell サービスが Firestore を利用する。
- `idempotency_keys` はほぼ全サービスが使う。
- `settings`, `orders`, `audit_logs`, `insight_records` などもドキュメント codec や timestamp 付与の考え方は共通化しやすい。

共通化する範囲:

- Firestore client 初期化
- 共通 timestamp / metadata codec
- collection 名を型で扱う helper
- upsert / get / query の薄い adapter
- document decode 失敗の共通エラー

最優先で共通化する具体物:

- `idempotency_keys` repository

### 4.7 冪等性リポジトリ

内部設計書上の共通性:

- すべてのイベント処理系サービスで `identifier` を冪等性キーとして使う。
- `共通設計.md` に `idempotency_keys/{service}:{identifier}` の方針が明記されている。

共通化する範囲:

- `service + identifier` のキー生成
- `reserve`, `complete`, `alreadyProcessed` 判定
- TTL / `processedAt` / `updatedAt` の共通項目
- duplicate event を成功扱いにする標準フロー

サービス側に残す範囲:

- 冪等性確定のタイミング
- 失敗時に key を解放するかどうか

### 4.8 Retry / エラーモデル

内部設計書上の共通性:

- 共通設計で「指数バックオフ最大3回」が明記されている。
- 多くのサービスで retryable / non-retryable の切り分けが必要。

共通化する範囲:

- `RetryPolicy`
- 指数バックオフ helper
- 共通 `ReasonCode` の土台型
- retryable / non-retryable 判定のヘルパー

サービス側に残す範囲:

- 各サービス固有の reason code 集合
- fail-open / fail-closed の業務判断

### 4.9 構造化ログ / 監査コンテキスト

共通化できる理由:

- `trace`, `identifier`, `service` を全ログに載せる方針が共通設計にある。
- `audit-log` だけでなく、他サービスもイベント受信・失敗・publish 成功を同じキーで記録する。

共通化する範囲:

- 構造化ログ出力 helper
- `service`, `identifier`, `trace`, `eventType`, `reasonCode` を保持する log context
- request / event 単位の context 生成

サービス側に残す範囲:

- 業務メトリクス名
- ドメイン固有の追加ログ項目

### 4.10 Service-to-Service 認証

対象:

- `bff` -> `risk-guard` private command API
- 将来的な internal HTTP endpoint 全般

共通化する範囲:

- Service Account JWT の検証 helper
- internal API 用 auth middleware
- principal / audience 検証

サービス側に残す範囲:

- 認可ポリシー
- endpoint ごとの権限制御

### 4.11 Cloud Storage / Secret Manager / 外部 API クライアントの共通部

共通化できる理由:

- `data-collector` と `insight-collector` は Cloud Storage を使う。
- `data-collector`, `execution`, `insight-collector`, `bff` は Secret Manager や外部 API 資格情報ロードを持つ。

共通化する範囲:

- GCS path / bucket helper
- Secret Manager からの secret 取得 wrapper
- HTTP client の timeout / retry / user-agent 標準設定

サービス側に残す範囲:

- API ごとの request / response モデル
- source 固有の制限・整形ルール

## 5. 今回は共通化対象にしないもの

- 注文審査、注文執行、注文候補生成などのドメイン判定ロジック
- 市場データ正規化、逆日歩クレンジング、特徴量設計
- インサイト要約や So What 判定などの業務ルール
- 監査レコードのドメイン意味づけ

理由:

- 同じ Haskell でも業務意味がサービスごとに大きく異なる。
- まずは「サービスを作るための基盤」を共通化し、その上でドメインコードは個別実装を維持する方が安全である。

## 6. 推奨ディレクトリ設計

### 6.1 追加するトップレベル

`backend/common/haskell` を新設し、Haskell 共通ライブラリ package を配置する。

```text
backend/
  common/
    haskell/
      alpha-mind-haskell-common.cabal
      src/
        AlphaMind/
          Common/
            App/
              Bootstrap.hs
              Health.hs
              Server.hs
            Config/
              Env.hs
              Service.hs
            Messaging/
              CloudEvent.hs
              PubSub.hs
            Persistence/
              Firestore.hs
              Idempotency.hs
            Observability/
              Logging.hs
              Metrics.hs
            Resilience/
              Retry.hs
              Error.hs
            Auth/
              InternalJwt.hs
            Storage/
              GCS.hs
      test/
        ...
```

### 6.2 `cabal.project` の扱い

`backend/cabal.project` に `common/haskell/` を package として追加し、各サービス `.cabal` から `alpha-mind-haskell-common` を参照する。

例:

```text
packages:
  common/haskell/
  bff/
  data-collector/
  execution/
  ...
```

### 6.3 各サービス側の配置方針

各サービスでは `Main.hs` を薄くし、共通 bootstrap を呼び出す形に寄せる。

例:

```text
backend/risk-guard/src/
  Main.hs                       -- 起動定義のみ
  RiskGuard/App.hs              -- service 固有 wiring
  RiskGuard/Domain/...
  RiskGuard/UseCase/...
  RiskGuard/Infrastructure/...
```

`Main.hs` の責務:

- サービス名の宣言
- サービス固有 server の組み立て
- 共通 `runHttpService` の呼び出し

## 7. 共通化の優先順位

### Phase 1

- `App.Bootstrap`
- `App.Health`
- `Config.Env`
- `Observability.Logging`

狙い:

- まず現在の `Main.hs` 重複を解消し、全 Haskell サービスの足場を統一する。

### Phase 2

- `Messaging.CloudEvent`
- `Messaging.PubSub`
- `Persistence.Idempotency`
- `Resilience.Retry`

狙い:

- イベント駆動サービスの標準実装を作る。

### Phase 3

- `Persistence.Firestore`
- `Auth.InternalJwt`
- `Storage.GCS`
- `Config.Service`

狙い:

- Firestore / private HTTP / Job 系サービスの実装速度を上げる。

## 8. この設計で期待する効果

- 新規 Haskell サービス追加時に `Main.hs` のコピペをやめられる。
- `identifier`, `trace`, `schemaVersion`, retry, idempotency の扱いを全サービスで揃えられる。
- BFF と内部イベントサービスで、HTTP / Pub/Sub / Firestore の基盤実装を共有できる。
- 将来 `risk-guard`, `execution`, `portfolio-planner` を本実装に進めるときの初期コストを下げられる。

## 9. 次の実装対象

最初に着手する候補は以下の順を推奨する。

1. `backend/common/haskell` package 作成
2. `App.Health` と `App.Bootstrap` の実装
3. `bff`, `data-collector`, `execution`, `portfolio-planner`, `risk-guard`, `audit-log`, `insight-collector` の `Main.hs` を共通 bootstrap 利用へ置換

これにより、最小リスクで共通モジュールを導入できる。
