# App.Bootstrap 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- Cloud Run / Cloud Run Job 上で動く Haskell サービスの共通起動処理を 1 箇所へ集約する。
- `Main.hs` を「サービス名・API・server の定義」に限定し、ポート解決、Warp 設定、logging / metrics 初期化を隠蔽する。

## 2. 責務

- `PORT` を含む runtime 設定の読込
- logger / metrics / middleware 初期化
- Warp `Settings` 生成
- WAI `Application` 構築
- 起動ログ出力

非責務:

- 業務 route 定義
- Firestore / Pub/Sub client 初期化
- 認証認可ポリシー決定

## 3. 公開型・関数

```haskell
data HttpServiceOptions api = HttpServiceOptions
  { serviceName :: Text
  , serviceVersion :: Text
  , metricsPath :: Maybe Text
  , middlewareStack :: [Middleware]
  , beforeRun :: IO ()
  }

runHttpService
  :: HttpServiceOptions api
  -> Proxy api
  -> Server api
  -> IO ()

mkApplication
  :: HttpServiceOptions api
  -> Proxy api
  -> Server api
  -> IO Application
```

## 4. 入力

- `HttpServiceOptions`
- `Proxy api`
- `Server api`
- 環境変数:
  - `PORT`
  - `K_SERVICE`
  - `K_REVISION`
  - `GOOGLE_CLOUD_PROJECT`
  - `LOG_LEVEL`

## 5. 出力

- 起動済み WAI `Application`
- 標準出力への構造化起動ログ
- `runHttpService` 実行時は blocking な HTTP server

## 6. 処理内容

1. `Config.Env` から runtime 設定を読込
2. `Observability.Logging` で logger 初期化
3. `Observability.Metrics` で registry 初期化
4. `App.Health` の標準 route をサービス API と合成
5. middleware を順番に適用
6. Warp `Settings` に `PORT`, graceful shutdown, exception logger を設定
7. `service_started` ログを出して起動

## 7. 外部リソース

- Cloud Run runtime env
- 標準出力 / Cloud Logging
- Prometheus scrape endpoint（有効時）

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `servant` | `0.20.3.0` | API 合成 |
| `servant-server` | `0.20.3.0` | `serve` / `Server` |
| `wai` | `3.2.4` | `Application`, `Middleware` |
| `warp` | `3.4.12` | HTTP 起動 |
| `envparse` | `0.6.0` | env 読込 |
| `katip` | `0.8.8.4` | 起動ログ |
| `prometheus` | `2.3.0` | `/metrics` |

### 8.1 ライブラリの役割と使い方

- `servant`
  - 役割: health API と業務 API を 1 つの API 型へ合成する
  - この module での使い方: `type FullApi api = StandardHealthApi :<|> api`
- `servant-server`
  - 役割: `Server api` を `Application` に変換する
  - この module での使い方: `serve (Proxy @FullApi) fullServer`
- `wai`
  - 役割: middleware を `Application` に巻く
  - この module での使い方: `foldr ($) app middlewareStack`
- `warp`
  - 役割: `Application` を指定ポートで起動する
  - この module での使い方: `runSettings settings app`
- `envparse`
  - 役割: `PORT` や `K_REVISION` を読む
  - この module での使い方: `Config.Env` を通して runtime 情報を受け取る
- `katip`
  - 役割: 起動ログを JSON で出す
  - この module での使い方: `service_started` などの共通ログを出す
- `prometheus`
  - 役割: `/metrics` 用の registry を持つ
  - この module での使い方: metrics endpoint を差し込む準備をする

最小コードイメージ:

```haskell
app :: Application
app = serve (Proxy @StandardHealthApi) (healthServer ctx)
```

### 8.2 ライブラリの主な使い方

- `servant`
  - API 型を `type FullApi api = StandardHealthApi :<|> api` のように合成する
- `servant-server`
  - `serve fullProxy fullServer` で `Server` を `Application` に変換する
- `wai`
  - `foldr ($) baseApp middlewareStack` で middleware を順に適用する
- `warp`
  - `runSettings (setPort port defaultSettings) app` で起動する
- `envparse`
  - `Config.Env.loadCommonRuntimeEnv` 経由で `PORT` や `K_REVISION` を読む
- `katip`
  - `logInfoWith logEnv ctx "service_started"` のように起動ログを出す
- `prometheus`
  - `initCommonMetrics serviceName` で registry を初期化し、`/metrics` 用 handler へ渡す

### 8.3 import 例

```haskell
import Data.Kind (Type)
import Data.Proxy (Proxy (Proxy))
import Data.Text (Text)
import Network.Wai (Application, Middleware)
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setPort)
import Servant
  ( HasServer
  , Server
  , serve
  , (:<|>)(..)
  )
```

補足:

- `Proxy` を型注釈で使うなら `Data.Proxy`
- `serve`, `Server`, `:<|>` は `Servant`
- `Application`, `Middleware` は `Network.Wai`
- `runSettings`, `setPort` は `warp`

## 9. 実装ルール

- `PORT` 未設定時は `8080`
- `beforeRun` の失敗は起動失敗として process を終了
- middleware の適用順は「外側から内側」へ固定
- `/healthz` と `/` は全サービスで必ず有効

## 10. テスト観点

- `PORT` 未設定時に `8080` で起動する
- `metricsPath` 有効時に metrics endpoint が追加される
- middleware 適用順が保持される
- 起動時に `service`, `revision`, `port` を含むログが出る

## 11. 実装ヒント

- 最初は `runHttpService` だけ実装し、`mkApplication` はその内部 helper に留める。
- API 合成は `type FullApi api = StandardHealthApi :<|> api` のような形で切ると分かりやすい。
- `beforeRun` は `IO ()` のまま持ち、失敗時は例外をそのまま落として fail-fast にする。
- middleware は最初から汎用 list にせず、`requestId` と `logging` の2つだけを固定で組み込んでもよい。

## 12. 初心者向け実装ロードマップ

### Step 1. 最小の record を作る

- まず [src/Shared/Bootstrap.hs](/Users/lihs/workspace/alpha-mind/backend/common/haskell/src/Shared/Bootstrap.hs) に module header だけ書く
- 次に `HttpServiceOptions api` の型だけ追加する
- この step では関数本体はまだ書かず、型を確定することだけに集中する

この step でファイルに追加するもの:

```haskell
module Shared.Bootstrap where

import Data.Text (Text)
import Network.Wai (Middleware)

data HttpServiceOptions api = HttpServiceOptions
  { serviceName :: Text
  , serviceVersion :: Text
  , metricsPath :: Maybe Text
  , middlewareStack :: [Middleware]
  , beforeRun :: IO ()
  }
```

この step ではまだやらないこと:

- `mkApplication`
- `runHttpService`
- logging 初期化
- metrics endpoint 追加

### Step 2. `App.Health` を先に使える状態にする

- 先に [App.Health.md](/Users/lihs/workspace/alpha-mind/documents/内部設計/haskell-common/App.Health.md) の最小実装を終わらせる
- 少なくとも以下が import できる状態にする
  - `StandardHealthApi`
  - `ServiceHealthContext`
  - `healthServer`
- `Bootstrap` 側では health endpoint 自体は書かず、「既にある health server を組み込む側」に徹する

この step で実際にやること:

1. `Shared/Health.hs` を作る
2. `StandardHealthApi` を定義する
3. `healthServer` を仮実装でもよいので返せる状態にする
4. `Shared/Bootstrap.hs` で import だけ追加する

この step が終わった時の状態:

- `Shared.Bootstrap` の先頭で `import Shared.Health (...)` が書ける
- まだアプリ起動はできなくてもよい
- `cabal build` が通れば十分

### Step 3. `mkApplication` を先に作る

- `Proxy api` と `Server api` を受け取って `Application` を返す関数シグネチャを書く
- 最初は health 合成をせず、業務 API だけ `serve` してもよい
- `middlewareStack` は一旦無視して build を通す

最初に書く形:

```haskell
mkApplication
  :: HttpServiceOptions api
  -> Proxy api
  -> Server api
  -> IO Application
mkApplication _ proxy server =
  pure (serve proxy server)
```

この step の目的:

- `Application` を返す最低限の関数を作る
- `Servant` の `serve` が何をしているかを理解する
- まず「起動可能な WAI アプリが返る」状態にする

### Step 4. health API と業務 API を合成する

- API 型と server 値の両方を `:<|>` で合成する
- `App.Health` で作った `healthServer` を先頭側に置く
- まずは `metrics` なし、middleware なしでよい

この step で追加するイメージ:

```haskell
type FullApi api = StandardHealthApi :<|> api

mkApplication options proxy businessServer = do
  let ctx = ServiceHealthContext
        { serviceName = options.serviceName
        , serviceVersion = options.serviceVersion
        , revision = Nothing
        }
      fullServer = healthServer ctx :<|> businessServer
  pure (serve (Proxy @(FullApi api)) fullServer)
```

ここで理解すること:

- `:<|>` は「API を横につなぐ」
- server 側も同じ順番で `:<|>` する
- API 型の順番と handler の順番は必ず一致する

### Step 5. middleware を後から適用する

- `serve` で作った `Application` に対して `middlewareStack` を適用する
- 最初は空 list で何も起きない状態を確認する
- 次に 1 個だけ middleware を追加して、順番が崩れないことを確認する

追加するイメージ:

```haskell
let baseApp = serve fullProxy fullServer
    finalApp = foldr ($) baseApp (middlewareStack options)
pure finalApp
```

この step で確認すること:

- middleware 0 件でも build が通る
- `middlewareStack = [mw1, mw2]` のとき `mw1` が外側になる
- middleware 実装自体はこの module で作らなくてよい

### Step 6. `runHttpService` を最後に作る

- `runHttpService` は orchestration 専用の関数として最後に書く
- やることは 4 つだけに限定する
  1. env を読む
  2. `beforeRun` を実行する
  3. `mkApplication` を呼ぶ
  4. `Warp.runSettings` で起動する

最初の実装イメージ:

```haskell
runHttpService options proxy server = do
  runtimeEnv <- loadCommonRuntimeEnv (serviceName options)
  beforeRun options
  app <- mkApplication options proxy server
  runSettings (setPort (port runtimeEnv) defaultSettings) app
```

この step で後回しにしてよいもの:

- graceful shutdown の細かい設定
- exception logger の詳細
- metrics endpoint の追加
- 起動ログの field 拡充

### 完了条件

- 共通 bootstrap 経由で既存サービス 1 つが起動する
- `/healthz` と `/` が返る
- `PORT` 変更で listen port が変わる

最終チェック手順:

1. `shared.cabal` に `Shared.Bootstrap` が `exposed-modules` で入っていることを確認する
2. `cabal build` を実行する
3. 既存 service の `Main.hs` から `runHttpService` を呼ぶ
4. `curl localhost:8080/healthz` と `curl localhost:8080/` を確認する

## 13. `mkApplication` の型変数に関する注意

`mkApplication` の中で `FullApi api` を使う場合は、型シグネチャ側で `forall api.` を明示し、`ScopedTypeVariables` を有効にする。

理由:

- `mkApplication :: HttpServiceOptions api -> Proxy api -> Server api -> IO Application` の `api` は、暗黙のままだと関数本体で名前として参照できない
- その状態で `FullApi api` と書くと `Not in scope: type variable 'api'` になる
- `forall api.` と `ScopedTypeVariables` を使うことで、「型シグネチャで導入した `api` を本体でも同じ名前で使う」ことができる

記述例:

```haskell
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeOperators #-}

mkApplication
  :: forall api.
     HttpServiceOptions api
  -> Proxy api
  -> Server api
  -> IO Application
mkApplication options _ businessServer = do
  let ctx = ServiceHealthContext
        { serviceName = serviceName options
        , serviceVersion = serviceVersion options
        , serviceRevision = Nothing
        }
      fullServer = healthServer ctx :<|> businessServer
  pure (serve (Proxy :: Proxy (FullApi api)) fullServer)
```

補足:

- `Proxy @(FullApi api)` を使う場合は `TypeApplications` も必要
- 初学者は `Proxy :: Proxy (FullApi api)` の方が読みやすい
- `:<|>` を handler 側で使う場合は `Servant` から値コンストラクタとして import する

例:

```haskell
import Servant
  ( Server
  , serve
  , (:<|>)(..)
  , type (:>)
  )
```
