# App.Health 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- 全 Haskell サービスで共通の health / status endpoint を提供する。
- Cloud Run readiness と運用者確認のための最小 API を標準化する。

## 2. 責務

- `GET /healthz` の提供
- `GET /` の status JSON 提供
- `service`, `status`, `version`, `revision` の標準レスポンス定義

## 3. 公開型・関数

```haskell
type StandardHealthApi =
       "healthz" :> Get '[PlainText] Text
  :<|> Get '[JSON] ServiceStatusResponse

data ServiceStatusResponse = ServiceStatusResponse
  { service :: Text
  , status :: Text
  , version :: Text
  , revision :: Maybe Text
  }

healthServer :: ServiceHealthContext -> Server StandardHealthApi
```

## 4. 入力

- `ServiceHealthContext`
  - `serviceName`
  - `serviceVersion`
  - `revision`

## 5. 出力

- `/healthz`: `"ok"`
- `/`: `ServiceStatusResponse`

## 6. 処理内容

1. `/healthz` は依存先を見ずに `200 ok` を返す
2. `/` は service metadata を JSON で返す
3. 依存先の deep health check はこの module では持たない

## 7. 外部リソース

- なし

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `servant` | `0.20.3.0` | API 型 |
| `servant-server` | `0.20.3.0` | Handler |
| `aeson` | `2.2.3.0` | JSON |
| `text` | `2.1.4` | レスポンス値 |

### 8.1 ライブラリの役割と使い方

- `servant`
  - 役割: `/healthz` と `/` を型として表現する
  - 使い方: `"healthz" :> Get '[PlainText] Text` のように path と method を型で書く
- `servant-server`
  - 役割: API 型に対応する handler を `Server` として実装する
  - 使い方: `healthServer :: ServiceHealthContext -> Server StandardHealthApi`
- `aeson`
  - 役割: `ServiceStatusResponse` を JSON にする
  - 使い方: `ToJSON` instance か `Generic` ベースの encode
- `text`
  - 役割: `"ok"` や `serviceName` を `Text` で統一する
  - 使い方: 文字列はなるべく `Text` で持つ

最小コードイメージ:

```haskell
type StandardHealthApi =
       "healthz" :> Get '[PlainText] Text
  :<|> Get '[JSON] ServiceStatusResponse
```

### 8.2 ライブラリの主な使い方

- `servant`
  - `"healthz" :> Get '[PlainText] Text` のように endpoint を型で定義する
- `servant-server`
  - `healthServer :: ServiceHealthContext -> Server StandardHealthApi` を実装する
- `aeson`
  - `toJSON` または `deriving anyclass (ToJSON)` で status response を JSON 化する
- `text`
  - `"ok"` や `"running"` を `OverloadedStrings` 前提で `Text` として返す

### 8.3 import 例

```haskell
{-# LANGUAGE OverloadedStrings #-}

import Data.Aeson (ToJSON)
import Data.Text (Text)
import Servant
  ( Get
  , JSON
  , PlainText
  , Server
  , (:<|>)(..)
  , type (:>)
  )
```

補足:

- `Get`, `JSON`, `PlainText`, `type (:>)` は API 型定義用
- `( :<|> )(..)` は handler をつなぐ値コンストラクタとしても必要

## 9. 実装ルール

- `status` は固定で `"running"`
- `revision` は env 未設定なら `null`
- deep health は別 module で実装し、ここには混ぜない

## 10. テスト観点

- `/healthz` が常に 200 / `ok`
- `/` の JSON shape が全サービスで同一
- `revision` 未設定時に `null` になる

## 11. 実装ヒント

- handler は pure data を返すだけにし、外部依存を一切持たせない。
- `ServiceHealthContext` を record 1 つにまとめて、`ReaderT` に逃がさず明示引数で渡すと初期実装が簡単。
- `/healthz` と `/` のレスポンス型はこの module だけで完結させ、各サービスで再定義しない。

## 12. 初心者向け実装ロードマップ

### Step 1. レスポンス型を先に作る

- まず [src/Shared/Health.hs](/Users/lihs/workspace/alpha-mind/backend/common/haskell/src/Shared/Health.hs) を作る
- `ServiceStatusResponse` record を追加する
- `status` は入力で受けず、handler 側で `"running"` を埋める前提にする

この step で追加するもの:

```haskell
data ServiceStatusResponse = ServiceStatusResponse
  { service :: Text
  , status :: Text
  , version :: Text
  , revision :: Maybe Text
  }
```

### Step 2. API 型を書く

- `servant` を import する
- `GET /healthz` と `GET /` の API 型を 1 つにまとめる
- この step では handler はまだ未実装でよい

この step で追加するもの:

```haskell
type StandardHealthApi =
       "healthz" :> Get '[PlainText] Text
  :<|> Get '[JSON] ServiceStatusResponse
```

### Step 3. context 型を作る

- handler が必要とする値だけを record にまとめる
- `serviceName`, `serviceVersion`, `revision` の 3 つだけで十分
- まだ logger や metrics は入れない

### Step 4. handler を実装する

- `healthServer :: ServiceHealthContext -> Server StandardHealthApi` を書く
- `/healthz` 側は `pure "ok"`
- `/` 側は context から `ServiceStatusResponse` を組み立てる

最初の実装イメージ:

```haskell
healthServer ctx =
  pure "ok"
    :<|> pure
      ServiceStatusResponse
        { service = serviceName ctx
        , status = "running"
        , version = serviceVersion ctx
        , revision = revision ctx
        }
```

### Step 5. Servant で動作確認する

- 一時的な `main` を作るか `App.Bootstrap` から `serve` して確認する
- ブラウザでも `curl` でもよい
- JSON shape が設計どおりかを確認する

### 完了条件

- `/healthz` が 200 で `"ok"`
- `/` が決まった JSON shape を返す
- 外部依存なしでテストできる

最終チェック手順:

1. `Shared.Health` を `shared.cabal` に登録する
2. `cabal build` を実行する
3. `curl localhost:8080/healthz`
4. `curl localhost:8080/`
