# Observability.Logging 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- `trace`, `identifier`, `service` を含む構造化ログを全 Haskell サービスで統一する。

## 2. 責務

- logger 初期化
- log context の標準化
- JSON 形式での出力
- error / warning / info / debug のレベル統一

## 3. 公開型・関数

```haskell
data LogContext = LogContext
  { service :: Text
  , trace :: Maybe Text
  , identifier :: Maybe Text
  , eventType :: Maybe Text
  , reasonCode :: Maybe Text
  }

initLogger :: CommonRuntimeEnv -> IO LogEnv
logInfoWith :: LogEnv -> LogContext -> Text -> IO ()
logErrorWith :: LogEnv -> LogContext -> Text -> IO ()
```

## 4. 入力

- `CommonRuntimeEnv`
- `LogContext`
- message

## 5. 出力

- Cloud Logging が取り込める JSON ログ

## 6. 処理内容

1. `katip` の namespace を service 名で初期化
2. context を JSON object 化
3. message と level を付与して stdout へ出力
4. exception は stack / error kind を付与

## 7. 外部リソース

- 標準出力
- Cloud Logging

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `katip` | `0.8.8.4` | structured logging |
| `aeson` | `2.2.3.0` | context encode |
| `text` | `2.1.4` | log values |

### 8.1 ライブラリの役割と使い方

- `katip`
  - 役割: 構造化ログ出力の本体
  - 使い方: logger を初期化し、level と context を付けて stdout へ出す
- `aeson`
  - 役割: `LogContext` を JSON へ変換する
  - 使い方: `trace`, `identifier`, `reasonCode` を JSON field にする
- `text`
  - 役割: log message と context 値を持つ
  - 使い方: 文字列を `Text` に統一する

最小コードイメージ:

```haskell
logInfoWith logEnv ctx "service_started"
```

### 8.2 ライブラリの主な使い方

- `katip`
  - `initLogger runtimeEnv` で logger を作り、`logInfoWith` / `logErrorWith` から使う
- `aeson`
  - `LogContext` を `object [...]` で JSON 化して構造化 field を作る
- `text`
  - message、service、reason code を `Text` に統一して扱う

### 8.3 import 例

```haskell
import Data.Aeson (ToJSON, object, (.=))
import Data.Text (Text)
import Katip
  ( LogEnv
  , Namespace
  , Severity (..)
  )
```

補足:

- `katip` は import が多くなりやすいので必要な型だけ明示 import する
- JSON field を作るために `object`, `(.=)` も使う

## 9. 実装ルール

- `service` は必須
- `trace`, `identifier` は判明しているなら必ず載せる
- message は人が読む短文、詳細は structured field 側へ寄せる

## 10. テスト観点

- JSON shape が固定
- context 欠損時に `null` ではなく field omit する
- level に応じて logger が切り替わる

### 8.4 katip 詳細解説

#### 概念モデル

katip は「**何を**ログに出すか」と「**どこに**ログを出すか」を分離した設計になっている。

```
LogEnv（ログ環境）
├── Namespace    : アプリ名（"svc-bff" など）
├── Environment  : 実行環境（"production", "development" など）
└── Scribe[]     : 出力先（stdout, ファイルなど。複数登録可）
```

#### 主要な型

| 型 | 説明 | 例 |
|---|---|---|
| `LogEnv` | ログ環境全体を保持するレコード。初期化時に作り、アプリ全体で使い回す | — |
| `Namespace` | アプリやモジュールの名前空間。`IsString` インスタンスがあるのでリテラルで書ける | `"svc-bff"` |
| `Environment` | 実行環境を表す。同じく `IsString` | `"production"` |
| `Severity` | ログレベル。8 段階 | `DebugS`, `InfoS`, `WarningS`, `ErrorS` など |
| `Verbosity` | 出力の詳細度。`V0`（最小）〜 `V3`（最大） | `V2` |
| `Scribe` | 出力先。stdout / ファイルなどに対応 | — |
| `LogStr` | ログメッセージ。`ls` 関数で `Text` から変換 | `ls "started"` |

#### Severity 一覧

```haskell
data Severity
  = DebugS      -- デバッグ
  | InfoS       -- 情報
  | NoticeS     -- 通常の注目すべき状態
  | WarningS    -- 警告
  | ErrorS      -- エラー
  | CriticalS   -- 重大
  | AlertS      -- 即時対応必要
  | EmergencyS  -- システム使用不可
```

本プロジェクトでは `InfoS` と `ErrorS` を主に使用する。

#### 初期化の流れ

```haskell
import Katip
import System.IO (stdout)

initLogger :: Text -> Text -> IO LogEnv
initLogger serviceName env = do
  -- 1. LogEnv を作る（アプリ名 + 環境名）
  logEnv <- initLogEnv (Namespace [serviceName]) (Environment env)
  -- 2. Scribe（出力先）を作る
  --    jsonFormat: JSON 形式で出力（Cloud Logging と相性が良い）
  --    ColorIfTerminal: ターミナルなら色付き
  --    stdout: 標準出力へ
  --    permitItem InfoS: InfoS 以上を出力（DebugS は除外）
  --    V2: Verbosity レベル 2
  scribe <- mkHandleScribeWithFormatter jsonFormat ColorIfTerminal stdout (permitItem InfoS) V2
  -- 3. Scribe を LogEnv に登録
  registerScribe "stdout" scribe defaultScribeSettings logEnv
```

#### Scribe のフォーマッタ

| フォーマッタ | 出力形式 | 用途 |
|---|---|---|
| `jsonFormat` | JSON 1行 | **本プロジェクトで使用**。Cloud Logging が自動パースできる |
| `bracketFormat` | `[時刻][App][Level]...` | 人間が読むデバッグ用 |

#### カスタム payload（LogContext の組み込み方）

katip にカスタムデータを載せるには `ToObject` と `LogItem` の 2 つの型クラスが必要:

```haskell
-- 1. ToObject: JSON object への変換（ToJSON があればデフォルト実装が使える）
class ToObject a where
  toObject :: a -> Object

-- 2. LogItem: どの Verbosity でどのキーを出すかを制御
class ToObject a => LogItem a where
  payloadKeys :: Verbosity -> a -> PayloadSelection
```

`LogContext` への実装例:

```haskell
instance ToJSON LogContext where
  toJSON ctx =
    object $
      ["service" .= service ctx]
        <> maybe [] (\v -> ["trace" .= v]) (trace ctx)
        <> maybe [] (\v -> ["identifier" .= v]) (identifier ctx)
        <> maybe [] (\v -> ["eventType" .= v]) (eventType ctx)
        <> maybe [] (\v -> ["reasonCode" .= v]) (reasonCode ctx)

instance ToObject LogContext  -- ToJSON があればデフォルト実装で OK

instance LogItem LogContext where
  payloadKeys V0 _ = SomeKeys ["service"]           -- 最小: service のみ
  payloadKeys _  _ = AllKeys                         -- V1 以上: 全フィールド
```

#### ログ出力関数

katip には 2 つのアプローチがある:

**アプローチ 1: `KatipT` モナドを使う（型クラス経由）**

```haskell
runKatipT logEnv $ do
  logF myContext "myModule" InfoS "started"
```

**アプローチ 2: `LogEnv` を明示的に渡す（本プロジェクトの方針）**

設計書§11 の方針に従い、最初は `LogEnv` を引数で渡す。内部的には `runKatipT` を使うが、呼び出し側には隠す:

```haskell
logInfoWith :: LogEnv -> LogContext -> Text -> IO ()
logInfoWith logEnv ctx message =
  runKatipT logEnv $
    logF ctx mempty InfoS (ls message)

logErrorWith :: LogEnv -> LogContext -> Text -> IO ()
logErrorWith logEnv ctx message =
  runKatipT logEnv $
    logF ctx mempty ErrorS (ls message)
```

- `logF :: LogItem a => a -> Namespace -> Severity -> LogStr -> m ()`
  - 第 1 引数: payload（`LogContext`）
  - 第 2 引数: 追加の namespace（不要なら `mempty`）
  - 第 3 引数: ログレベル
  - 第 4 引数: メッセージ（`ls` で `Text` → `LogStr` に変換）

#### 終了処理

アプリ終了時に `closeScribes` でバッファをフラッシュする:

```haskell
closeScribes :: LogEnv -> IO LogEnv
```

`Bootstrap.runService` のシャットダウン処理で呼ぶ。

## 11. 実装ヒント

- 最初は `initLogger`, `logInfoWith`, `logErrorWith` の 3 関数だけ実装する。
- `LogContext` を `ToJSON` instance にしておくと、追加項目を後から増やしやすい。
- `KatipContextT` を全体へ広げる前に、まずは `LogEnv` を明示引数で渡す実装で始めると追いやすい。

## 12. 初心者向け実装ロードマップ

### Step 1. `LogContext` を先に作る

- まず `src/Observability/Logging.hs` を作る
- `service` だけ必須にし、他の field は `Maybe Text` で始める
- 最初は record を定義するだけでよい

この step でファイルに追加するもの:

```haskell
data LogContext = LogContext
  { service :: Text
  , trace :: Maybe Text
  , identifier :: Maybe Text
  , eventType :: Maybe Text
  , reasonCode :: Maybe Text
  }
```

### Step 2. context の JSON 化を作る

- `ToJSON` instance を追加する
- `Nothing` を `null` で出すか field omit するかを決める
- 初期実装では `Nothing` の field を出さない方が扱いやすい

最初の実装イメージ:

```haskell
instance ToJSON LogContext where
  toJSON ctx =
    object $
      ["service" .= service ctx]
        <> maybe [] (\v -> ["trace" .= v]) (trace ctx)
        <> maybe [] (\v -> ["identifier" .= v]) (identifier ctx)
```

### Step 3. logger 初期化を作る

- `initLogger :: CommonRuntimeEnv -> IO LogEnv` の型を書く
- 最初は stdout に 1 種類の logger を出すだけでよい
- `debug` と `info` の切り替えは後回しでもよい

この step でやること:

1. `initLogger` のシグネチャを書く
2. `katip` の初期化コードを最小で入れる
3. `cabal build` が通る状態にする

### Step 4. 出力関数を 2 つだけ作る

- `logInfoWith` と `logErrorWith` だけ先に作る
- message は `Text`
- context は `LogContext`

debug や warning は後で増やせばよい。

最初の実装イメージ:

```haskell
logInfoWith :: LogEnv -> LogContext -> Text -> IO ()
logInfoWith logEnv ctx message = ...
```

### Step 5. 例外時の出力を足す

- `SomeException` を受ける helper を 1 つ追加する
- 例外文字列を message にし、`reasonCode` は呼び出し側から渡せる形でよい
- `trace` と `identifier` は `LogContext` に既に入るので再設計しない

### 完了条件

- JSON ログを stdout に出せる
- `service` が必ず出る
- `trace` と `identifier` を任意で付けられる

最終チェック手順:

1. `shared.cabal` に `Observability.Logging` を登録する
2. `cabal build` を実行する
3. `logInfoWith` を 1 回呼ぶ小さな `main` で stdout を確認する
