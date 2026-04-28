# Config.Env 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- 環境変数ベースの設定読込を一元化し、必須値不足や型変換失敗をサービス起動時に確実に検出する。

## 2. 責務

- 必須 / 任意 env の parse
- typed config record の構築
- parse error の整形
- `Text`, `Int`, `Bool`, `URI` の標準 parser 提供

## 3. 公開型・関数

```haskell
data CommonRuntimeEnv = CommonRuntimeEnv
  { port :: Int
  , gcpProjectId :: Text
  , serviceName :: Text
  , serviceVersion :: Text
  , revision :: Maybe Text
  , logLevel :: Text
  }

loadCommonRuntimeEnv :: Text -> IO CommonRuntimeEnv
requireTextEnv :: Text -> IO Text
optionalTextEnv :: Text -> IO (Maybe Text)
```

## 4. 入力

- `serviceName`
- 環境変数:
  - `PORT`
  - `GCP_PROJECT_ID` または `GOOGLE_CLOUD_PROJECT`
  - `SERVICE_VERSION`
  - `K_REVISION`
  - `LOG_LEVEL`

## 5. 出力

- `CommonRuntimeEnv`
- parse 失敗時は `ConfigError`

## 6. 処理内容

1. `envparse` で共通 env parser を定義
2. `GCP_PROJECT_ID` 未設定時は `GOOGLE_CLOUD_PROJECT` を fallback
3. `PORT` 未設定時は `8080`
4. parse 完了後に `serviceName` を record に埋める

## 7. 外部リソース

- process environment

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `envparse` | `0.6.0` | 環境変数 parser |
| `text` | `2.1.4` | 設定値 |

### 8.1 ライブラリの役割と使い方

- `envparse`
  - 役割: 文字列の環境変数を型付き設定へ変換する
  - 使い方: 必須値と任意値を分けて parse し、欠損時は明示的に失敗させる
- `text`
  - 役割: 環境変数由来の値を `Text` で扱う
  - 使い方: `serviceName`, `projectId`, `logLevel` などを `Text` にそろえる

最小コードイメージ:

```haskell
data CommonRuntimeEnv = CommonRuntimeEnv
  { port :: Int
  , serviceName :: Text
  }
```

### 8.2 ライブラリの主な使い方

- `envparse`
  - 必須値は `requireTextEnv "SERVICE_VERSION"` のような helper へ閉じ込める
  - 任意値は `optionalTextEnv "K_REVISION"` のように `Maybe Text` で返す
  - 数値は `requireIntEnv "PORT"` のように parse 失敗を `InvalidEnv` に変換する
- `text`
  - `serviceName`, `projectId`, `logLevel` を `Text` で保持し、`String` を境界でだけ変換する

### 8.3 import 例

```haskell
import Data.Text (Text)
import qualified Data.Text as Text
import System.Environment (lookupEnv)
```

補足:

- `envparse` を直接使う場合は、その parser combinator を import する
- 初期実装では `lookupEnv` ベースの helper を作り、後から `envparse` に寄せてもよい
- `String` から `Text` への変換用に `qualified Data.Text` を置くと扱いやすい

## 9. 実装ルール

- env 名は大文字スネークケース固定
- 起動不能な欠損は recover せず fail-fast
- log level は `debug|info|warning|error` のみ許可

## 10. テスト観点

- 必須 env 欠損時に明示的エラーを返す
- fallback (`GOOGLE_CLOUD_PROJECT`) が効く
- `PORT` の数値変換失敗を検出できる

## 11. 実装ヒント

- `loadCommonRuntimeEnv` を作る前に `requireTextEnv` / `optionalTextEnv` / `requireIntEnv` の小関数から作る。
- fallback は parser の中で頑張らず、`lookupEnv` を 2 回見る helper に切り出す方が読みやすい。
- `ConfigError` は `MissingEnv | InvalidEnv` の 2 種から始めると十分。

## 12. 初心者向け実装ロードマップ

### Step 1. 小さい helper から作る

- [src/Shared/Config/Env.hs](/Users/lihs/workspace/alpha-mind/backend/common/haskell/src/Shared/Config/Env.hs) を作る
- `requireTextEnv`, `optionalTextEnv`, `requireIntEnv` の順で追加する
- まずは `System.Environment.lookupEnv` ベースでもよい

いきなり `CommonRuntimeEnv` 全体を作らない方が追いやすい。

最初の実装イメージ:

```haskell
requireTextEnv :: String -> IO Text
requireTextEnv name = do
  value <- lookupEnv name
  case value of
    Nothing -> throwIO (MissingEnv name)
    Just raw -> pure (Text.pack raw)
```

### Step 2. エラー型を最小で定義する

- `MissingEnv`
- `InvalidEnv`

最初はこの 2 つだけで十分。

### Step 3. fallback helper を作る

- `GCP_PROJECT_ID`
- なければ `GOOGLE_CLOUD_PROJECT`

この分岐を専用関数にしておくと `loadCommonRuntimeEnv` が読みやすくなる。

この step で追加するもの:

```haskell
loadProjectId :: IO Text
loadProjectId = do
  primary <- lookupEnv "GCP_PROJECT_ID"
  fallback <- lookupEnv "GOOGLE_CLOUD_PROJECT"
  ...
```

### Step 4. `CommonRuntimeEnv` を組み立てる

- `PORT` は default `8080`
- `serviceName` は引数から受ける
- `revision` は `Maybe Text`

この step でやること:

1. `CommonRuntimeEnv` record を定義する
2. `loadCommonRuntimeEnv :: Text -> IO CommonRuntimeEnv` を追加する
3. `port`, `projectId`, `revision`, `logLevel` を helper から埋める

最初の実装イメージ:

```haskell
loadCommonRuntimeEnv serviceName = do
  port <- fromMaybe 8080 <$> optionalIntEnv "PORT"
  projectId <- loadProjectId
  revision <- optionalTextEnv "K_REVISION"
  pure CommonRuntimeEnv {..}
```

### Step 5. 異常系を先にテストする

- 必須 env 欠損
- `PORT` が数値でない
- fallback が動く

確認コマンドの例:

```bash
cabal build
```

### 完了条件

- env 欠損が明示的に失敗する
- default 値と fallback が期待どおり動く
- `App.Bootstrap` からそのまま使える
