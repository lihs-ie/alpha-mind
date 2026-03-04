# insight-collector 収集元候補リスト（初期版）

最終更新日: 2026-03-03
対象サービス: `insight-collector`

## 1. 進め方（最初に固定）

- まず `高信頼の一次情報ソース` だけで v0.1 を開始する。
- 評価軸は以下6項目を 1-5 点で採点し、合計 24 点以上を初期採用目安とする。
  - 鮮度（更新頻度）
  - 関連性（日本株・投資判断に直結）
  - 根拠性（一次情報・公式性）
  - ノイズ率（低いほど高得点）
  - 運用性（API取得容易性・quota）
  - コンプライアンス（利用規約・再配布可否）
- 初期運用の採用件数（推奨）
  - X: 10アカウント
  - YouTube: 8チャンネル
  - 論文: 4ソース（API/RSS単位）
  - GitHub: 10リポジトリ

## 2. 初期候補（X）

| 候補 | 種別 | 主用途 | 初期評価 | 参考 |
|---|---|---|---:|---|
| `@JPX_official` | 取引所公式 | 市場制度・取引所発信の一次情報 | 29 | JPX公式SNS一覧 |
| `@jpx_JQuants` | データ基盤公式 | J-Quants仕様更新・障害/リリース情報 | 28 | JPX公式SNS一覧 |
| `@kabako_OSE` | デリバ系公式 | 先物/オプションの制度・教育情報 | 24 | JPX公式SNS一覧 |
| `@meti_NIPPON` | 省庁公式 | 政策・制度改定の早期把握 | 26 | METI公式SNS一覧 |
| `@keizaikaiseki` | 政府統計 | 指標公表・マクロ動向 | 25 | METI公式SNS一覧 |
| `@meti_saiene` | 政策（エネルギー） | 電力・資源セクター関連情報 | 23 | METI公式SNS一覧 |
| `@JETRO_info` | 公的機関 | 貿易・対外環境の変化把握 | 22 | METI公式SNS一覧 |

注記:
- 上記は `公的/公式` を優先した初期セット。
- メディア・個人アカウントは v0.2 で追加（ノイズ率と規約確認後）。

## 3. 初期候補（YouTube）

| 候補 | URL識別子 | 主用途 | 初期評価 | 備考 |
|---|---|---|---:|---|
| 日本取引所グループ公式チャンネル | `https://www.youtube.com/channel/UCnZA74T8a8dEbavWRq8F2nA` | 取引所公式解説・制度理解 | 27 | JPX公式発表から取得 |
| 東証IRムービー・スクエア | `https://www.youtube.com/user/tsesquare` | 決算説明・企業IR動画 | 30 | JPXページから取得 |
| 松井証券公式 | `https://www.youtube.com/user/MatsuiSecurities` | 個人投資家向け実践知見 | 24 | 松井証券プレスから取得 |
| METI channel | `https://www.youtube.com/user/metichannel` | 産業政策・制度背景 | 23 | METI公式SNSから取得 |
| metiGIchannel | `https://www.youtube.com/channel/UC6eH5HKEH9EhNl8wfTgnYrQ` | GX/脱炭素投資テーマ | 22 | METI公式SNSから取得 |
| RIETI channel | `https://www.youtube.com/user/rietichannel` | 経済研究・政策議論 | 22 | METI公式SNSから取得 |

注記:
- `sourceConfig.youtube.channelIdentifiers` には channel Identifier を保存する。
- `user/...` 形式の候補は初回オンボーディング時に YouTube Data API で channel ID に正規化する。

## 4. 初期候補（論文ソース）

| 候補 | 取得方式 | 主用途 | 初期評価 | 参考 |
|---|---|---|---:|---|
| arXiv | API (`export.arxiv.org`) | 最新手法の高速追跡 | 28 | arXiv API User Manual |
| arXiv `q-fin.*` | taxonomy指定 | 金融特化のノイズ低減 | 29 | arXiv Category Taxonomy |
| OpenAlex | REST API | 引用・関連文献の拡張探索 | 26 | OpenAlex API Overview |
| Crossref | REST API | DOIメタデータ・出版情報補完 | 25 | Crossref REST API |
| NBER Working Papers | Web + ニュースレター | 実証経済・政策系の補完 | 21 | NBER Working Papers |

推奨クエリ（初期）:
- arXiv: `cat:q-fin.PM OR cat:q-fin.ST OR cat:q-fin.TR OR cat:stat.ML`
- OpenAlex: `finance OR market microstructure OR portfolio optimization`（要 filter 固定）

## 5. 初期候補（GitHub）

| 候補 | 主用途 | 初期評価 | ライセンス/注意 |
|---|---|---:|---|
| `J-Quants/jquants-api-client-python` | 日本株データ連携の公式クライアント | 30 | Apache-2.0 |
| `microsoft/qlib` | 量的研究・特徴量/バックテスト基盤 | 27 | MIT |
| `AI4Finance-Foundation/FinRL` | RLベース戦略研究 | 23 | MIT（商標注意） |
| `polakowo/vectorbt` | 高速バックテスト・分析 | 24 | Apache-2.0 + Commons Clause |
| `mementum/backtrader` | イベント駆動バックテスト | 22 | OSS（リポジトリ確認） |
| `ranaroussi/yfinance` | 研究用データ取得補助 | 20 | Yahoo!利用規約の順守必須 |

運用ルール:
- `最終更新1年以上` かつ `Issue過多` のリポジトリは初期採用から除外。
- `再配布制限が強い` 場合は `source_policies.redistributionAllowed=false` を設定。

## 6. v0.1 で最初に採用する最小セット（推奨）

- X: `@JPX_official`, `@jpx_JQuants`, `@meti_NIPPON`, `@keizaikaiseki`
- YouTube: `UCnZA74T8a8dEbavWRq8F2nA`, `tsesquare(要ID正規化)`, `MatsuiSecurities(要ID正規化)`
- 論文: `arXiv(q-fin.* + stat.ML)`, `OpenAlex`
- GitHub: `J-Quants/jquants-api-client-python`, `microsoft/qlib`, `polakowo/vectorbt`

## 7. 参考（一次情報）

- JPX ソーシャルメディア: https://www.jpx.co.jp/corporate/news/social-media/index.html
- JPX YouTube開設情報: https://www.jpx.co.jp/corporate/news/news-releases/0060/20161229-01.html
- 東証IRムービー・スクエア: https://www.jpx.co.jp/listing/ir-clips/ir-movie/index.html
- METI 公式SNS一覧: https://www.meti.go.jp/sns/index.html
- METI X一覧: https://www.meti.go.jp/sns/sns_twitter.html
- METI YouTube一覧: https://www.meti.go.jp/sns/sns_youtube.html
- 松井証券（YouTube公式チャンネル記載）: https://www.matsui.co.jp/company/press/2025/pr250523.html
- arXiv API User Manual: https://info.arxiv.org/help/api/user-manual.html
- arXiv Category Taxonomy: https://arxiv.org/category_taxonomy
- OpenAlex API Overview: https://docs.openalex.org/how-to-use-the-api/api-overview
- Crossref REST API: https://www.crossref.org/documentation/retrieve-metadata/rest-api/
- NBER Working Papers: https://www.nber.org/papers
- GitHub `microsoft/qlib`: https://github.com/microsoft/qlib
- GitHub `J-Quants/jquants-api-client-python`: https://github.com/J-Quants/jquants-api-client-python
- GitHub `AI4Finance-Foundation/FinRL`: https://github.com/AI4Finance-Foundation/FinRL
- GitHub `polakowo/vectorbt`: https://github.com/polakowo/vectorbt
- GitHub `mementum/backtrader`: https://github.com/mementum/backtrader
- GitHub `ranaroussi/yfinance`: https://github.com/ranaroussi/yfinance

## 8. 初期投入データ（反映済み）

- Firestore emulator seed:
  `docker/scripts/seed-data.json`
- `source_policies` 反映済みドキュメントID:
  - `source_policy_x_core_v2026_03`
  - `source_policy_youtube_core_v2026_03`
  - `source_policy_paper_core_v2026_03`
  - `source_policy_github_core_v2026_03`
- `compliance_controls/trading.sourcePolicies` も同時に v0.1 セットへ更新済み。

残タスク:
- YouTube候補の `user/...` 形式（`tsesquare`, `MatsuiSecurities` など）を channel Identifier に正規化して `sourceConfig.youtube.channelIdentifiers` へ追加する。
