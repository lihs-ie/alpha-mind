# AI投資運用アプリ 要件定義（議論整理版）

最終更新日: 2026-02-28  
対象読者: 個人開発者（想定ユーザー数 1）

## 1. 背景

- 本アプリは「投資運用をAIに委任する」ことを目標とする。
- ただし研究・実証では、過去データ学習のみで長期的に市場平均を安定超過する確率は高くない。
- そのため要件は、モデル性能だけでなく、検証設計・コスト管理・リスク管理を主軸に設計する。

## 2. 目的

- 低コストで運用可能なAI投資運用アプリのMVPを構築する。
- 研究結果に整合する形で、過学習・コスト・レジーム変化に耐える運用基盤を実装する。
- 当面は単一ユーザー（自分用）での実運用を対象とする。

## 3. 非目的

- 短期間での高収益保証。
- 複数市場を同時に扱う複雑なグローバル運用。
- 初期段階でのB2B提供・第三者配信（ライセンス/規制コストが高い）。

## 4. 研究結果に基づく前提

### 4.1 勝率が低下しやすい主因

- 手数料・売買コストが超過収益を侵食する。
- 多重検定/データマイニングによりバックテスト過大評価が発生する。
- シグナルは公表後・実装後に劣化しやすい。
- 市場レジーム変化により、過去の優位性が持続しない。

### 4.2 解決方針（完全解決ではなく緩和）

- Walk-forwardを中心とした厳格なOOS検証を必須化する。
- コスト込み評価（手数料・スリッページ・インパクト）を標準化する。
- DSR/PBO等で過剰適合リスクを定量化する。
- 低回転戦略を優先し、取引回数を抑制する。

## 5. 対象市場要件

### 5.1 市場選定方針（初期）

- 初期は市場を絞る（要件）: 1市場先行。
- 採用方針: **売買対象は日本株、シグナルは日本+米国情報を利用**。
- 根拠1: 日米比較では、米国単独より他国（日本含む）側で予測有効性が確認される研究がある。
- 根拠2: 米国情報が日本市場予測に有効とする研究がある。

### 5.2 データ利用上の制約

- データ利用規約を要確認（特にJ-Quantsの私的利用制限）。
- 将来の公開提供を見据える場合は、再配布可否・商用可否を契約上で明文化する。

## 6. システム要件（MVP）

### 6.1 構成（低コスト優先）

- 実行基盤: Cloud Run（API/バッチ）
- スケジューラ: Cloud Scheduler
- 永続データ: 取引状態・設定・ログはFirestore、履歴データ/特徴量スナップショットはCloud Storage（Parquet）。
- データソース（初期案）: 米国はAlpaca Basic（無料枠を優先）、日本はJ-Quants（規約順守）。

### 6.2 DB方針

- 想定ユーザー1人のため、Firestoreを第一候補とする。
- 理由1: 固定費がほぼ不要（無料枠あり）。
- 理由2: Supabase Proの固定費（約25 USD/月）を回避可能。
- 注意点: Listenerや非効率クエリでRead課金が膨らむため、アクセスパターンを設計段階で最適化する。

## 7. コスト要件（概算）

### 7.1 月額目安（1ユーザー、低頻度運用）

- Firestore: 0〜数USD/月想定（無料枠中心）
- Cloud Run + Scheduler + Storage: 0〜20 USD/月程度
- 市場データ: 0〜22 USD/月（無料〜低価格プラン前提）
- 合計: **概ね 30〜60 USD/月以内を目標**

注記:
- リアルタイム高品質データや高頻度運用に移行すると100 USD/月超の可能性が高い。
- 規制手数料や取引コストは別途発生する。

## 8. 機能要件

- 日次または週次でシグナル生成を実行する。
- シグナルに基づく売買候補を生成する。
- 発注前リスクチェックを必須化する（ポジション上限、損失上限、銘柄上限）。
- 取引・判断根拠・モデル版を監査ログとして保存する。
- 緊急停止（kill switch）を提供する。
- 定性分析用エージェントを実装し、X/YouTube/論文/GitHub由来の知見を構造化して保存する。
- Claude Code Skill（取得・抽出・検証・記録）をコード資産として登録・再実行可能にする。
- 仮説を `draft -> backtested -> demo -> live/rejected` で管理する仮説ポートフォリオを提供する。
- バックテスト失敗を含む検証履歴を「失敗知見DB」として蓄積し、次回探索に再利用する。
- 昇格は「手動昇格」を基本としつつ、ETFかつ低インサイダーリスク条件を満たす場合のみ条件付き自動昇格を許可する。

## 9. 非機能要件

- 再現性: 学習データ期間、特徴量、モデルバージョンをすべて追跡可能。
- 安全性: 手動停止フローは常に残し、昇格は「手動」または「条件付き自動」のみを許可する（無条件自動は禁止）。
- 可用性: バッチ失敗時のリトライと通知。
- 拡張性: 市場追加時にデータアダプタを差し替え可能な構造。
- 資産性: Skill定義、指示書、仮説、失敗知見を永続管理し、使い捨て分析を禁止する。
- 一貫性: Markdown指示書（投資哲学・禁止事項・評価軸）をプロトコル化し、AI出力のぶれを抑制する。
- 効率性: 頻出計算は事前計算し、トークン消費と非決定的計算エラーを低減する。

## 10. 検証要件（研究整合）

- 検証分割: 学習/検証/テスト + Walk-forward。
- 評価指標: コスト控除後リターン、最大ドローダウン、Sharpe/Sortino、売買回転率。
- 過剰適合評価: DSR（Deflated Sharpe Ratio）、PBO（Probability of Backtest Overfitting）。
- 合格基準: ベンチマーク比だけでなく、コスト控除後・リスク調整後で判定する。

### 10.1 AI戦略探索の運用要件

- 戦略案の生成は「人間が仮説を定義し、AIが深掘り・大量検証する」方式を原則とする。
- 禁止リストを拡張し続ける探索方式は、近傍アイデア反復のリスクがあるため主手段にしない。
- 評価ループは `戦略生成 -> バックテスト -> 結果フィードバック -> 改善` を標準化する。
- 評価関数には、手数料・スリッページ・約定現実性（流動性制約）を必須で含める。
- AI提案戦略は、Walk-forward/DSR/PBO を通過しない限り本番利用不可とする。
- 直近期間での性能劣化（Sharpe低下、コスト比率上昇）を監視し、閾値超過時は昇格停止とする。

### 10.2 AI提案戦略のコンプライアンス要件

- AI提案の注文ロジックは、人手レビューで不公正取引リスク（見せ玉等）を確認する。
- 高頻度・板依存ロジックは、実運用前に法令・取引所ルール適合性チェックを実施する。
- コンプライアンス懸念が解消されるまで、当該戦略は `candidate` のまま保持する。

### 10.3 インサイダー接触回避の技術要件

- データ取り込みは「公開済み情報の許可ソース」のみを許可し、未承認ソースは処理を拒否する。
- 発注判断に関わる手動入力は自由記述を禁止し、事前定義コード + 短文コメント（長さ制限）に限定する。
- コメントはMNPI（未公表の重要事実）疑義検知フィルタを通し、疑義時は保存/実行を拒否する。
- 制限銘柄（restricted symbols）とブラックアウト期間を機械判定し、該当注文は常に拒否する。
- コンプライアンス未レビュー状態（`requiresComplianceReview=true`）のモデルは昇格不可とする。
- これらの拒否は `reasonCode` で監査可能にし、運用Runbookに連動させる。
- 昇格時は、`MNPIを知らない` 自己申告を監査ログに必須記録する。
- 取引先・案件関連銘柄を `partnerRestrictedSymbols` として管理し、該当銘柄の自動昇格を禁止する。
- 昇格判断は `reasonCode` と `trace` を必須記録し、後追い監査可能にする。
- 自動昇格は `instrumentType=ETF` かつ `insiderRisk=low` の場合に限定し、個別株は手動承認を必須とする。

### 10.4 エージェントベース分析の要件

- 定性情報（SNS、動画字幕、開示文章）を銘柄・テーマ・センチメントで構造化し、時刻付きで保存する。
- 収集Skillは「許可ソースホワイトリスト」「利用規約チェック」「重複排除」を必須とする。
- 生成インサイトは必ず一次ソース参照（URL/取得時刻/抜粋）を保持し、根拠なき要約を禁止する。

### 10.5 モデルベース分析の要件

- 定量モデルは既存の市場データ特徴量に加え、定性インサイト由来特徴量を結合可能にする。
- エージェント生成仮説でも、Walk-forward/DSR/PBO/コスト控除評価を通過しない限り昇格不可とする。
- バックテスト通過後は最低1〜2か月のデモトレードを必須化し、本番昇格の最終ゲートとする。
- ETFについては、コンプライアンス条件・MNPI自己申告記録・ブロックリスト非該当を満たす場合に限り、自動昇格を許可する。
- 個別株は、上記条件を満たしても手動昇格ゲートを1段残す。

### 10.6 知見資産化の要件

- 仮説ごとに「入力データ」「Skill版」「評価結果」「採否理由」「失敗原因」を紐付ける。
- 失敗仮説も削除せず保持し、次回探索時に類似仮説の重複実行を抑止する。
- 自作コードの参照テンプレートを管理し、AI出力を既存実装スタイルへ整合させる。

## 11. リスクと対応

- 規約違反リスク: データ提供元の利用条件を定期確認。
- モデル劣化リスク: 定期再学習 + シャドー運用で監視。
- 市場急変リスク: ボラ急騰時のポジション縮小ルールを実装。
- 運用ミスリスク: 手動介入と注文上限を設ける。
- AI誤要約リスク: 一次ソースリンク必須、引用根拠なしのインサイトは無効化する。
- 近傍反復リスク: 失敗知見DBで類似仮説を検知し、探索空間を拡張する。

## 12. 参考情報ソース（根拠）

### 12.1 実証・研究（勝率低下要因と対策）

- Morningstar Active vs Passive Barometer（2025-06時点）  
  https://www.morningstar.com/business/insights/blog/funds/active-vs-passive-investing
- SPIVA U.S. Mid-Year 2025  
  https://d1e00ek4ebabms.cloudfront.net/production/uploaded-files/spiva-us-mid-year-2025-bc7a7f61-4b27-48b0-b20a-856cc87521d0.pdf
- SPIVA Japan（Mid-Year 2025）  
  https://www.spglobal.com/spdji/en/spiva/article/spiva-japan/
- Gu, Kelly, Xiu (2020)  
  https://academic.oup.com/rfs/article/33/5/2223/5758276
- Harvey, Liu, Zhu (2016, NBER WP)  
  https://www.nber.org/papers/w20592
- McLean, Pontiff (2016)  
  https://afajof.org/issue/volume-71-issue-1/
- Berk, Green (2004, NBER WP)  
  https://www.nber.org/papers/w9275
- Monteiro et al. (2023)  
  https://link.springer.com/article/10.1186/s40854-022-00439-1
- Andersen et al. (2021)  
  https://www.sciencedirect.com/science/article/pii/S0304407620301950

### 12.2 インフラ・データ提供価格（コスト根拠）

- Cloud Run  
  https://cloud.google.com/run
- Cloud Scheduler pricing  
  https://cloud.google.com/scheduler/pricing
- Cloud Storage pricing  
  https://cloud.google.com/storage/pricing
- Firestore pricing  
  https://cloud.google.com/firestore/pricing
- Firestore quotas  
  https://docs.cloud.google.com/firestore/quotas
- Supabase MAU / Pro  
  https://supabase.com/docs/guides/platform/manage-your-usage/monthly-active-users
- Alpaca Market Data  
  https://docs.alpaca.markets/docs/about-market-data-api
- Alpaca Regulatory Fees  
  https://alpaca.markets/support/regulatory-fees
- Alpaca Commission/Clearing Fees  
  https://alpaca.markets/support/commission-clearing-fees
- Financial Modeling Prep pricing  
  https://site.financialmodelingprep.com/developer/docs/pricing
- J-Quants FAQ（利用目的）  
  https://jpx.gitbook.io/j-quants-en/faq/usage
- JPX J-Quants料金関連（お知らせ）  
  https://www.jpx.co.jp/corporate/news/news-releases/6020/20250505-01.html

## 13. 今後の更新方針

- 数値（勝率・料金・規約）は変動するため、四半期ごとに見直す。
- 次版では、運用頻度（日次/週次）と対象銘柄数を固定し、月額試算を数式化する。
- Skill品質レビュー（精度・失敗率・コスト）を週次で実施し、不要Skillを棚卸しする。
