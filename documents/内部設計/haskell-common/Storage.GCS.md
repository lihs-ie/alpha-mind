# Storage.GCS 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- Cloud Storage への bytes / JSON / text の入出力を Haskell サービス共通で提供する。

## 2. 責務

- `gs://bucket/path` の parse
- download / upload
- content-type 設定
- metadata 読み書き

## 3. 公開型・関数

```haskell
data GcsObjectRef = GcsObjectRef
  { bucket :: Text
  , objectPath :: Text
  }

parseGsUri :: Text -> Either GcsError GcsObjectRef
downloadObject :: GcsContext -> GcsObjectRef -> IO (Either GcsError ByteString)
uploadObject
  :: GcsContext
  -> GcsObjectRef
  -> Text
  -> ByteString
  -> IO (Either GcsError ())
```

## 4. 入力

- `gs://...` URI または bucket / object path
- content-type
- bytes payload

## 5. 出力

- `GcsObjectRef`
- downloaded bytes
- upload 成功 / 失敗

## 6. 処理内容

1. `gs://` URI を parse
2. `gogol-storage` で object を取得 / 作成
3. upload 時は content-type と custom metadata を設定
4. transient error は retry

## 7. 外部リソース

- Google Cloud Storage JSON API
- fake-gcs-server（テスト時）

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `gogol` | `1.0.0.0` | auth |
| `gogol-storage` | `1.0.0` | GCS API |
| `text` | `2.1.4` | URI / path |
| `aeson` | `2.2.3.0` | metadata JSON |
| `retry` | `0.9.3.1` | retry |

### 8.1 ライブラリの役割と使い方

- `gogol`
  - 役割: GCS API を呼ぶための認証基盤
  - 使い方: upload / download 前に auth context を作る
- `gogol-storage`
  - 役割: object の取得・作成 request を表現する
  - 使い方: download と upload の内部実装に閉じ込める
- `text`
  - 役割: `gs://bucket/path` の parse 結果を扱う
  - 使い方: bucket 名と object path を保持する
- `aeson`
  - 役割: object metadata を JSON で扱う
  - 使い方: custom metadata の encode / decode に使う
- `retry`
  - 役割: transient error の upload / download を再試行する
  - 使い方: timeout や一時 5xx に限定して再試行する

最小コードイメージ:

```haskell
parseGsUri "gs://bucket/path/to/file"
```

### 8.2 ライブラリの主な使い方

- `gogol`
  - GCS 用 auth context を初期化して API 呼び出しに渡す
- `gogol-storage`
  - object download / upload 用 request を module 内部で組み立てる
- `text`
  - `gs://bucket/path` を parse して bucket と object path を保持する
- `aeson`
  - custom metadata を JSON として encode / decode する
- `retry`
  - upload / download の transient error を数回だけ再試行する

### 8.3 import 例

```haskell
import Data.Aeson (Value)
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import Network.Google (Env, runGoogle)
import Network.Google.Storage qualified as Storage
```

補足:

- `gogol-storage` は module 名が長くなりやすいので `qualified` import が安全
- upload / download の payload は `ByteString`
- metadata を使う場合は `aeson` の `Value` があると扱いやすい

## 9. 実装ルール

- URI parse は bucket 空文字を拒否
- object path 先頭 `/` は normalize して除去
- upload は overwrite を標準動作とする

## 10. テスト観点

- `gs://bucket/path/to/file` を正しく parse できる
- invalid URI を reject できる
- fake-gcs-server に upload / download できる

## 11. 実装ヒント

- 先に `parseGsUri` を pure 関数で固め、その後 `downloadObject` / `uploadObject` を足す。
- bytes I/O だけ先に実装し、JSON helper はその上に `encode` / `eitherDecode` を被せる。
- object metadata は最初から汎用 map にしておくと、後で `contentEncoding` や `customTime` を追加しやすい。

## 12. 初心者向け実装ロードマップ

### Step 1. URI parse を先に作る

- `parseGsUri`
- bucket 空文字を拒否
- 先頭 `/` の normalize

まず pure 関数から始める。

この step で作る file:

- `src/Storage/GCS.hs`

最初の実装イメージ:

```haskell
parseGsUri :: Text -> Either GcsError GcsObjectRef
parseGsUri uri = ...
```

### Step 2. `GcsObjectRef` を使って download を作る

- bytes を取るだけの最小 API
- text / JSON helper はまだ作らない

この step でやること:

1. `downloadObject :: ... -> IO (Either GcsError ByteString)`
2. 認証付き client を受け取る
3. object body を bytes で返す

### Step 3. upload を作る

- content-type
- bytes payload
- overwrite 標準

最初の実装イメージ:

```haskell
uploadObject
  :: GcsContext
  -> GcsObjectRef
  -> Text
  -> ByteString
  -> IO (Either GcsError ())
```

### Step 4. metadata を後から足す

- まずは必須でない
- bytes I/O が安定してから追加する

この step でやること:

- custom metadata を `Maybe Value` や map で受ける helper を追加する
- 初期実装の `uploadObject` は壊さない

### Step 5. fake server か test bucket で確認する

- upload
- download
- invalid URI

この step で確認すること:

1. `gs://bucket/path/to/file` を parse できる
2. upload した bytes を download で戻せる
3. 無効 URI を `Left` にできる

### 完了条件

- `gs://` URI を正しく parse できる
- bytes の upload / download が動く
- JSON helper を後付けできる土台がある

最終チェック手順:

1. invalid URI を 1 つ試す
2. valid URI を parse する
3. upload / download を 1 往復確認する
