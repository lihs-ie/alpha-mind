# Messaging.CloudEvent 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- `共通設計.md` で定義されたイベントエンベロープを Haskell で統一的に表現し、validate / encode / decode を共通化する。

## 2. 責務

- CloudEvent 互換 envelope 型定義
- JSON decode / encode
- `identifier`, `trace`, `occurredAt`, `schemaVersion` の検証
- payload と envelope の分離

## 3. 公開型・関数

```haskell
data CloudEvent payload = CloudEvent
  { identifier :: ULID
  , eventType :: Text
  , occurredAt :: UTCTime
  , trace :: ULID
  , schemaVersion :: Text
  , payload :: payload
  }

decodeCloudEvent :: FromJSON payload => ByteString -> Either CloudEventError (CloudEvent payload)
encodeCloudEvent :: ToJSON payload => CloudEvent payload -> ByteString
validateEventType :: Text -> CloudEvent payload -> Either CloudEventError (CloudEvent payload)
```

## 4. 入力

- Pub/Sub message body または publish 対象 payload
- expected `eventType`
- `schemaVersion`

## 5. 出力

- 成功: `CloudEvent payload`
- 失敗: `CloudEventError`
- publish 用 JSON bytes

## 6. 処理内容

1. JSON object を decode
2. `identifier` / `trace` を ULID として parse
3. `occurredAt` を ISO8601 UTC として parse
4. `schemaVersion` が空文字でないことを確認
5. payload を型付き decode
6. publish 時は field 順序を固定せず JSON encode

## 7. 外部リソース

- Pub/Sub payload JSON

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `aeson` | `2.2.3.0` | JSON |
| `text` | `2.1.4` | eventType / schemaVersion |
| `ulid` | `0.3.3.0` | `identifier`, `trace` |
| `unordered-containers` | `0.2.21` | object 操作 |

### 8.1 ライブラリの役割と使い方

- `aeson`
  - 役割: CloudEvent JSON の decode / encode を行う
  - 使い方: `RawCloudEvent` を `FromJSON` で受け、その後 typed event に変換する
- `text`
  - 役割: `eventType`, `schemaVersion` を表現する
  - 使い方: 文字列比較や空文字チェックに使う
- `ulid`
  - 役割: `identifier` と `trace` を専用型で扱う
  - 使い方: 文字列から parse し、不正値を decode error にする
- `unordered-containers`
  - 役割: 生 JSON object を扱うときの補助
  - 使い方: `payload` を取り出す前の中間表現に使う

最小コードイメージ:

```haskell
decodeCloudEvent :: FromJSON payload => ByteString -> Either CloudEventError (CloudEvent payload)
decodeCloudEvent = ...
```

### 8.2 ライブラリの主な使い方

- `aeson`
  - `eitherDecode` で raw JSON を受け、`encode` で publish 用 bytes を作る
- `text`
  - `eventType` と `schemaVersion` の比較や空文字チェックに使う
- `ulid`
  - `parseUlidText rawIdentifier` のような helper で `Text` から `ULID` へ変換する
- `unordered-containers`
  - raw object を経由して `payload` を個別 decode するときの中間表現に使う

### 8.3 import 例

```haskell
import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode)
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.ULID (ULID)
```

補足:

- `eitherDecode` / `encode` は `aeson`
- `ByteString` は CloudEvent の JSON bytes を扱うために必要
- `UTCTime` と `ULID` は最終型で使う

## 9. 実装ルール

- `eventType` はサービス側で exact match する
- `occurredAt` は timezone-aware でない値を拒否
- `payload` decode 失敗は envelope 正常でも `CloudEventErrorPayloadInvalid`

## 10. テスト観点

- 正常 envelope が decode できる
- ULID 不正を拒否する
- `occurredAt` の timezone 欠損を拒否する
- `eventType` mismatch を拒否する

### 10.1 `CloudEventError` の設計

`CloudEventError` は decode / validate の各失敗を表す。§9 の実装ルールと §10 のテスト観点から以下のコンストラクタを導出する。

```haskell
data CloudEventError
  = CloudEventErrorJsonInvalid Text
    -- ^ JSON として parse できない（eitherDecode 失敗）
  | CloudEventErrorIdentifierInvalid Text
    -- ^ identifier が ULID として不正
  | CloudEventErrorTraceInvalid Text
    -- ^ trace が ULID として不正
  | CloudEventErrorOccurredAtInvalid Text
    -- ^ occurredAt が ISO8601 UTC として不正（timezone 欠損を含む）
  | CloudEventErrorSchemaVersionEmpty
    -- ^ schemaVersion が空文字
  | CloudEventErrorEventTypeMismatch Text Text
    -- ^ eventType 不一致（expected, actual）
  | CloudEventErrorPayloadInvalid Text
    -- ^ envelope は正常だが payload の decode に失敗
  deriving stock (Show, Eq)
```

対応表:

| コンストラクタ | 発生箇所 | 根拠 |
|---|---|---|
| `CloudEventErrorJsonInvalid` | `decodeRawCloudEvent` | §6 step 1 |
| `CloudEventErrorIdentifierInvalid` | `parseUlidText` | §10「ULID 不正を拒否する」 |
| `CloudEventErrorTraceInvalid` | `parseUlidText` | §10「ULID 不正を拒否する」 |
| `CloudEventErrorOccurredAtInvalid` | `parseOccurredAt` | §9「timezone-aware でない値を拒否」/ §10 |
| `CloudEventErrorSchemaVersionEmpty` | `toCloudEvent` | §6 step 4 |
| `CloudEventErrorEventTypeMismatch` | `validateEventType` | §10「eventType mismatch を拒否する」 |
| `CloudEventErrorPayloadInvalid` | `toCloudEvent` | §9「payload decode 失敗は CloudEventErrorPayloadInvalid」 |

## 11. 実装ヒント

- 最初に `RawCloudEvent` を `Value` ベースで定義し、その後 `CloudEvent payload` へ変換する 2 段構成にすると実装しやすい。
- validation は `FromJSON` instance に全部詰め込まず、`decode -> validate -> toTyped` の順に分ける。
- `identifier` と `trace` は同じ parser を使うので、`parseUlidField :: Text -> Object -> Parser ULID` のような helper を先に作る。

## 12. 初心者向け実装ロードマップ

### Step 1. 先に最終型を決める

- まず `src/Messaging/CloudEvent.hs` を作る
- `CloudEvent payload` の record を書く
- field 名は設計書に合わせて固定する

この step で追加するもの:

```haskell
data CloudEvent payload = CloudEvent
  { identifier :: ULID
  , eventType :: Text
  , occurredAt :: UTCTime
  , trace :: ULID
  , schemaVersion :: Text
  , payload :: payload
  }
```

### Step 2. `RawCloudEvent` を別で作る

- JSON decode 用に `RawCloudEvent payload` を別に作る
- `identifier`, `trace`, `occurredAt` は最初は `Text`
- ここでは「JSON を受け取れること」だけを目的にする

最初の実装イメージ:

```haskell
data RawCloudEvent payload = RawCloudEvent
  { rawIdentifier :: Text
  , rawEventType :: Text
  , rawOccurredAt :: Text
  , rawTrace :: Text
  , rawSchemaVersion :: Text
  , rawPayload :: payload
  }
```

### Step 3. decode と validate を分ける

- `eitherDecode` で `RawCloudEvent`
- その後に ULID / 時刻 / schemaVersion を検証
- 最後に `CloudEvent payload` に変換

この step でやること:

1. `decodeRawCloudEvent` を作る
2. `toCloudEvent` を作る
3. `decodeCloudEvent = decodeRawCloudEvent >=> toCloudEvent` の形へ寄せる

### Step 4. helper を切り出す

- ULID parse helper
- `occurredAt` parse helper
- `eventType` 検証 helper

1 関数に詰め込まないことが大事。

この step で追加する関数例:

```haskell
parseUlidText :: Text -> Either CloudEventError ULID
parseOccurredAt :: Text -> Either CloudEventError UTCTime
validateEventType :: Text -> CloudEvent payload -> Either CloudEventError (CloudEvent payload)
```

### Step 5. encode を最後に作る

- decode が安定してから `encodeCloudEvent` を書く
- round-trip テストが書けると理解しやすい

最初の実装イメージ:

```haskell
encodeCloudEvent :: ToJSON payload => CloudEvent payload -> ByteString
encodeCloudEvent event = encode ...
```

### 完了条件

- 正常 JSON を decode できる
- ULID / 時刻不正を弾ける
- encode / decode の round-trip が成立する

最終チェック手順:

1. 正常 JSON fixture を 1 つ作る
2. `decodeCloudEvent` で通ることを確認する
3. `encodeCloudEvent` 後に再 decode して round-trip を確認する
