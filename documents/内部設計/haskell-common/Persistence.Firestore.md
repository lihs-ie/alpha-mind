# Persistence.Firestore 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- Firestore への document 読み書きをサービス共通の adapter として提供する。
- Haskell サービスごとに Firestore REST request と JSON codec を重複実装しないようにする。

## 2. 責務

- Firestore client 初期化
- collection / document path の構築
- get / create / patch / upsert / query の薄い API
- Firestore JSON と Haskell record の相互変換

## 3. 公開型・関数

```haskell
data FirestoreContext = FirestoreContext
  { projectId :: Text
  , databaseId :: Text
  }

newtype CollectionName = CollectionName Text
newtype DocumentId = DocumentId Text

data FirestoreError
  = FirestoreErrorDecode Text
  -- ^ document の decode に失敗（schema mismatch）
  | FirestoreErrorPermissionDenied Text
  -- ^ 認証・認可エラー（403）
  | FirestoreErrorTransport Text
  -- ^ ネットワーク障害・タイムアウト（retry 上限超過後）
  | FirestoreErrorUnexpected Int Text
  -- ^ 想定外の HTTP status とメッセージ
  deriving (Show, Eq)

getDocument
  :: FromFirestore a
  => FirestoreContext
  -> CollectionName
  -> DocumentId
  -> IO (Either FirestoreError (Maybe a))

upsertDocument
  :: ToFirestore a
  => FirestoreContext
  -> CollectionName
  -> DocumentId
  -> a
  -> IO (Either FirestoreError ())
```

## 4. 入力

- `FirestoreContext`
- collection 名
- document id
- 保存対象 record

## 5. 出力

- `Maybe a`
- 永続化成功 / 失敗
- Firestore 固有エラーを包んだ `FirestoreError`

## 6. 処理内容

1. `projects/{project}/databases/{database}/documents/...` を構築
2. `ToFirestore` で Firestore document 形式へ変換
3. `gogol-firestore` で REST 呼び出し
4. 404 は `Nothing` へ変換
5. schema mismatch は `FirestoreErrorDecode`

## 7. 外部リソース

- Firestore API v1
- Firestore emulator（テスト時）

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `gogol` | `1.0.0.0` | Google auth |
| `gogol-firestore` | `1.0.0` | Firestore API |
| `aeson` | `2.2.3.0` | document codec |
| `text` | `2.1.4` | path / IDs |
| `retry` | `0.9.3.1` | transient retry |

### 8.1 ライブラリの役割と使い方

- `gogol`
  - 役割: Google API 共通の認証基盤
  - 使い方: Firestore API を叩く前の auth context を作る
- `gogol-firestore`
  - 役割: Firestore の request / response 型を提供する
  - 使い方: document get や patch を組み立てる内部実装に使う
- `aeson`
  - 役割: domain record と Firestore document の変換補助
  - 使い方: service record を JSON に寄せて中間変換する
- `text`
  - 役割: collection 名、document id、path を扱う
  - 使い方: path 組み立てや識別子表現に使う
- `retry`
  - 役割: transient error の再試行
  - 使い方: timeout や一時的 5xx を数回だけ再試行する

最小コードイメージ:

```haskell
getDocument ctx (CollectionName "orders") (DocumentId "123")
```

### 8.2 ライブラリの主な使い方

- `gogol`
  - Firestore API を呼ぶ前に auth context を初期化する
- `gogol-firestore`
  - get / patch / create 用 request 型を module 内部で組み立てる
- `aeson`
  - domain record を一度 JSON 寄りの中間表現へ落として Firestore document へ変換する
- `text`
  - collection 名、document id、document path の組み立てに使う
- `retry`
  - timeout や一時的な 5xx を数回再試行する wrapper に使う

### 8.3 import 例

```haskell
import Data.Text (Text)
import Gogol (Env, newEnv, send, sendEither)
import Gogol.FireStore.Types (Document (..), Document_Fields (..), Value (..), newValue, newDocument)
import Gogol.FireStore.Projects.Databases.Documents.Get qualified as Documents
import Gogol.FireStore.Projects.Databases.Documents.Patch qualified as Documents
import Control.Monad.Trans.Resource (runResourceT)
```

補足:

- gogol 1.0 では module 名は `Gogol.*`（`Network.Google.*` は旧版）
- `Gogol` が auth / 実行環境用
- Firestore 専用 request は `Gogol.FireStore.*` 側の module から import する
- package の生成 module 名は長いので `qualified` import を推奨する

### 8.4 gogol-firestore 詳細解説

以下は `gogol` / `gogol-firestore` ライブラリが提供する型・関数のリファレンスである。**自前で実装しない。**

#### モジュール構成

| モジュール | 用途 |
|---|---|
| `Gogol.FireStore.Types` | Document, Value 等の全型定義をre-export |
| `Gogol.FireStore.Projects.Databases.Documents.Get` | document 取得 |
| `Gogol.FireStore.Projects.Databases.Documents.Patch` | document 更新 / upsert |
| `Gogol.FireStore.Projects.Databases.Documents.CreateDocument` | document 新規作成 |
| `Gogol.FireStore.Projects.Databases.Documents.Delete` | document 削除 |

#### Document 型

```haskell
data Document = Document
  { createTime :: Maybe DateTime
  , fields :: Maybe Document_Fields
  , name :: Maybe Text      -- "projects/{pid}/databases/{did}/documents/{collection}/{docId}"
  , updateTime :: Maybe DateTime
  }

newtype Document_Fields = Document_Fields
  { additional :: HashMap Text Value
  }
```

`fields` が実際のデータ本体。`HashMap Text Value` として field 名と値のペアを保持する。

#### Value 型

Firestore の field 値を表す。各 field は `Maybe` で、ちょうど 1 つだけ `Just` にする:

```haskell
data Value = Value
  { arrayValue     :: Maybe ArrayValue
  , booleanValue   :: Maybe Bool
  , bytesValue     :: Maybe Base64
  , doubleValue    :: Maybe Double
  , geoPointValue  :: Maybe LatLng
  , integerValue   :: Maybe Int64
  , mapValue       :: Maybe MapValue
  , nullValue      :: Maybe Value_NullValue
  , referenceValue :: Maybe Text
  , stringValue    :: Maybe Text
  , timestampValue :: Maybe DateTime
  }

newValue :: Value  -- 全 field が Nothing のスマートコンストラクタ
```

Value の構築例（**自前で実装する** codec 内部ヘルパー）:

```haskell
-- Text → Value
textValue :: Text -> Value
textValue t = newValue { stringValue = Just t }

-- Bool → Value
boolValue :: Bool -> Value
boolValue b = newValue { booleanValue = Just b }

-- Int → Value
intValue :: Int64 -> Value
intValue n = newValue { integerValue = Just n }

-- UTCTime → Value（DateTime への変換が必要）
timestampVal :: DateTime -> Value
timestampVal dt = newValue { timestampValue = Just dt }
```

#### コンテナ型

```haskell
newtype ArrayValue = ArrayValue
  { values :: Maybe [Value]
  }

newtype MapValue = MapValue
  { fields :: Maybe MapValue_Fields
  }

newtype MapValue_Fields = MapValue_Fields
  { additional :: HashMap Text Value
  }
```

#### リクエスト実行

gogol は `send` / `sendEither` で request を実行する:

```haskell
-- 成功時は値を返し、失敗時は例外を投げる
send :: (MonadResource m, AllowRequest a scopes) => Env scopes -> a -> m (Rs a)

-- 失敗を Either で返す
sendEither :: (MonadResource m, AllowRequest a scopes) => Env scopes -> a -> m (Either Error (Rs a))
```

#### Get リクエスト

```haskell
-- スマートコンストラクタ（name は必須）
newFireStoreProjectsDatabasesDocumentsGet
  :: Text  -- "projects/{pid}/databases/{did}/documents/{collection}/{docId}"
  -> FireStoreProjectsDatabasesDocumentsGet

-- レスポンス型は Document
-- type Rs FireStoreProjectsDatabasesDocumentsGet = Document
```

#### Patch リクエスト（upsert に使用）

```haskell
-- スマートコンストラクタ（name と payload が必須）
newFireStoreProjectsDatabasesDocumentsPatch
  :: Document  -- 書き込む document
  -> Text      -- document path
  -> FireStoreProjectsDatabasesDocumentsPatch

-- レスポンス型は Document
-- type Rs FireStoreProjectsDatabasesDocumentsPatch = Document
```

`updateMaskFieldPaths` を省略すると全 field を上書き（upsert 相当）。

#### Document path の構築（**自前で実装する**）

```haskell
buildDocumentPath :: FirestoreContext -> CollectionName -> DocumentId -> Text
buildDocumentPath ctx (CollectionName col) (DocumentId docId) =
  "projects/" <> ctx.projectId
    <> "/databases/" <> ctx.databaseId
    <> "/documents/" <> col
    <> "/" <> docId
```

#### 実行パターン（**自前で実装する** `getDocument` / `upsertDocument` 内部の参考コード）

```haskell
import Control.Monad.Trans.Resource (runResourceT)

-- Env を初期化（GCP 環境では ADC を自動検出）
env <- runResourceT newEnv

-- Get
let path = buildDocumentPath ctx collection docId
    req = Documents.newFireStoreProjectsDatabasesDocumentsGet path
result <- runResourceT $ sendEither env req

-- Patch (upsert)
let doc = newDocument { name = Just path, fields = Just (Document_Fields fieldsMap) }
    req = Documents.newFireStoreProjectsDatabasesDocumentsPatch doc path
result <- runResourceT $ sendEither env req
```

### 8.5 ToFirestore / FromFirestore typeclass 設計（**自前で実装する**）

gogol-firestore の `Value` 型を直接 service 側に公開しないため、自前の typeclass で変換を抽象化する:

```haskell
class ToFirestore a where
  toFirestoreFields :: a -> HashMap Text Value

class FromFirestore a where
  fromFirestoreFields :: HashMap Text Value -> Either Text a
```

- `toFirestoreFields` は record を `HashMap Text Value` に変換する（`Document_Fields` の中身）
- `fromFirestoreFields` は `HashMap Text Value` から record を復元する。field 不足や型不一致は `Left` で返す
- service 側はこの typeclass だけ実装すれば Firestore の wire format を知る必要がない

## 9. 実装ルール

- database はデフォルト `(default)` を標準とする
- collection 名は raw `Text` ではなく `CollectionName` で扱う
- Firestore 依存を services 側へ漏らさないため、service 側は `ToFirestore` / `FromFirestore` だけ実装する

## 10. テスト観点

- emulator に対して get / upsert が動く
- 404 が `Nothing` になる
- schema mismatch を decode error として返せる

## 11. 実装ヒント

- 最初は `getDocument` と `upsertDocument` の 2 関数だけで始める。
- `ToFirestore` / `FromFirestore` は最初から複雑な typeclass にせず、`toFirestoreValue` / `fromFirestoreValue` の薄い interface で十分。
- Firestore の wire format は癖があるので、module 内部に `WireDocument` を置いて services 側へ漏らさない。

## 12. 初心者向け実装ロードマップ

### Step 1. path と context を固める

- `FirestoreContext`、`CollectionName`、`DocumentId` の 3 型を定義する
- まずは path を安全に扱う型を作る

この step で作る file:

- `src/Persistence/Firestore.hs`

ヒント:

- `FirestoreContext` は `projectId` と `databaseId` を持つ record
- `CollectionName` と `DocumentId` は raw `Text` と区別するために newtype にする
- §3 の公開型定義を参照

### Step 2. path 構築関数を作る

- Firestore REST API が要求する document path 文字列を組み立てる関数を作る

ヒント:

- path の形式は `projects/{projectId}/databases/{databaseId}/documents/{collection}/{docId}`
- §8.4「Document path の構築」を参照
- `FirestoreContext`、`CollectionName`、`DocumentId` を引数に取る

### Step 3. read と write の最小 API を作る

- `getDocument` と `upsertDocument` の 2 関数だけで始める
- query や patch は後回しでよい

ヒント:

- §3 の関数シグネチャを参照
- gogol の `sendEither` を使うとエラーを `Either` で受けられる（§8.4「リクエスト実行」参照）
- Get には `newFireStoreProjectsDatabasesDocumentsGet` を使う（§8.4「Get リクエスト」参照）
- Upsert には `newFireStoreProjectsDatabasesDocumentsPatch` を使う（§8.4「Patch リクエスト」参照）
- `Env` の初期化には `runResourceT` + `newEnv` を使う
- HTTP 404 は `Nothing` に変換し、それ以外のエラーは `FirestoreError` の適切なバリアントに変換する

### Step 4. codec を薄く実装する

- `ToFirestore` / `FromFirestore` typeclass を定義する
- 最初は必要な field 型だけ対応すればよい

ヒント:

- §8.5 の typeclass 設計を参照
- gogol-firestore の `Value` 型は各フィールド値が `Maybe` で、1 つだけ `Just` にする構造（§8.4「Value 型」参照）
- `newValue` スマートコンストラクタで全 field `Nothing` の Value を作り、必要な field だけ record update する
- 最初に対応する field 型: `Text`, `Int`, `Bool`, `UTCTime`, `Maybe`
- `Document_Fields` の中身は `HashMap Text Value` なので、typeclass のメソッドはこの型との変換にする
- field が見つからない場合や型が合わない場合は `Left` でエラーメッセージを返す

### Step 5. emulator で検証する

- Firestore emulator に対して正常系と異常系を確認する

確認項目:

1. path の組み立てが正しい
2. `upsertDocument` → `getDocument` で round-trip できる
3. 存在しない document の get が `Right Nothing` になる
4. field の型が合わない document を get すると `Left (FirestoreErrorDecode ...)` になる

ヒント:

- `gcloud emulators firestore start` で emulator を起動する
- `FIRESTORE_EMULATOR_HOST` 環境変数が設定されていれば gogol は emulator に接続する

### 完了条件

- document を読み書きできる
- Firestore 固有形式（`Value`, `Document` 等）が service 側に漏れない
- emulator で正常系と異常系を確認できる
