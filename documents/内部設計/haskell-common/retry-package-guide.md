# retry パッケージ 使い方ガイド

パッケージ: `retry` 0.9.3.1
モジュール: `Control.Retry`

## 1. 概要

`retry` は IO アクションの再試行を制御するライブラリ。2 つの利用パターンがある：

| パターン | 関数 | 失敗の表現 | 用途 |
|---------|------|-----------|------|
| **戻り値ベース** | `retrying` | `Either e a` や `Maybe a` | 例外を使わない設計 |
| **例外ベース** | `recovering` | `throwM` / `throwIO` | 例外で失敗を表現する設計 |

本プロジェクトでは **戻り値ベース（`retrying`）** を採用する。

## 2. 主要な型

### RetryPolicyM / RetryPolicy

```haskell
newtype RetryPolicyM m = RetryPolicyM
    { getRetryPolicyM :: RetryStatus -> m (Maybe Int) }

-- pure 版（モナド非依存）
type RetryPolicy = forall m. Monad m => RetryPolicyM m
```

- `RetryStatus` を受け取り、`Just delay`（delay マイクロ秒後に再試行）または `Nothing`（再試行停止）を返す
- **Monoid インスタンス** を持ち、`<>` で組み合わせ可能
  - どちらかが `Nothing` → 全体が `Nothing`（停止条件の AND）
  - 両方 `Just` → 大きい方の delay を採用

### RetryStatus

```haskell
data RetryStatus = RetryStatus
    { rsIterNumber     :: !Int       -- 試行番号（0 から開始）
    , rsCumulativeDelay :: !Int      -- これまでの累積遅延（マイクロ秒）
    , rsPreviousDelay  :: !(Maybe Int) -- 前回の遅延（初回は Nothing）
    }
```

## 3. ポリシー定義

### 基本ポリシー

```haskell
-- 固定遅延（無限リトライ）
constantDelay :: Int -> RetryPolicy
-- 例: constantDelay 50000  -- 50ms 固定

-- 指数バックオフ（無限リトライ）
-- delay = base * 2^attempt
exponentialBackoff :: Int -> RetryPolicy
-- 例: exponentialBackoff 100000  -- 100ms, 200ms, 400ms, 800ms, ...

-- 指数バックオフ + ジッター（無限リトライ、MonadIO 必要）
-- delay = base * 2^attempt / 2 + random(0, base * 2^attempt / 2)
fullJitterBackoff :: Int -> RetryPolicyM IO
-- 例: fullJitterBackoff 100000  -- ランダム要素あり

-- フィボナッチバックオフ（無限リトライ）
fibonacciBackoff :: Int -> RetryPolicy
-- 例: fibonacciBackoff 100000  -- 100ms, 100ms, 200ms, 300ms, 500ms, ...

-- 最大回数制限（遅延なし）
limitRetries :: Int -> RetryPolicy
-- 例: limitRetries 3  -- 最大 3 回再試行
```

> **注意**: `constantDelay`, `exponentialBackoff` 等は単体では無限リトライ。必ず `limitRetries` と組み合わせる。

### ポリシー変換

```haskell
-- 遅延の上限を設定
capDelay :: Int -> RetryPolicyM m -> RetryPolicyM m
-- 例: capDelay 5000000 (exponentialBackoff 100000)  -- 最大 5 秒

-- 1 回あたりの遅延が上限に達したら停止
limitRetriesByDelay :: Int -> RetryPolicyM m -> RetryPolicyM m

-- 累積遅延が上限に達したら停止
limitRetriesByCumulativeDelay :: Int -> RetryPolicyM m -> RetryPolicyM m
```

### 組み合わせ例

```haskell
-- 指数バックオフ、最大 3 回、delay 上限 5 秒
myPolicy :: RetryPolicy
myPolicy = exponentialBackoff 100000 <> limitRetries 3

-- 指数バックオフ + ジッター、最大 3 回、delay 上限 5 秒
myPolicyWithJitter :: RetryPolicyM IO
myPolicyWithJitter =
    capDelay 5000000 (fullJitterBackoff 100000) <> limitRetries 3

-- デフォルトポリシー（50ms 固定、最大 5 回）
retryPolicyDefault :: RetryPolicyM m
retryPolicyDefault = constantDelay 50000 <> limitRetries 5
```

## 4. 戻り値ベースの再試行（`retrying`）

### 型シグネチャ

```haskell
retrying
    :: MonadIO m
    => RetryPolicyM m
    -> (RetryStatus -> b -> m Bool)
    -- ^ リトライ判定。True を返すと再試行する
    -> (RetryStatus -> m b)
    -- ^ 実行するアクション
    -> m b
```

### 使用例: Either ベース

```haskell
import Control.Retry

data MyError = Timeout | NotFound deriving (Show)

-- リトライ対象かどうかの判定
isRetryable :: MyError -> Bool
isRetryable Timeout  = True   -- 一時障害 → リトライ
isRetryable NotFound = False  -- 恒久障害 → 即失敗

-- リトライ付きでアクションを実行
fetchWithRetry :: IO (Either MyError Value)
fetchWithRetry =
    retrying
        policy
        checkResult
        action
  where
    policy = exponentialBackoff 100000 <> limitRetries 3

    -- retrying の判定関数: True → リトライ, False → 停止
    checkResult _retryStatus result = pure $ case result of
        Left err -> isRetryable err
        Right _  -> False  -- 成功したらリトライしない

    -- 実行するアクション（RetryStatus は無視してよい）
    action _retryStatus = callExternalService
```

### 使用例: Maybe ベース

```haskell
import Data.Maybe (isNothing)

fetchWithRetry :: IO (Maybe Value)
fetchWithRetry =
    retrying
        (constantDelay 50000 <> limitRetries 5)
        (\_ result -> pure (isNothing result))
        (\_ -> callExternalService)
```

## 5. retryingDynamic: 遅延の動的上書き

HTTP の `Retry-After` ヘッダーなど、レスポンスに基づいて遅延を変更したい場合に使う。

```haskell
data RetryAction
    = DontRetry                       -- リトライしない
    | ConsultPolicy                   -- ポリシーに従う
    | ConsultPolicyOverrideDelay Int  -- ポリシーに従うが delay を上書き

retryingDynamic
    :: MonadIO m
    => RetryPolicyM m
    -> (RetryStatus -> b -> m RetryAction)
    -> (RetryStatus -> m b)
    -> m b
```

### 使用例

```haskell
fetchWithDynamicRetry :: IO (Either MyError Value)
fetchWithDynamicRetry =
    retryingDynamic
        (exponentialBackoff 100000 <> limitRetries 3)
        checkResult
        action
  where
    checkResult _ result = pure $ case result of
        Right _ -> DontRetry
        Left (RateLimited retryAfterSeconds) ->
            ConsultPolicyOverrideDelay (retryAfterSeconds * 1000000)
        Left Timeout -> ConsultPolicy
        Left NotFound -> DontRetry

    action _ = callExternalService
```

## 6. 例外ベースの再試行（`recovering`）

```haskell
recovering
    :: (MonadIO m, MonadMask m)
    => RetryPolicyM m
    -> [RetryStatus -> Handler m Bool]
    -- ^ 例外ハンドラのリスト。True → リトライ
    -> (RetryStatus -> m a)
    -> m a
```

### 使用例

```haskell
import Control.Exception (IOException)

fetchWithRecovery :: IO Value
fetchWithRecovery =
    recovering
        (exponentialBackoff 100000 <> limitRetries 3)
        (skipAsyncExceptions ++ [ioHandler])
        action
  where
    ioHandler _ = Handler $ \(_ :: IOException) -> pure True
    action _ = callExternalServiceThatThrows
```

> **`skipAsyncExceptions`**: `AsyncException` と `SomeAsyncException` をリトライしないハンドラ。`recovering` を使う際は必ず先頭に含める。

## 7. ポリシーのシミュレーション

開発時にポリシーの挙動を確認できる。

```haskell
-- GHCi で実行
>>> simulatePolicyPP 10 (exponentialBackoff 100000 <> limitRetries 3)
0: 100.0ms
1: 200.0ms
2: 400.0ms
3: Inhibit
4: Inhibit
...
Total cumulative delay would be: 700.0ms
```

## 8. 本プロジェクトでの使い方

設計書 `Resilience.Retry` の `withRetry` は `retrying` を薄くラップする形で実装する：

```haskell
-- 設計書のインターフェース
withRetry
    :: RetryPolicyConfig
    -> (e -> Bool)            -- retryable 判定
    -> IO (Either e a)        -- アクション
    -> IO (Either e a)

-- 実装イメージ
withRetry config isRetryable action =
    retrying
        (toRetryPolicy config)
        (\_ result -> pure $ case result of
            Left err -> isRetryable err
            Right _  -> False
        )
        (\_ -> action)
  where
    toRetryPolicy cfg =
        exponentialBackoff (baseDelayMicros cfg) <> limitRetries (maxRetries cfg)
```

## 9. 遅延の単位

全ての遅延値は **マイクロ秒** で指定する。

| 表記 | マイクロ秒 |
|------|-----------|
| 50ms | `50000` |
| 100ms | `100000` |
| 1s | `1000000` |
| 5s | `5000000` |
| 30s | `30000000` |

## 10. import 例

```haskell
import Control.Retry
    ( RetryPolicyM
    , RetryStatus (..)
    , exponentialBackoff
    , limitRetries
    , retrying
    )
```
