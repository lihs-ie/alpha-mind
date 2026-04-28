# Observability.Metrics 詳細設計

最終更新日: 2026-03-21

## 1. 目的

- Haskell サービス共通の Counter / Histogram を統一し、SLO 監視に必要なメトリクス基盤を提供する。

## 2. 責務

- registry 初期化
- counter / gauge / histogram 登録
- `service`, `result`, `reason_code` ラベルの標準化
- `/metrics` endpoint への expose

## 3. 公開型・関数

```haskell
data CommonMetrics = CommonMetrics
  { requestsTotal :: Vector Label1 Counter
  , processingDurationSeconds :: Vector Label2 Histogram
  , dependencyFailuresTotal :: Vector Label2 Counter
  }

initCommonMetrics :: Text -> IO CommonMetrics
observeProcessing :: CommonMetrics -> Text -> Text -> NominalDiffTime -> IO ()
```

## 4. 入力

- `serviceName`
- `result`
- `reasonCode`
- 処理時間

## 5. 出力

- Prometheus scrape 用 exposition text
- process 内 registry 更新

## 6. 処理内容

1. service 共通メトリクスを registry へ登録
2. request 単位で counter / histogram を更新
3. `App.Bootstrap` から `/metrics` を expose

## 7. 外部リソース

- Prometheus / Cloud Monitoring scrape

## 8. 使用ライブラリ

| パッケージ | バージョン | 用途 |
|---|---|---|
| `prometheus-client` | `1.1.1` | metrics registry / counter / histogram / vector label |
| `text` | `2.1.4` | label values |

**注意**: `prometheus` (bitnomial) パッケージではなく `prometheus-client` (fimad/prometheus-haskell) を使用する。`prometheus` 2.3.0 には `Vector` / `Label1` / `Label2` の型安全なラベル機構がなく、設計書§3 の型定義と合わない。

### 8.1 ライブラリの役割と使い方

- `prometheus-client`
  - 役割: counter, histogram, vector label, registry の管理
  - 使い方: process 起動時に metric を登録し、処理ごとに `withLabel` で値を更新する
- `text`
  - 役割: `result`, `reasonCode` などの label 値を表現する
  - 使い方: label 用文字列を `Text` に統一する

最小コードイメージ:

```haskell
observeProcessing metrics "success" "none" duration
```

### 8.2 ライブラリの主な使い方

- `prometheus-client`
  - 起動時に `register` で counter / histogram を登録し、リクエストごとに `withLabel` で観測値を更新する
- `text`
  - `result` や `reasonCode` の label 値を `Text` で扱う

### 8.3 import 例

```haskell
import Prometheus
  ( Counter
  , Histogram
  , Info (..)
  , Label1
  , Label2
  , Vector
  , counter
  , histogram
  , incCounter
  , observe
  , register
  , vector
  , withLabel
  )
```

補足:

- `prometheus-client` は `import Prometheus` の単一インポートで全型・関数が揃う
- `Label1` は `Text` の type alias、`Label2` は `(Text, Text)` の type alias

### 8.4 prometheus-client 詳細解説

#### 主要な型

| 型 | import 元 | 説明 |
|---|---|---|
| `Counter` | `Prometheus` | 単調増加する数値。リセットされない |
| `Histogram` | `Prometheus` | 値の分布を bucket に集計する |
| `Gauge` | `Prometheus` | 増減する現在値 |
| `Vector l m` | `Prometheus` | ラベル付きメトリクス。`l` はラベル型、`m` はメトリクス型 |
| `Label1` | `Prometheus` | `Text` の type alias。ラベル 1 個 |
| `Label2` | `Prometheus` | `(Text, Text)` の type alias。ラベル 2 個 |
| `Info` | `Prometheus` | メトリクスの名前と説明を持つレコード |
| `Metric m` | `Prometheus` | 未登録のメトリクス定義 |

`Label3` 〜 `Label9` もある（タプルの要素数に対応）。

#### メトリクス登録の流れ

```haskell
-- 1. メトリクス定義を作る（まだ登録されていない）
--    counter :: Info -> Metric Counter
--    histogram :: Info -> [Double] -> Metric Histogram
--    vector :: Label l => l -> Metric m -> Metric (Vector l m)

-- 2. register で global registry に登録する
--    register :: Metric m -> IO m
```

実装例:

```haskell
-- ラベルなし Counter
myCounter <- register $ counter (Info "my_counter" "説明")

-- ラベル 1 個の Counter（Label1 = Text）
requestsTotal <- register $ vector "result" $ counter (Info "requests_total" "リクエスト数")

-- ラベル 2 個の Histogram（Label2 = (Text, Text)）
duration <- register $ vector ("result", "reason_code")
  $ histogram (Info "processing_duration_seconds" "処理時間")
              [0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
```

`vector` の第 1 引数はラベル名。`Label1` なら `Text`、`Label2` なら `(Text, Text)` のタプルで渡す。

#### メトリクス更新

```haskell
-- ラベルなし
incCounter myCounter

-- ラベル付き: withLabel でラベル値を指定してから操作
withLabel requestsTotal "success" incCounter
withLabel duration ("success", "none") (observe 0.042)
```

`withLabel` のシグネチャ:

```haskell
withLabel :: (Label label, MonadMonitor m) => Vector label metric -> label -> (metric -> IO ()) -> m ()
```

1. 対象の Vector メトリクス
2. ラベル値（`Label1` なら `Text`、`Label2` なら `(Text, Text)`）
3. メトリクスへの操作関数（`incCounter`, `observe 値` など）

#### Exposition（scrape 用テキスト出力）

```haskell
import Prometheus.Metric.GHC (ghcMetrics)  -- オプション: GHC ランタイムメトリクス
import Prometheus (exportMetricsAsText)

-- global registry からテキスト形式で出力
expositionText <- exportMetricsAsText
-- expositionText :: ByteString（Prometheus text format）
```

`App.Bootstrap` の `/metrics` endpoint から `exportMetricsAsText` を呼んでレスポンスとして返す。

#### ユースケースまとめ

| メトリクス | ユースケース | 操作 |
|---|---|---|
| `Counter` | リクエスト数、エラー数 | `incCounter`（+1）, `addCounter n`（+n） |
| `Histogram` | 処理時間、レスポンス時間 | `observe value`（bucket に記録） |
| `Gauge` | 接続数、キューサイズ | `setGauge n`, `incGauge`, `decGauge` |

## 9. 実装ルール

- metric 名はスネークケース
- ラベル cardinality を増やしすぎない
- `identifier` を label に入れない

## 10. テスト観点

- 重複登録を防げる
- histogram 観測値が出力へ反映される
- exposition endpoint が正常応答する

## 11. 実装ヒント

- 初期実装は counter 2 本、histogram 1 本だけで十分。
- metrics 名は module 内の定数に寄せ、各サービスで文字列を組み立てない。
- `service` を label に入れるか prefix に入れるかは早めに固定する。初期実装では prefix より固定 label の方が扱いやすい。

## 12. 初心者向け実装ロードマップ

### Step 1. 最小の metrics 集合を決める

- まず `src/Observability/Metrics.hs` を作る
- request counter 1 本、failure counter 1 本、duration histogram 1 本の 3 つに絞る
- 名前も最初に固定する

最初から種類を増やしすぎない。

### Step 2. `CommonMetrics` record を作る

- metric handle を record にまとめる
- 各 service が個別に `register` しないようにする

この step で追加するもの:

```haskell
data CommonMetrics = CommonMetrics
  { requestsTotal :: Vector Label1 Counter
  , dependencyFailuresTotal :: Vector Label2 Counter
  , processingDurationSeconds :: Vector Label2 Histogram
  }
```

### Step 3. `initCommonMetrics` を作る

- `initCommonMetrics :: Text -> IO CommonMetrics` を書く
- `register` をこの関数に集約する
- metric 名は文字列リテラルを散らさず定数に寄せる

最初の実装イメージ:

```haskell
initCommonMetrics :: Text -> IO CommonMetrics
initCommonMetrics serviceName = do
  reqTotal <- register $ vector "result"
    $ counter (Info (serviceName <> "_requests_total") "Total requests")
  depFailures <- register $ vector ("dependency", "reason_code")
    $ counter (Info (serviceName <> "_dependency_failures_total") "Dependency failures")
  procDuration <- register $ vector ("result", "reason_code")
    $ histogram (Info (serviceName <> "_processing_duration_seconds") "Processing duration")
                defaultBuckets
  pure CommonMetrics
    { requestsTotal = reqTotal
    , dependencyFailuresTotal = depFailures
    , processingDurationSeconds = procDuration
    }
```

`defaultBuckets` は `Prometheus` から提供される標準的なバケット境界値。

### Step 4. 更新 helper を作る

- `observeProcessing`
- failure counter 更新 helper

この step でやること:

1. success / failure を受け取る helper を作る
2. duration を histogram に観測する helper を作る
3. 呼び出し側が low-level API に触れないようにする

最初の実装イメージ:

```haskell
observeProcessing :: CommonMetrics -> Text -> Text -> NominalDiffTime -> IO ()
observeProcessing metrics result reasonCode duration = do
  withLabel (requestsTotal metrics) result incCounter
  withLabel (processingDurationSeconds metrics) (result, reasonCode)
    (observe (realToFrac duration))

recordDependencyFailure :: CommonMetrics -> Text -> Text -> IO ()
recordDependencyFailure metrics dependency reasonCode =
  withLabel (dependencyFailuresTotal metrics) (dependency, reasonCode) incCounter
```

### Step 5. `/metrics` 連携を確認する

- `App.Bootstrap` から export text を返せる前提にする
- この module 単体では exposition text を返す helper まで作れば十分
- endpoint 追加は Bootstrap 側に任せる

最初の実装イメージ:

```haskell
import Prometheus (exportMetricsAsText)

-- Servant ハンドラや Wai アプリから呼ぶ
getMetrics :: IO ByteString
getMetrics = exportMetricsAsText
```

### 完了条件

- metric を登録できる
- request ごとに counter / histogram を更新できる
- exposition text が取得できる

最終チェック手順:

1. `shared.cabal` の `build-depends` を `prometheus` → `prometheus-client ^>=1.1.1` に変更する
2. `cabal build` を実行する
3. helper を 1 回呼んで counter が増えることを確認する
4. exposition text に metric 名が含まれることを確認する
