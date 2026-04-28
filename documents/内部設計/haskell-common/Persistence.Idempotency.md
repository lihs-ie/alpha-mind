# Persistence.Idempotency 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- `idempotency_keys` コレクションを使った重複処理防止を Haskell サービス共通で提供する。

## 2. 責務

- `service:identifier` 形式のキー生成
- reserve / complete / alreadyProcessed 判定
- TTL 付き document 保存
- duplicate event の標準扱いを提供

## 3. 公開型・関数

```haskell
data IdempotencyRecord = IdempotencyRecord
  { key :: Text
  , identifier :: ULID
  , trace :: ULID
  , service :: Text
  , processedAt :: Maybe UTCTime
  , expiresAt :: UTCTime
  , updatedAt :: UTCTime
  }

data ReserveResult
  = Reserved
  -- ^ 初回予約に成功した
  | AlreadyProcessed
  -- ^ 完了済みキーが存在する（duplicate event）

data IdempotencyError
  = IdempotencyErrorPersistence FirestoreError
  -- ^ Firestore 操作の失敗（ネットワーク、権限、デコード等）
  | IdempotencyErrorNotReserved Text
  -- ^ complete 対象のキーが存在しない

reserveIdempotency
  :: FirestoreContext
  -> Text
  -> ULID
  -> ULID
  -> IO (Either IdempotencyError ReserveResult)

completeIdempotency
  :: FirestoreContext
  -> Text
  -> ULID
  -> IO (Either IdempotencyError ())
```

## 4. 入力

- `FirestoreContext`
- `service`
- `identifier`
- `trace`
- current time

## 5. 出力

- `ReserveResult = Reserved | AlreadyProcessed`
- 完了結果

## 6. 処理内容

1. key を `service <> ":" <> identifier` で生成
2. Firestore に存在確認
3. 未存在なら `processedAt = null` で reserve
4. 完了時に `processedAt` を更新
5. 既存在かつ `processedAt` ありなら duplicate 扱い

## 7. 外部リソース

- Firestore `idempotency_keys`

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `gogol-firestore` | `1.0.0` | 永続化 |
| `ulid` | `0.3.3.0` | identifier / trace |
| `aeson` | `2.2.3.0` | codec |
| `text` | `2.1.4` | key 構築 |

### 8.1 ライブラリの役割と使い方

- `gogol-firestore`
  - 役割: `idempotency_keys` の永続化先として使う
  - 使い方: 直接この module で触るより、`Persistence.Firestore` の helper 経由に寄せる
- `ulid`
  - 役割: `identifier` と `trace` を型安全に扱う
  - 使い方: key 生成時は render して文字列へする
- `aeson`
  - 役割: record の保存形式を決める補助
  - 使い方: Firestore codec の中間表現として使う
- `text`
  - 役割: `service:identifier` の key を作る
  - 使い方: key 組み立てと collection 名表現に使う

最小コードイメージ:

```haskell
makeKey service identifier = service <> ":" <> renderUlid identifier
```

### 8.2 ライブラリの主な使い方

- `gogol-firestore`
  - 直接 request を書かず、`Persistence.Firestore.getDocument` / `upsertDocument` 経由で使う
- `ulid`
  - `identifier` と `trace` を record では `ULID` で持ち、key 生成時だけ文字列化する
- `aeson`
  - idempotency record の保存 shape を固定するための JSON 中間表現に使う
- `text`
  - `service <> ":" <> renderUlid identifier` の形式で key を作る

### 8.3 import 例

```haskell
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
import Persistence.Firestore
  ( FirestoreContext
  , getDocument
  , upsertDocument
  )
```

補足:

- この module では `gogol-firestore` を直接 import しない方がよい
- Firestore 依存は `Persistence.Firestore` に閉じ込める

## 9. 実装ルール

- TTL は標準 30 日
- duplicate は成功扱いで副作用を起こさない
- Firestore write conflict は retryable

## 10. テスト観点

- 初回 reserve が成功する
- 完了済み key が duplicate 判定される
- `service` ごとに key 空間が分離される

## 11. 実装ヒント

- `reserve` と `complete` だけ先に作り、`release` や `terminate` は必要になってから追加する。
- record 本体は `Persistence.Firestore` の helper に乗せ、ここでは key 生成と状態遷移だけを担当させる。
- duplicate 判定は `processedAt` の有無だけで十分なので、初期実装では状態 enum を増やしすぎない。

## 12. 初心者向け実装ロードマップ

### Step 1. key 生成だけ先に作る

- `service <> ":" <> identifier`
- pure 関数で実装する

ここは一番簡単で、先に固定すると後が楽になる。

最初の実装イメージ:

```haskell
makeIdempotencyKey :: Text -> ULID -> Text
makeIdempotencyKey service identifier = service <> ":" <> renderUlid identifier
```

### Step 2. record 型を作る

- `IdempotencyRecord`
- `processedAt`
- `expiresAt`
- `updatedAt`

まずは保存したい shape を確定する。

この step で作る file:

- `src/Persistence/Idempotency.hs`

### Step 3. `reserve` を先に作る

- 未存在なら reserve
- 既存在かつ完了済みなら duplicate

この step でやること:

1. Firestore から key を読む
2. 無ければ `Reserved`
3. あれば状態を見て duplicate 判定する

### Step 4. `complete` を作る

- `processedAt` を更新する
- `reserve` と分けて考える

最初の実装イメージ:

```haskell
completeIdempotency :: ... -> IO (Either IdempotencyError ())
completeIdempotency ctx service identifier = ...
```

### Step 5. Firestore adapter と接続する

- Firestore への保存・取得は `Persistence.Firestore` に任せる
- この module は状態遷移に集中する

この step で確認すること:

- Firestore request 型をこの module に持ち込まない
- `getDocument` / `upsertDocument` だけ使う
- duplicate 判定ロジックは pure に近い関数へ寄せる

### 完了条件

- 初回 event は `Reserved`
- 完了済み event は `AlreadyProcessed`
- `service` ごとに key 空間が分離される

最終チェック手順:

1. 初回 reserve
2. complete
3. 再度 reserve で `AlreadyProcessed`
