# data-collector 内部設計書

最終更新日: 2026-03-03
JSON対応: `内部設計/json/data-collector.json`

## 1. サービス概要

- サービスID: `data-collector`
- 役割: 市場データを取得し、正規化して保存し、後続処理イベントを発行する。
- AI責務: なし

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run Job |
| Language | Haskell |
| Exposure | private |

## 3. イベントIF

- Subscribe: `market.collect.requested`
- Publish: `market.collected`, `market.collect.failed`

## 4. 依存関係

- Cloud Storage: `raw_market_data`
- Firestore: `idempotency_keys`
- External: J-Quants API, Alpaca Market Data API, 日商金Web, Secret Manager

## 5. 処理フロー

1. `market.collect.requested` 受信
2. 冪等性チェック
3. 日米データ取得
4. 日商金データ取得（逆日歩CSV）
5. 調整係数再計算・スキーマ正規化・逆日歩クレンジング
6. Cloud Storage保存
7. `market.collected` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- 再試行対象: `DATA_SOURCE_TIMEOUT`, `DATA_SOURCE_UNAVAILABLE`, `DEPENDENCY_TIMEOUT`
- 非再試行: `REQUEST_VALIDATION_FAILED`, `DATA_SCHEMA_INVALID`

## 7. SLO・監視

- 1ジョブ完了: 10分以内
- 成功率: 99.0%
- メトリクス: `collect_success_total`, `collect_failure_total`, `source_latency_ms`
- メトリクス: `collect_success_total`, `collect_failure_total`, `source_latency_ms`, `nisshokin_fetch_success_total`

## 8. 収集仕様（ソース別・議論用ドラフト）

### 8.1 収集方針

- `market.collect.requested.payload.targetDate` を収集対象日として扱う。
- ソース別に `raw` 保存後、共通スキーマへ正規化して `market.collected` を発行する。
- ソースごとの失敗は `reasonCode` に正規化し、非再試行エラーは即時 `market.collect.failed` を発行する。

### 8.2 ソース別収集設計

| ソース | 取得方式 | 主な取得対象 | 認証情報 | 実行時刻（JST） | タイムアウト | 失敗時方針 |
|---|---|---|---|---|---|---|
| J-Quants | REST API（`/listed/info`, `/prices/daily_quotes`） | 日本株の日次価格、銘柄メタデータ | Secret ManagerのAPI資格情報（Bearer） | 17:30（取引日） | 30秒/req | 3回再試行、最終失敗で `DATA_SOURCE_UNAVAILABLE` |
| Alpaca Market Data | REST API | 米国株の日次価格（MVPでは収集無効） | Secret ManagerのAPI資格情報 | 07:00（翌営業日） | 30秒/req | 3回再試行、最終失敗で `DATA_SOURCE_TIMEOUT`/`DATA_SOURCE_UNAVAILABLE` |
| 日商金（逆日歩） | URL直接CSV取得 + ブラウザ自動化フォールバック | 品貸料（逆日歩）CSV | 認証不要（取得失敗に備えてURL監視） | 18:00（取引日） | 60秒/req | URL直接2回連続失敗でブラウザ自動化へ切替。最終失敗は `DATA_SOURCE_UNAVAILABLE` |

注記:
- 日商金はUI変更に弱いため、取得処理は「URL直接取得を第一優先」「失敗時のみブラウザ自動操作」を採用する。
- Alpacaは米国市場クローズ後データが安定する時刻で収集し、`targetDate` へJST基準で正規化する。

### 8.2.1 J-Quants 取得詳細（確定）

| 区分 | 設定値 |
|---|---|
| ベースURL（推奨） | `https://api.jquants-pro.com/v2` |
| ベースURL（互換） | `https://api.jquants.com/v1`（旧仕様。移行対象） |
| 認証 | `Authorization: Bearer <idToken>` |
| 取得API 1 | `GET /listed/info` |
| 取得API 2 | `GET /prices/daily_quotes` |

`GET /listed/info` の採用クエリ:
- `date`（対象日）
- `code`（指定時のみ）

`GET /prices/daily_quotes` の採用クエリ:
- `date`（全銘柄の対象日取得）
- `code`（銘柄指定時）
- `from`, `to`（期間指定時）
- `pagination_key`（ページング継続時）

J-Quantsで収集して正規化へ渡す列:
- `Date`, `Code`
- `Open`, `High`, `Low`, `Close`, `Volume`, `TurnoverValue`
- `AdjustmentFactor`, `AdjustmentOpen`, `AdjustmentHigh`, `AdjustmentLow`, `AdjustmentClose`, `AdjustmentVolume`
- `MarketCode`, `MarketCodeName`, `Sector17Code`, `Sector33Code`, `ScaleCategory`, `MarginCode`

### 8.2.1.1 J-Quants 調整済み価格再計算（確定）

目的:
- 株式分割・併合を跨いでも、最新時点の価格単位へ統一した時系列を生成する。
- look-ahead bias を回避し、過去時点で利用可能な情報のみで調整する。

手順（銘柄単位）:
1. `Date` 降順（最新 -> 過去）で並べる。
2. `AdjustmentFactor` から累積係数 `cumFactor` を降順で計算する（backward-looking cumulative product）。
3. `cumFactor` を `shift(1)` し、欠損は `1.0` で補完する。
4. 価格列（`Open/High/Low/Close`）に `cumFactor` を乗算する。
5. 出来高列（`Volume`）は `cumFactor` で除算する。
6. 監査用に生値（raw）列を保持したうえで、調整済み列を正本として保存する。

注意:
- `AdjustmentFactor <= 0` または欠損行は `DATA_SCHEMA_INVALID` として扱い、当該銘柄の正規化を失敗させる。
- `AdjustmentOpen/High/Low/Close/Volume` が取得できる場合も、運用標準は上記再計算結果を優先する。

### 8.2.2 Alpaca 取得詳細（確定）

| 区分 | 設定値 |
|---|---|
| ベースURL | `https://data.alpaca.markets/v2` |
| 認証 | `APCA-API-KEY-ID`, `APCA-API-SECRET-KEY` ヘッダ |
| 取得API | `GET /stocks/bars` |
| ページング | `next_page_token` |

`GET /stocks/bars` の採用クエリ:
- `symbols`（カンマ区切り）
- `timeframe=1Day`
- `start`, `end`
- `feed`（`iex`/`sip`）
- `limit`
- `next_page_token`

Alpacaで収集して正規化へ渡す列:
- `t`（timestamp）
- `o`, `h`, `l`, `c`, `v`
- `n`, `vw`（取得可能時）

### 8.2.3 日商金取得詳細（確定）

| 項目 | 設定値 |
|---|---|
| 第一取得方式 | URL直接CSV取得 |
| フォールバック方式 | ブラウザ自動操作（期間指定 -> CSVダウンロード） |
| 切替閾値 | URL直接取得が **2回連続失敗** した時点で切替 |
| 最大試行回数 | 合計3回（URL直接2回 + ブラウザ1回） |
| 成功判定 | CSV取得成功かつ必須列（銘柄コード、対象日、品貸料）が存在 |
| 失敗判定 | 3回失敗で `DATA_SOURCE_UNAVAILABLE`、CSV列不整合は `DATA_SCHEMA_INVALID` |

運用ルール:
- ブラウザ自動化の起動時は監査ログに `reason=browser_fallback` を記録する。
- URL直接取得成功時はブラウザ自動化を実行しない。
- ブラウザ自動化失敗が3営業日連続した場合、Runbook `RB-OPS-001` に従い手動介入する。

### 8.3 収集ユニバース

| 項目 | 方針 |
|---|---|
| 日本株対象 | `settings/strategy.symbols` で指定した銘柄リスト（MVPは `market=JP` 固定） |
| 米国株対象 | 研究用シャドー収集のみ。MVPの売買ユニバースには含めない（デフォルト空） |
| 逆日歩対象 | 日本株対象と同一銘柄集合 |
| 管理場所 | Firestore `settings/strategy` で管理し、`targetDate` 実行時点の版をスナップショット保存 |

### 8.3.1 初期ユニバース（v1.0 確定）

MVP方針:
- 売買対象はJPのみ（`StrategySettings.market=JP`）。
- 初期値は流動性の高いETF中心で開始し、個別株は運用者が `settings/strategy` で段階追加する。
- Alpacaは将来拡張用に実装を保持するが、MVP運用では収集ジョブを無効（`usCollectionEnabled=false`）とする。

初期設定値（`settings/strategy.symbols` の初期値）:

| 市場 | symbols | 意図 |
|---|---|---|
| JP | `1306.T`, `1321.T`, `1348.T`, `1475.T`, `2558.T` | 指数連動ETFでスプレッド・出来高・運用安定性を優先 |

運用ルール:
- 初期5銘柄から開始し、週次レビューで最大20銘柄まで段階拡張。
- 追加銘柄は `compliance/controls` の制限銘柄・ブラックアウトと同時確認して反映する。
- 逆日歩結合はJP対象全銘柄で必須とする。

### 8.4 正規化スキーマ（内部）

| フィールド | 型 | 説明 |
|---|---|---|
| `identifier` | string | 入力イベント識別子 |
| `targetDate` | date | 収集対象日（JST基準） |
| `symbol` | string | 銘柄コード |
| `market` | enum(`JP`,`US`) | 市場区分 |
| `open`,`high`,`low`,`close` | number | 調整済み日次価格（最新基準） |
| `volume` | number | 調整済み出来高（最新基準） |
| `openRaw`,`highRaw`,`lowRaw`,`closeRaw` | number | API取得の生価格（監査用） |
| `volumeRaw` | number | API取得の生出来高（監査用） |
| `adjustmentCumFactor` | number | 当該行に適用した累積調整係数 |
| `adjustmentBaseDate` | date | 係数基準日（通常は `targetDate`） |
| `reverseLoanFee` | number \| null | 逆日歩（JPのみ） |
| `source` | enum(`jquants`,`alpaca`,`nisshokin`) | データソース |
| `collectedAt` | datetime | 収集時刻（UTC） |
| `trace` | string | トレースID |

### 8.5 保存先設計

| 区分 | パス規約 | 形式 | 用途 |
|---|---|---|---|
| Raw（J-Quants） | `raw_market_data/jquants/date={targetDate}/part-*.json` | JSON | 再処理・監査 |
| Raw（Alpaca） | `raw_market_data/alpaca/date={targetDate}/part-*.json` | JSON | 再処理・監査 |
| Raw（日商金） | `raw_market_data/nisshokin/date={targetDate}/source.csv` | CSV | 再処理・監査 |
| Normalized | `normalized_market_data/date={targetDate}/market_snapshot.parquet` | Parquet | 下流連携（調整済み正本 + 生値監査列） |

### 8.6 処理シーケンス（詳細）

1. `market.collect.requested` 受信、`identifier` の冪等性チェック。
2. 対象ユニバース（日本株/米国株）を取得し、収集ジョブをソース別に生成。
3. J-Quants/Alpaca/日商金を並列収集（ソース内並列数は上限付き）。
4. Raw保存後にスキーマ検証（必須列、数値範囲、重複行）を実施。
5. J-Quants は調整係数再計算（逆順cumprod + shift）を実施。
6. 正規化・逆日歩結合（`symbol`,`targetDate` で内部結合）を実施。
7. 正規化データをParquet保存し、`market.collected` を発行。
8. 途中失敗時は `market.collect.failed` を発行し、監査ログへ保存。

### 8.7 reasonCode マッピング

| 事象 | reasonCode | retryable |
|---|---|---|
| APIタイムアウト | `DATA_SOURCE_TIMEOUT` | true |
| API 5xx / 接続不可 | `DATA_SOURCE_UNAVAILABLE` | true |
| 依存サービス遅延 | `DEPENDENCY_TIMEOUT` | true |
| 入力イベント不正 | `REQUEST_VALIDATION_FAILED` | false |
| CSV/JSONスキーマ不整合 | `DATA_SCHEMA_INVALID` | false |
| 同一イベント重複 | `IDEMPOTENCY_DUPLICATE_EVENT` | false |

### 8.8 未確定事項（次議論）

- なし（現時点の主要論点は確定済み）。
