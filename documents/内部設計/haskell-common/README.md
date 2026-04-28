# Haskell共通モジュール詳細設計

最終更新日: 2026-03-07

## 1. 目的

- `backend/common/haskell` に実装する共通モジュールを、モジュール単位で実装可能な粒度まで詳細化する。
- 各設計書に「何をするか」「入力」「出力」「処理手順」「外部リソース」「使用ライブラリ」を定義し、設計書だけで実装完遂できる状態を作る。

## 2. 設計書一覧

- `App.Bootstrap.md`
- `App.Health.md`
- `Config.Env.md`
- `Messaging.CloudEvent.md`
- `Messaging.PubSub.md`
- `Persistence.Firestore.md`
- `Persistence.Idempotency.md`
- `Observability.Logging.md`
- `Observability.Metrics.md`
- `Resilience.Retry.md`
- `Auth.InternalJwt.md`
- `Storage.GCS.md`

## 3. ライブラリ基準

以下は 2026-03-07 時点で採用する基準バージョンである。出典は Hackage の各 package page とする。

| パッケージ | バージョン | 主用途 |
|---|---|---|
| `servant` | `0.20.3.0` | API 型定義 |
| `servant-server` | `0.20.3.0` | Server 実装 |
| `wai` | `3.2.4` | WAI Application / Middleware |
| `warp` | `3.4.12` | HTTP サーバー |
| `aeson` | `2.2.3.0` | JSON codec |
| `text` | `2.1.4` | 文字列処理 |
| `unordered-containers` | `0.2.21` | JSON / context map |
| `ulid` | `0.3.3.0` | `identifier` / `trace` |
| `envparse` | `0.6.0` | 環境変数ロード |
| `retry` | `0.9.3.1` | 指数バックオフ |
| `katip` | `0.8.8.4` | 構造化ログ |
| `prometheus` | `2.3.0` | メトリクス |
| `jose-jwt` | `0.10.0` | JWT / JWK 検証 |
| `http-client` | `0.7.19` | JWKS / metadata / fallback HTTP |
| `base64` | `1.0` | Pub/Sub `message.data` |
| `gogol` | `1.0.0.0` | Google API 認証基盤 |
| `gogol-firestore` | `1.0.0` | Firestore |
| `gogol-storage` | `1.0.0` | Cloud Storage |

## 4. 実装順序

1. `App.Bootstrap`
2. `App.Health`
3. `Config.Env`
4. `Observability.Logging`
5. `Observability.Metrics`
6. `Messaging.CloudEvent`
7. `Resilience.Retry`
8. `Persistence.Idempotency`
9. `Messaging.PubSub`
10. `Persistence.Firestore`
11. `Auth.InternalJwt`
12. `Storage.GCS`

## 5. 実装ポリシー

- 全モジュールは `AlphaMind.Common.*` 名前空間で公開する。
- 例外は共通エラー型へ寄せ、業務エラーはサービス側で包む。
- 外部 I/O を行う関数は request / response 変換を module 内で閉じ、サービス側には domain-friendly な interface を公開する。
- `identifier`, `trace`, `service` は logging / metrics / persistence の全 module で一貫して扱う。

## 6. 初心者向け実装ロードマップ

最初から全 module を同時に作ろうとすると、`Servant`、`WAI`、`Firestore`、`Pub/Sub` が一気に出てきて追いにくい。以下の順で「pure な module」から「外部 I/O を持つ module」へ進めると理解しやすい。

### 6.0 このロードマップの読み方

各 step は「概念説明」ではなく、「次にファイルへ何を書くか」を示すものとして読む。

基本ルール:

1. 先に型を書く
2. 次に関数シグネチャを書く
3. その後で最小の仮実装を書く
4. `cabal build` を通す
5. 最後にテストか動作確認をする

読み方の例:

- 「`App.Health` を先に使える状態にする」と書いてある場合:
  - 先に `Shared.Health` module を作る
  - `StandardHealthApi` と `healthServer` の型を書く
  - 仮実装でもよいので compile できる状態にする
  - その後で `Shared.Bootstrap` から import する

初心者向けの進め方:

- 1 step ごとに `cabal build` を通す
- 1 file に全部を書こうとしない
- 「import できる状態にする」を小さな目標にする

### Step 0. 作業前の足場確認

やること:

- `backend/common/haskell/shared.cabal` に依存関係が入っていることを確認する
- `backend/cabal.project` に `common/haskell/` が含まれていることを確認する
- `backend/hie.yaml` を使ってエディタが `lib:shared` を見る状態にする
- `cabal build` が通る最小状態を維持する

この時点の理解ポイント:

- Haskell は「module 名」と「ファイルパス」が一致している必要がある
- 依存パッケージは import するだけでは使えず、`.cabal` の `build-depends` に必要
- まず package / build / editor の 3 つを正常化してから実装に入る

完了条件:

- `backend/common/haskell` で `cabal build` が通る
- `src/Shared/Bootstrap.hs` を開いて import error が出ない

### Step 1. `App.Health` を作る

先にやる理由:

- 外部 I/O がなく、`Servant` の基本だけで完結する
- 「型を書いて handler を返す」という Haskell Web 実装の基本を学べる

やること:

- `ServiceStatusResponse` 型を作る
- `StandardHealthApi` 型を作る
- `healthServer` を実装する
- JSON shape を固定するテストを書く

見るべき設計書:

- `App.Health.md`

完了条件:

- `/healthz` が `"ok"` を返す
- `/` が `service`, `status`, `version`, `revision` を返す

### Step 2. `Config.Env` を作る

先にやる理由:

- `App.Bootstrap` が依存する
- `envparse` と `Maybe` / `Either` の扱いに慣れられる

やること:

- `requireTextEnv`
- `optionalTextEnv`
- `loadCommonRuntimeEnv`

初心者向けの考え方:

- いきなり parser combinator を頑張らず、小さい helper を先に作る
- `IO Text` や `IO (Maybe Text)` を返す薄い関数から始める
- fallback ロジックは 1 つの大関数に押し込めない

見るべき設計書:

- `Config.Env.md`

完了条件:

- `PORT` default `8080`
- `GCP_PROJECT_ID` fallback が動く
- 欠損時に明示的なエラーになる

### Step 3. `Observability.Logging` と `Observability.Metrics` を作る

先にやる理由:

- ここまでで起動時に必要な土台が揃う
- I/O はあるが、HTTP や Google Cloud API より追いやすい

やること:

- `initLogger`, `logInfoWith`, `logErrorWith`
- `initCommonMetrics`, `observeProcessing`

初心者向けの考え方:

- まず「1 件出せる」「1 件増やせる」を作る
- 汎用化は後でよい
- label や context は record にまとめる

見るべき設計書:

- `Observability.Logging.md`
- `Observability.Metrics.md`

完了条件:

- ログに `service` が必ず入る
- metrics を 1 本以上登録して更新できる

### Step 4. `App.Bootstrap` を作る

ここで初めて Web サービスの共通起動になる。

やること:

- `HttpServiceOptions`
- `mkApplication`
- `runHttpService`
- `App.Health` との API 合成

初心者向けの考え方:

- 最初は `beforeRun` を無視せず、そのまま `IO ()` で呼ぶ
- middleware は 0 個でも動く形から始める
- `serve` で `Application` を作り、最後に `runSettings` で起動する流れを固定で覚える

見るべき設計書:

- `App.Bootstrap.md`

完了条件:

- 既存サービス 1 つを共通 bootstrap で起動できる

### Step 5. `Messaging.CloudEvent` を作る

先にやる理由:

- まだ pure 中心で実装できる
- 後続の Pub/Sub と Idempotency の理解が楽になる

やること:

- `CloudEvent payload`
- `decodeCloudEvent`
- `encodeCloudEvent`
- `validateEventType`

初心者向けの考え方:

- まず `RawCloudEvent` を作る
- decode と validate を分離する
- `FromJSON` instance に全部詰め込まない

見るべき設計書:

- `Messaging.CloudEvent.md`

完了条件:

- 正常系 JSON を decode / encode できる
- ULID / 時刻不正を弾ける

### Step 6. `Resilience.Retry` を作る

先にやる理由:

- 外部 I/O を持つ module の共通部品になる
- `retry` package の使い方を先に理解できる

やること:

- `RetryPolicyConfig`
- `withRetry`

完了条件:

- retryable error だけ再試行できる

### Step 7. `Persistence.Firestore` と `Persistence.Idempotency` を作る

順番:

1. `Persistence.Firestore`
2. `Persistence.Idempotency`

理由:

- Idempotency は Firestore adapter の上に乗るため

初心者向けの考え方:

- Firestore wire format を service 側へ漏らさない
- まず `get` / `upsert` の 2 つだけ作る
- emulator テストで API の形を固める

完了条件:

- document の読み書きができる
- duplicate event を成功扱いで吸収できる

### Step 8. `Messaging.PubSub` を作る

順番:

1. push decode
2. CloudEvent 復元
3. publish

理由:

- 受信側の方が pure 寄りで簡単
- publish は auth, HTTP, retry が絡むため後回しが安全

完了条件:

- push body から `CloudEvent payload` を復元できる
- publish request を送れる

### Step 9. `Auth.InternalJwt` と `Storage.GCS` を作る

最後にやる理由:

- HTTP middleware と Google API I/O が中心で難易度が高い
- 先に Bootstrap / Logging / Retry / HTTP client の理解が必要

完了条件:

- JWT を検証して principal を取り出せる
- `gs://` の upload / download が動く

## 7. ライブラリの役割と最初の使い方

### 7.1 Web 基盤

| ライブラリ | 何のために使うか | 最初に覚えるもの | 主に使う module |
|---|---|---|---|
| `servant` | API 型を型レベルで表現する | `Get`, `Post`, `:>`, `:<|>` | `App.Health`, `App.Bootstrap` |
| `servant-server` | `Server` / `Handler` を `Application` に変換する | `Server`, `Handler`, `serve` | `App.Health`, `App.Bootstrap` |
| `wai` | HTTP middleware と `Application` の土台 | `Application`, `Middleware` | `App.Bootstrap`, `Auth.InternalJwt` |
| `warp` | WAI `Application` を実際に起動する | `run`, `runSettings` | `App.Bootstrap` |

初心者向けメモ:

- `servant` は「API の型」を書く
- `servant-server` は「その API を動かす handler」を書く
- `wai` は「handler の外側に logging や auth を巻く」
- `warp` は「最後に HTTP サーバーとして起動する」

最小イメージ:

```haskell
type Api = "healthz" :> Get '[PlainText] Text

server :: Server Api
server = pure "ok"

app :: Application
app = serve (Proxy @Api) server

main :: IO ()
main = run 8080 app
```

この例での役割:

- `servant`: `Api` という HTTP API の型を書く
- `servant-server`: `Server Api` と `serve` を使って handler を `Application` にする
- `wai`: `Application` が HTTP アプリ本体になる
- `warp`: `run 8080 app` で実際に起動する

最初に覚えること:

- API は値ではなく型で表現する
- handler の並び順は API 型の並び順に一致する
- middleware は `Application -> Application` で後から巻ける

### 7.2 データと validation

| ライブラリ | 何のために使うか | 最初に覚えるもの | 主に使う module |
|---|---|---|---|
| `aeson` | JSON encode / decode | `ToJSON`, `FromJSON`, `eitherDecode`, `encode` | `App.Health`, `Messaging.CloudEvent`, `Messaging.PubSub` |
| `text` | `String` より扱いやすい文字列 | `Text`, `pack`, `unpack` | ほぼ全 module |
| `unordered-containers` | JSON object や map 風データを扱う | `HashMap` | `Messaging.CloudEvent`, `Observability.Logging` |
| `ulid` | `identifier`, `trace` の型安全な表現 | `ULID` の parse / render | `Messaging.CloudEvent`, `Persistence.Idempotency` |
| `base64` | Pub/Sub `message.data` の decode / encode | `decode`, `encode` 相当 API | `Messaging.PubSub` |

最小イメージ:

```haskell
payloadBytes :: ByteString
payloadBytes = encode myRecord

decoded :: Either String MyRecord
decoded = eitherDecode payloadBytes
```

この層での考え方:

- `aeson` は「JSON 文字列」と「Haskell の record」の変換に使う
- `text` は業務で扱う文字列型の標準にする
- `ulid` は `identifier` を単なる文字列でなく専用型で扱うために使う
- `base64` は Pub/Sub の `message.data` が base64 文字列だから必要になる

### 7.3 設定と制御

| ライブラリ | 何のために使うか | 最初に覚えるもの | 主に使う module |
|---|---|---|---|
| `envparse` | 環境変数を型付きで読む | env parser の組み立て | `Config.Env`, `App.Bootstrap` |
| `retry` | 指数バックオフ再試行 | `retrying` か `recovering` | `Resilience.Retry`, `Messaging.PubSub`, `Storage.GCS` |

最小イメージ:

```haskell
loadPort :: IO Int
loadPort = do
  value <- lookupEnv "PORT"
  pure $ maybe 8080 read value
```

この層での考え方:

- `envparse` は「環境変数を読む処理」を型付きで整理するために使う
- `retry` は「失敗したらもう一度呼ぶ」という制御を共通化するために使う
- まずは手書きで動きを理解し、その後 `retry` package に置き換えてよい

### 7.4 観測性

| ライブラリ | 何のために使うか | 最初に覚えるもの | 主に使う module |
|---|---|---|---|
| `katip` | JSON ログを出す | logger 初期化, context 付き logging | `Observability.Logging` |
| `prometheus` | metrics を公開する | counter, histogram, registry | `Observability.Metrics` |

最小イメージ:

```haskell
logInfoWith logEnv ctx "service_started"
observeProcessing metrics "success" "none" 0.12
```

この層での考え方:

- `katip` は「人が読む message」と「機械が読む context」を一緒に出す
- `prometheus` は counter や histogram を process 内で増減させる
- どちらも domain logic ではなく運用のための情報を扱う

### 7.5 外部 API / Google Cloud

| ライブラリ | 何のために使うか | 最初に覚えるもの | 主に使う module |
|---|---|---|---|
| `http-client` | REST API 呼び出し | request 作成, manager, response body | `Messaging.PubSub`, `Auth.InternalJwt` |
| `jose-jwt` | JWT / JWK 検証 | token decode, claims 検証 | `Auth.InternalJwt` |
| `gogol` | Google API 認証と共通土台 | env / auth context | `Messaging.PubSub`, `Persistence.Firestore`, `Storage.GCS` |
| `gogol-firestore` | Firestore API | document get / patch | `Persistence.Firestore` |
| `gogol-storage` | Cloud Storage API | object get / insert | `Storage.GCS` |

初心者向けメモ:

- `gogol` 系は最初から全部覚えなくてよい
- まず「認証済み context を作る」「1 API を呼ぶ」の 2 段階で理解する
- Firestore と GCS は別 package だが、auth の考え方は共通

最小イメージ:

```haskell
request <- parseRequest "https://pubsub.googleapis.com/v1/..."
manager <- newManager tlsManagerSettings
response <- httpLbs request manager
```

この層での考え方:

- `http-client` は素直な REST 呼び出しに使う
- `jose-jwt` は token を decode して claim を検証する
- `gogol` は Google API を呼ぶための認証済み環境を作る
- `gogol-firestore` と `gogol-storage` は、それぞれ Firestore と GCS の request 型を提供する

## 7.6 ライブラリの学習順

初心者は次の順で理解すると詰まりにくい。

1. `text`
2. `aeson`
3. `servant`
4. `servant-server`
5. `wai`
6. `warp`
7. `envparse`
8. `retry`
9. `katip`
10. `prometheus`
11. `http-client`
12. `gogol` 系

理由:

- 先に pure なデータ型と JSON を理解する
- 次に HTTP アプリの基本を理解する
- その後で設定、再試行、観測性、外部 API に進む

## 8. 初心者向け実装ガイド

### 8.1 迷ったらこの順で書く

1. 型を書く
2. pure 関数を書く
3. `IO` を持つ薄い wrapper を書く
4. テストを書く
5. module 外へ export する

### 8.2 まず pure に切れるかを考える

例:

- `parseGsUri :: Text -> Either GcsError GcsObjectRef`
- `decodeCloudEvent :: ByteString -> Either CloudEventError ...`
- `makeIdempotencyKey :: Text -> ULID -> Text`

こういう pure 関数を先に固めると、後から `IO` の問題を切り分けやすい。

### 8.3 外部ライブラリを直接 service 側へ漏らさない

悪い例:

- service 側が `gogol-firestore` の request 型を直接組み立てる

良い例:

- 共通 module 側で `upsertDocument` を公開し、service 側は domain record を渡すだけにする

### 8.4 テストの書き方

基本方針:

- pure 関数は unit test
- HTTP / Firestore / GCS は emulator or fake server
- いきなり end-to-end へ行かない

おすすめ順:

1. decode / parse の unit test
2. logger / metrics の shape test
3. emulator を使う integration test

### 8.5 つまずきやすい点

- module 名とファイルパスが一致していない
- `.cabal` の `exposed-modules` / `other-modules` に追加していない
- import した package を `build-depends` に入れていない
- `Text` と `String` を混ぜて型エラーになる
- `IO` の中で全部やろうとして pure 部分を分離していない

### 8.6 まず読むべき設計書

初心者が最初に読む順:

1. `App.Health.md`
2. `Config.Env.md`
3. `Observability.Logging.md`
4. `App.Bootstrap.md`
5. `Messaging.CloudEvent.md`
6. `Resilience.Retry.md`

この 6 本を理解してから外部 I/O を持つ module に進むと、実装しやすい。
