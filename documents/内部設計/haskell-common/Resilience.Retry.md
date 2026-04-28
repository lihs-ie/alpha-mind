# Resilience.Retry 詳細設計

最終更新日: 2026-03-07

## 1. 目的

- 一時障害に対する指数バックオフ再試行を共通化し、全 Haskell サービスで再試行方針を揃える。

## 2. 責務

- retry policy 定義
- retryable / non-retryable 判定
- retry 回数超過時のエラー返却

## 3. 公開型・関数

```haskell
data RetryPolicyConfig = RetryPolicyConfig
  { maxRetries :: Int
  , baseDelayMicros :: Int
  }

withRetry
  :: RetryPolicyConfig
  -> (e -> Bool)
  -> IO (Either e a)
  -> IO (Either e a)
```

## 4. 入力

- retry policy
- retryable 判定関数
- I/O action

## 5. 出力

- 最終成功値
- 再試行後も失敗した最終エラー

## 6. 処理内容

1. action 実行
2. `Left e` かつ retryable なら待機
3. `baseDelay * 2^attempt` で backoff
4. 最大回数超過で失敗返却

## 7. 外部リソース

- なし

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `retry` | `0.9.3.1` | backoff policy |
| `text` | `2.1.4` | log message |

### 8.1 ライブラリの役割と使い方

- `retry`
  - 役割: backoff 付き再試行制御
  - 使い方: `withRetry` の内部で `retrying` か `recovering` を包む
- `text`
  - 役割: retry ログや reason の表現
  - 使い方: attempt 情報や失敗理由の文字列に使う

最小コードイメージ:

```haskell
withRetry defaultPolicy isRetryable action
```

### 8.2 ライブラリの主な使い方

- `retry`
  - `retrying` または `recovering` を `withRetry` の内部に閉じ込める
  - 呼び出し側は `IO (Either e a)` と `e -> Bool` だけ渡す
- `text`
  - retry の attempt や failure reason をログへ出すときの文字列に使う

### 8.3 import 例

```haskell
import Control.Retry
  ( RetryPolicyM
  , constantDelay
  , limitRetries
  , retrying
  )
import Data.Text (Text)
```

補足:

- `retrying` を使うか `recovering` を使うかは実装方針に合わせて選ぶ
- 初期実装では `limitRetries <> constantDelay` の組み合わせで十分

## 9. 実装ルール

- デフォルトは最大3回
- jitter は初期実装では不要
- non-retryable を誤って再試行しないことを優先

## 10. テスト観点

- 成功時に即 return する
- retryable error で再試行する
- 非 retryable error で即停止する

## 11. 実装ヒント

- `retry` package の `recovering` か `retrying` をそのまま薄く包むだけでよい。
- `RetryPolicyConfig` は最初から env 化せず、module 内デフォルト値を持たせておくと実装が軽い。
- retryable 判定は `Exception` instance に寄せず、明示関数で渡す方が業務ごとの差分を吸収しやすい。

## 12. 初心者向け実装ロードマップ

### Step 1. 設定 record を作る

- `maxRetries`
- `baseDelayMicros`

まずは 2 項目だけで十分。

この step で作る file:

- `src/Resilience/Retry.hs`

この step で追加するもの:

```haskell
data RetryPolicyConfig = RetryPolicyConfig
  { maxRetries :: Int
  , baseDelayMicros :: Int
  }
```

### Step 2. `IO (Either e a)` を包む形に固定する

- 例外より `Either` の方が挙動を追いやすい
- retryable 判定も `e -> Bool` で受ける

この step で関数シグネチャを書く:

```haskell
withRetry
  :: RetryPolicyConfig
  -> (e -> Bool)
  -> IO (Either e a)
  -> IO (Either e a)
```

### Step 3. 1 回実行して失敗時だけ retry する流れを作る

- 成功なら即 return
- retryable なら待機して再試行
- non-retryable なら即 return

最初は手書き再帰でもよい:

```haskell
go attempt = do
  result <- action
  case result of
    Right value -> pure (Right value)
    Left err -> ...
```

### Step 4. `retry` package に置き換える

- 手書きの再帰で理解してもよい
- 動きが分かったら `retrying` / `recovering` に寄せる

この step でやること:

1. 手書き版で期待動作を確認する
2. `retry` package 実装へ置き換える
3. テストが変わらず通ることを確認する

### 完了条件

- retryable error だけ再試行される
- 最大回数を超えたら最後の失敗を返す
- non-retryable error は即停止する

最終チェック手順:

1. 1 回で成功する action
2. 2 回失敗して 3 回目で成功する action
3. non-retryable error で即終了する action
