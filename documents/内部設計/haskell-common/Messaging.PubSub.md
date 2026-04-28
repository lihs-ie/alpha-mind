# Messaging.PubSub 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- Cloud Run の Pub/Sub push 受信と Pub/Sub publish を Haskell サービス共通の実装として提供する。

## 2. 責務

- push body の decode
- CloudEvent payload の取り出し
- publish request 組み立て
- retryable / non-retryable 失敗の返却方針統一

## 3. 公開型・関数

```haskell
data PubSubPushEnvelope = PubSubPushEnvelope
  { messageId :: Text
  , publishTime :: UTCTime
  , dataBase64 :: Text
  }

decodePubSubPush
  :: FromJSON payload
  => ByteString
  -> Either PubSubError (CloudEvent payload)

publishCloudEvent
  :: ToJSON payload
  => PubSubPublisher
  -> TopicName
  -> CloudEvent payload
  -> IO (Either PubSubError PublishResult)
```

## 4. 入力

- HTTP request body (`message.data` を含む Pub/Sub push body)
- `TopicName`
- `CloudEvent payload`
- project id / auth context

## 5. 出力

- subscribe 側: `CloudEvent payload`
- publish 側: `PublishResult { messageId :: Text }`

## 6. 処理内容

受信:

1. push body を JSON decode
2. `message.data` を base64 decode
3. 中身を `Messaging.CloudEvent` へ渡す
4. decode 失敗時は `400` 相当の non-retryable error を返す

送信:

1. topic path を `projects/{project}/topics/{topic}` に正規化
2. CloudEvent JSON を `PubsubMessage.data` に詰める
3. `https://pubsub.googleapis.com/v1/{topic}:publish` へ REST request を送る
4. 一時障害は `Resilience.Retry` で再試行

## 7. 外部リソース

- Pub/Sub push HTTP body
- Google Cloud Pub/Sub API v1

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `aeson` | `2.2.3.0` | push body decode |
| `gogol` | `1.0.0.0` | ADC / access token 取得 |
| `http-client` | `0.7.19` | Pub/Sub REST 呼び出し |
| `base64` | `1.0` | `message.data` encode |
| `retry` | `0.9.3.1` | publish retry |
| `text` | `2.1.4` | topic / IDs |

### 8.1 ライブラリの役割と使い方

- `aeson`
  - 役割: Pub/Sub push body と publish request body を JSON で扱う
  - 使い方: push 側では decode、publish 側では encode に使う
- `gogol`
  - 役割: production で Google 認証済みの publish client を作る
  - 使い方: ADC を使って access token を得る部分に閉じ込める
- `http-client`
  - 役割: Pub/Sub REST API へ publish request を送る
  - 使い方: topic URL を組み立て、JSON body を POST する
- `base64`
  - 役割: `message.data` の decode / encode
  - 使い方: push では decode、publish では encode に使う
- `retry`
  - 役割: 一時障害の publish を再試行する
  - 使い方: `Resilience.Retry.withRetry` の内部実装や呼び出し先として使う
- `text`
  - 役割: `topic`, `messageId`, `projectId` を扱う
  - 使い方: URL や識別子を組み立てる

最小コードイメージ:

```haskell
decodePubSubPush body =
  decodePushEnvelope body >>= decodeBase64Data >>= decodeCloudEvent
```

### 8.2 ライブラリの主な使い方

- `aeson`
  - push body は `eitherDecode body`、publish body は `encode publishRequest` で扱う
- `gogol`
  - production 用 publisher 初期化時に ADC から access token を取得する
- `http-client`
  - `parseRequest publishUrl` と `httpLbs request manager` で Pub/Sub REST API を呼ぶ
- `base64`
  - `message.data` は decode、publish payload は encode に使う
- `retry`
  - `withRetry defaultPolicy isRetryable (publishOnce ...)` の形で publish を包む
- `text`
  - `projects/{project}/topics/{topic}` の topic path を組み立てる

### 8.3 import 例

```haskell
import Data.Aeson (FromJSON, ToJSON, eitherDecode, encode)
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import Network.HTTP.Client (Manager, httpLbs, parseRequest)
```

補足:

- base64 の package に応じて module 名は多少変わる
- `httpLbs`, `parseRequest` は `http-client`
- emulator 分岐を入れるなら `System.Environment.lookupEnv` も使う

## 9. 実装ルール

- duplicate delivery は `Persistence.Idempotency` 側で吸収する
- `400` 系は ack、`500` 系は nack を標準方針とする
- base64 decode 失敗は常に non-retryable
- production では ADC から Bearer token を取得し、emulator (`PUBSUB_EMULATOR_HOST`) 利用時は auth を無効化する

## 10. テスト観点

- push body から CloudEvent が正しく復元できる
- base64 不正を reject できる
- publish request の topic path が正しい
- retryable error 時に再試行される

## 11. 実装ヒント

- 先に `decodePubSubPush` だけ実装し、publish は後から足す方が安全。
- production / emulator の分岐は `mkPublisherClient` 側で閉じ、`publishCloudEvent` の分岐を増やさない。
- Pub/Sub publish request body は小さいので、まずは `http-client` + `aeson` で素直に JSON を組み立てる実装で十分。

## 12. 初心者向け実装ロードマップ

### Step 1. push 受信だけ先に作る

- まず `src/Messaging/PubSub.hs` を作る
- `PubSubPushEnvelope` とその内側の `message` 用 record を定義する
- `message.data` を取り出して base64 decode する helper を作る

publish は後回しにする。

この step で追加するもの:

```haskell
data PubSubPushEnvelope = PubSubPushEnvelope
  { message :: PubSubPushMessage
  }
```

### Step 2. CloudEvent 復元までつなぐ

- base64 decode 後の bytes を `Messaging.CloudEvent.decodeCloudEvent` へ渡す
- ここで `CloudEvent` module と接続する

この step でやること:

1. `decodePushEnvelope`
2. `decodeBase64Data`
3. `decodePubSubPush`

最初の実装イメージ:

```haskell
decodePubSubPush body =
  decodePushEnvelope body >>= decodeBase64Data >>= decodeCloudEvent
```

### Step 3. 異常系の分類を決める

- JSON 不正
- base64 不正
- payload 不正

どれが retryable でどれが non-retryable かを明示する。

この step で追加するもの:

- `PubSubErrorJsonInvalid`
- `PubSubErrorBase64Invalid`
- `PubSubErrorPayloadInvalid`

### Step 4. publish 用の request body を作る

- CloudEvent JSON を bytes にする
- bytes を base64 化する
- Pub/Sub publish API の JSON を組み立てる

この step でやること:

1. `encodeCloudEvent`
2. base64 encode
3. publish request JSON record を作る

### Step 5. HTTP 呼び出しを追加する

- `http-client` で request を送る
- emulator と production の分岐は client 生成側に閉じる
- retry は `Resilience.Retry` に寄せる

最初の実装イメージ:

```haskell
publishCloudEvent publisher topic event = do
  request <- mkPublishRequest publisher topic event
  httpLbs request (publisherManager publisher)
```

### 完了条件

- push body から `CloudEvent payload` を復元できる
- publish request を正しい topic path へ送れる
- 失敗種別ごとに再試行方針を分けられる

最終チェック手順:

1. push body fixture を 1 つ作る
2. `decodePubSubPush` が通ることを確認する
3. publish request body に topic と base64 payload が入ることを確認する
