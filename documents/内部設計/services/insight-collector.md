# insight-collector 内部設計書

最終更新日: 2026-03-03
JSON対応: `内部設計/json/insight-collector.json`

## 1. サービス概要

- サービスID: `insight-collector`
- 役割: 定性データソースを収集し、根拠付きインサイトへ構造化する。
- AI責務: あり（要約・タグ付け）

## 2. 実行環境

| 項目 | 値 |
|---|---|
| Platform | Cloud Run Job |
| Language | Haskell |
| Exposure | private |

## 3. イベントIF

- Subscribe: `insight.collect.requested`
- Publish: `insight.collected`, `insight.collect.failed`

### 3.1 ペイロード契約（実装で参照する最小項目）

- `insight.collect.requested.payload`:
  `targetDate`, `requestedBy` は必須。`sourceTypes`, `options(forceRecollect,dryRun,maxItemsPerSource)` は任意。
- `insight.collected.payload`:
  `identifier`, `count`, `storagePath`, `sourceStatus[]` は必須。部分成功時は `partialFailure=true` を付与。
- `insight.collect.failed.payload`:
  `reasonCode` は必須。`sourceType`, `stage`, `detail` を可能な限り付与する。

## 4. 依存関係

- Firestore: `skill_registry`, `source_policies`, `insight_records`, `idempotency_keys`
- Cloud Storage: `insight_raw`, `insight_processed`
- External: X API v2, YouTube Data API v3, Paper/GitHub source API

## 5. 処理フロー

1. `insight.collect.requested` 受信
2. リクエスト検証（`targetDate`, `sourceTypes`, `options`）
3. 冪等性チェック（`identifier`）
4. 収集Skill解決
5. 許可ソース/利用規約検証（`source_policies`）
6. X/YouTube/Paper/GitHub 収集
7. 正規化・要約・根拠生成
8. `signalClass` / `soWhatScore` 算出
9. 保存（`insight_raw`, `insight_processed`, `insight_records`）
10. `sourceStatus` 集計付きで `insight.collected` 発行

## 6. 冪等性・リトライ

- 冪等性キー: `identifier`
- リトライ: 最大3回、指数バックオフ
- 再試行対象: `DEPENDENCY_TIMEOUT`, `DEPENDENCY_UNAVAILABLE`, `DATA_SOURCE_TIMEOUT`, `DATA_SOURCE_UNAVAILABLE`
- 非再試行: `COMPLIANCE_SOURCE_UNAPPROVED`, `REQUEST_VALIDATION_FAILED`, `DATA_SCHEMA_INVALID`

## 7. 品質ゲート

- `source_policies` 一致必須
- `sourceUrl` 欠損禁止
- `evidenceSnippet` 欠損禁止
- `signalClass` 欠損禁止
- `soWhatScore` は `0.0 <= score <= 1.0` を必須
- `evidenceSnippet` は200文字以上の冗長引用を禁止（短い根拠抜粋に限定）

## 8. SLO・監視

- 1ジョブ完了: 20分以内
- 根拠リンク付きレコード率: 99.0%以上
- `signalClass` / `soWhatScore` 付与率: 99.0%以上
- メトリクス: `insight_collect_success_total`, `insight_collect_failure_total`, `insight_missing_evidence_total`
- メトリクス: `insight_x_collected_total`, `insight_youtube_collected_total`, `insight_source_quota_exhausted_total`
- メトリクス: `insight_structural_anomaly_total`, `insight_event_noise_total`

## 9. 収集仕様（X / YouTube / Paper / GitHub）

### 9.1 共通ポリシー

- `targetDate` を JST の 00:00:00-23:59:59 で解釈し、API 呼び出し時に UTC へ変換する。
- `sourceTypes` 未指定時は `x`, `youtube`, `paper`, `github` のうち `enabled=true` なソースを対象とする。
- 収集対象は `source_policies` で `enabled=true` のソースのみ。
- `source_policies` 必須項目: `sourceType`, `enabled`, `termsVersion`, `redistributionAllowed`, `dailyQuota`, `sourceConfig`。
- `redistributionAllowed=false` のソースは収集しても保存・配信しない（`COMPLIANCE_SOURCE_UNAPPROVED`）。
- 重複排除キーは `sourceType + externalIdentifier`。
- 正規化必須項目: `sourceType`, `externalIdentifier`, `sourceUrl`, `collectedAt`, `summary`, `evidenceSnippet`, `skillVersion`。
- `signalClass` は `structural_anomaly` / `event_noise` の2値。
- `soWhatScore` は 0.0-1.0 で、`signalClass=structural_anomaly` 推奨閾値は `0.70` 以上。

`sourceConfig` のキー定義（確定）:

| sourceType | 必須キー | 任意キー |
|---|---|---|
| `x` | `x.accountHandles` | `x.keywordQuery`, `x.excludeKeywords`, `x.includeReplies`, `x.minEngagement`, `x.soWhatThreshold`, `x.scoringWeights` |
| `youtube` | `youtube.channelIdentifiers` | `youtube.keywordQuery`, `youtube.includeLive`, `youtube.includeComments`, `youtube.maxCommentsPerVideo`, `youtube.transcriptProvider`, `youtube.soWhatThreshold`, `youtube.scoringWeights` |
| `paper` | `paper.providers` | `paper.query`, `paper.maxItemsPerRun`, `paper.soWhatThreshold`, `paper.scoringWeights` |
| `github` | `github.repositories` | `github.includeReadme`, `github.includeReleases`, `github.maxItemsPerRun`, `github.soWhatThreshold`, `github.scoringWeights` |

### 9.2 X 収集仕様

#### 9.2.1 API と取得条件

| 項目 | 設定 |
|---|---|
| ベースURL | `https://api.x.com/2` |
| 認証 | `Authorization: Bearer <X_API_BEARER_TOKEN>` |
| 取得API | `GET /tweets/search/recent`, `GET /users/by` |
| 対象 | 許可済み監視アカウント（`source_policies` で管理） |
| 期間 | `targetDate` 1日分（UTC変換） |

`search/recent` クエリテンプレート:
- `(from:{account1} OR from:{account2}) ({keywordQuery}) -is:retweet -is:reply lang:ja`
- `start_time`, `end_time`, `max_results=100`, `next_token`
- `tweet.fields=created_at,lang,author_id,conversation_id,public_metrics`
- `expansions=author_id`, `user.fields=username,name,verified`

#### 9.2.2 フィルタと保存列

- 除外: リポスト、返信、`source_policies` 未登録アカウント。
- 最小エンゲージメント: `like_count + retweet_count + reply_count >= 3`（デフォルト）。
- 保存列: `tweetIdentifier`, `authorUsername`, `text`, `createdAt`, `metrics`, `lang`, `conversationIdentifier`。
- `sourceUrl`: `https://x.com/{authorUsername}/status/{tweetIdentifier}`。
- `evidenceSnippet`: URL除去後テキスト先頭280文字（改行圧縮）。

#### 9.2.3 クォータ/失敗制御

- 1実行の上限リクエスト数: `min(dailyQuota, 300)`。
- APIが429を返した場合は当該ソース収集を打ち切り、`DEPENDENCY_UNAVAILABLE`。

| 事象 | reasonCode | retryable |
|---|---|---|
| ポリシー未許可/規約未充足 | `COMPLIANCE_SOURCE_UNAPPROVED` | false |
| 認証失敗（401/403） | `AUTH_INVALID_CREDENTIALS` / `AUTH_FORBIDDEN` | false |
| タイムアウト | `DEPENDENCY_TIMEOUT` | true |
| 429/5xx/接続不可 | `DEPENDENCY_UNAVAILABLE` | true |
| スキーマ不整合 | `DATA_SCHEMA_INVALID` | false |

### 9.3 YouTube 収集仕様

#### 9.3.1 API と取得モード

| 項目 | 設定 |
|---|---|
| ベースURL | `https://www.googleapis.com/youtube/v3` |
| 認証 | `YOUTUBE_API_KEY` |
| 取得API | `GET /search`, `GET /videos`, `GET /commentThreads` |
| 対象 | 許可済みチャンネルID（`source_policies` で管理） |
| 期間 | `targetDate` 1日分（`publishedAfter`/`publishedBefore`） |

収集モード:
- ライブ探索: `search` に `eventType=live`, `type=video` を指定（市場時間帯向け）。
- 日次探索: `search` で当日公開動画を収集し、`videos` で統計を補完。
- コメント補完: `commentThreads` から上位コメントを最大20件取得。

#### 9.3.2 字幕（Transcript）方針

- YouTube Data API 単体では第三者動画の字幕本文取得を保証できないため、標準では字幕本文を必須にしない。
- `source_policies.sourceConfig.youtube.transcriptProvider=approved` の場合のみ、許可済み字幕プロバイダから補助取得を実行する。
- 許可済み字幕プロバイダ実装（固定）:
  `GET {TRANSCRIPT_PROXY_BASE_URL}/v1/transcripts/{videoIdentifier}?langs=ja,en`
  （認証: `x-api-key: ${TRANSCRIPT_PROXY_API_KEY}`、タイムアウト15秒、最大1回再試行）
- 字幕プロバイダ呼び出しが失敗しても収集全体は失敗させず、`description` / `topComments` フォールバックへ移行する。
- 字幕取得不可時は `description` または上位コメントから `evidenceSnippet` を生成して継続する。

#### 9.3.3 保存列と根拠生成

- 保存列: `videoIdentifier`, `channelIdentifier`, `title`, `description`, `publishedAt`, `liveBroadcastContent`, `statistics`, `topComments`。
- `sourceUrl`: `https://www.youtube.com/watch?v={videoIdentifier}`。
- `evidenceSnippet` 優先順:
1. 字幕セグメント（timestamp付き）
2. 説明文のキーワード一致文
3. 上位コメントのキーワード一致文

#### 9.3.4 クォータ/失敗制御

- 日次予算は `source_policies.dailyQuota` を使用（デフォルト運用値: 8,000 units）。
- 予算消費が90%到達で追加探索を停止し、取得済みデータで成功確定する。

| 事象 | reasonCode | retryable |
|---|---|---|
| ポリシー未許可/規約未充足 | `COMPLIANCE_SOURCE_UNAPPROVED` | false |
| APIキー不正（403） | `AUTH_INVALID_CREDENTIALS` | false |
| quotaExceeded（403） | `DEPENDENCY_UNAVAILABLE` | false |
| タイムアウト | `DEPENDENCY_TIMEOUT` | true |
| 5xx/接続不可 | `DEPENDENCY_UNAVAILABLE` | true |
| スキーマ不整合 | `DATA_SCHEMA_INVALID` | false |

### 9.4 出力正規化スキーマ（主要ソース共通）

| フィールド | 型 | 説明 |
|---|---|---|
| `identifier` | string | 収集実行識別子 |
| `sourceType` | enum(`x`,`youtube`,`paper`,`github`) | 収集元 |
| `externalIdentifier` | string | tweetIdentifier / videoIdentifier / paperIdentifier / repositoryIdentifier |
| `sourceUrl` | string | 根拠URL |
| `title` | string \| null | タイトル（Xはnull可、他ソースは取得可能時に設定） |
| `summary` | string | 要約本文 |
| `evidenceSnippet` | string | 根拠抜粋 |
| `signalClass` | enum(`structural_anomaly`,`event_noise`) | 構造性分類 |
| `soWhatScore` | number | 投資判断有用度スコア（0.0-1.0） |
| `collectedAt` | datetime | 収集時刻（UTC） |
| `metrics` | object | 反応指標（like/view/comment等） |
| `trace` | string | トレースID |

### 9.5 `So What` 判定仕様（確定）

- 目的: ノイズ由来のインサイトを下流で抑制し、構造的な仮説候補を優先する。
- 判定入力:
  - 根拠鮮度（`collectedAt` と `targetDate` の差）
  - 根拠性（一次情報/公式ソース比率）
  - 再現性（同趣旨の複数根拠有無）
  - 市場関連性（戦略ユニバース銘柄/テーマ一致）
- スコアリング:
  - `soWhatScore = weighted_sum(freshness, credibility, reproducibility, marketRelevance)`
  - 重みは `source_policies` の `sourceConfig` で将来調整可能とし、初期値は等重み（0.25）を採用。
- クラス分類:
  - `soWhatScore >= 0.70`: `structural_anomaly`
  - `soWhatScore < 0.70`: `event_noise`
- 失敗条件:
  - 入力特徴量が不足し `soWhatScore` 算出不可の場合は `DATA_SCHEMA_INVALID` として失敗させる。

## 10. 未確定事項（次議論）

- なし（現時点の実装着手に必要な項目は確定済み）。
