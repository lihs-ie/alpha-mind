# Firestore設計

最終更新日: 2026-03-03

## 1. 目的

- BFFおよび各マイクロサービスが利用するFirestoreの論理設計を定義する。
- 対象はコレクション構造、アクセスパターン、インデックス、TTL、運用方針。

## 2. 設計方針

1. BFF経由アクセスを原則とし、クライアントからFirestoreへ直接接続しない。  
2. 1ユーザーMVP前提で、固定費より従量課金最適化を優先する。  
3. 監査可能性を確保するため、更新系は `trace` と `updatedAt` を必須化する。  
4. イベント冪等性のため、`idempotency_keys` を全イベント処理で使用する。  

## 3. コレクション定義

### 3.1 `settings`

用途:
- 戦略設定・リスク設定の保持

ドキュメント例:
- `settings/strategy`

主要フィールド:
- `market` (`JP`)
- `rebalanceFrequency` (`daily` or `weekly`)
- `symbols` (array<string>)
- `dailyLossLimit` (number)
- `positionConcentrationLimit` (number)
- `dailyOrderLimit` (number)
- `version` (number)
- `updatedAt` (timestamp)
- `updatedBy` (string)

### 3.2 `operations`

用途:
- 運用状態（runtime/kill switch）管理

ドキュメント例:
- `operations/runtime`

主要フィールド:
- `runtimeState` (`RUNNING` / `STOPPED`)
- `killSwitchEnabled` (boolean)
- `reason` (string)
- `updatedAt` (timestamp)
- `updatedBy` (string)

### 3.3 `positions`

用途:
- 現在保有状態のスナップショット

ドキュメントID:
- `symbol`（例: `7203.T`）

主要フィールド:
- `symbol`
- `qty`
- `avgPrice`
- `marketValue`
- `updatedAt`

### 3.4 `orders`

用途:
- 注文候補（提案）の正本管理（`portfolio-planner` オーナー）
- 注文一覧表示の基底データ（審査/執行状態は `risk_assessments` / `order_executions` を参照して統合）

ドキュメントID:
- `identifier` (ULID)

主要フィールド:
- `identifier`
- `symbol`
- `side` (`BUY` / `SELL`)
- `qty`
- `status` (`PROPOSED`)
- `proposal` (string)
- `trace` (string)
- `createdAt` (timestamp)
- `updatedAt` (timestamp)
- `version` (number)

### 3.5 `model_registry`

用途:
- モデルバージョン管理

ドキュメントID:
- `modelVersion`

主要フィールド:
- `modelVersion`
- `status` (`candidate` / `approved` / `rejected`)
- `metrics` (`oosReturn`, `sharpe`, `maxDrawdown`, `turnover`, `pbo`, `dsr`)
- `featureVersion`
- `createdAt`
- `decidedAt` (optional)
- `decidedBy` (optional)

### 3.6 `audit_logs`

用途:
- 監査ログ索引（長期はCloud Logging）

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `eventType`
- `service`
- `result` (`success` / `failed`)
- `trace`
- `reason`
- `occurredAt`
- `payloadSummary` (map)
- `expiresAt` (timestamp, TTL)

### 3.7 `compliance_controls`

用途:
- インサイダー接触回避の制御情報（制限銘柄、ブラックアウト期間、入力制約）

ドキュメント例:
- `compliance_controls/trading`

主要フィールド:
- `restrictedSymbols` (array<string>)
- `partnerRestrictedSymbols` (array<string>)
- `blackoutWindows` (array<map{symbol,startAt,endAt,actionReasonCode}>)
- `mnpiKeywordVersion` (string)
- `sourcePolicyVersion` (string)
- `autoPromotionEnabled` (boolean, default: false)
- `maxCommentLength` (number, default: 120)
- `updatedAt` (timestamp)
- `updatedBy` (string)

### 3.8 `idempotency_keys`

用途:
- 処理済みイベント管理

ドキュメントID:
- `{service}:{identifier}` (サービス間衝突防止のためサービス名プレフィックスを付与)

主要フィールド:
- `identifier`
- `service`
- `processedAt`
- `trace`
- `expiresAt` (timestamp, TTL)
- `updatedAt` (timestamp)

### 3.9 `skill_registry`

用途:
- Claude Code Skillの定義・版管理

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `name`
- `version`
- `status` (`active` / `deprecated`)
- `runner` (`cloud-run-job` / `manual`)
- `scope` (`insight` / `hypothesis` / `validation`)
- `updatedAt`
- `updatedBy`

### 3.10 `insight_records`

用途:
- 定性インサイト（X/YouTube/論文/GitHub）保存

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `symbol` (optional)
- `theme`
- `sentiment` (`positive` / `neutral` / `negative`)
- `sourceType` (`x` / `youtube` / `paper` / `github`)
- `sourceUrl`
- `evidenceSnippet`
- `signalClass` (`structural_anomaly` / `event_noise`)
- `soWhatScore` (number, `0.0-1.0`)
- `skillVersion`
- `collectedAt`
- `expiresAt` (timestamp, TTL optional)

### 3.11 `hypothesis_registry`

用途:
- 仮説ライフサイクル管理

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `symbol`
- `title`
- `status` (`draft` / `backtested` / `demo` / `live` / `rejected`)
- `instrumentType` (`ETF` / `STOCK`)
- `insiderRisk` (`low` / `medium` / `high`)
- `mnpiSelfDeclared` (boolean)
- `autoPromotionEligible` (boolean)
- `promotionMode` (`manual` / `auto`)
- `sourceEvidence` (array<string>)
- `skillVersion`
- `instructionProfileVersion`
- `createdAt`
- `updatedAt`
- `updatedBy`

### 3.12 `backtest_runs`

用途:
- 仮説のバックテスト結果保存

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `hypothesis`
- `datasetVersion`
- `metrics` (`oosReturn`, `costAdjustedReturn`, `sharpe`, `pbo`, `dsr`)
- `passed` (boolean)
- `executedAt`

### 3.13 `demo_trade_runs`

用途:
- デモトレード結果保存

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `hypothesis`
- `startAt`
- `endAt`
- `metrics`
- `promotable` (boolean)
- `evaluatedAt`

### 3.14 `failure_knowledge`

用途:
- 失敗仮説と失敗理由の知見化

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `hypothesis`
- `failureType`
- `reasonCode`
- `summary`
- `markdownSummary`
- `preventionChecklist` (array<string>)
- `similarityHash`
- `createdAt`

### 3.15 `instruction_profiles`

用途:
- Markdown指示書プロトコル管理

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `name`
- `version`
- `contentPath`
- `updatedAt`
- `updatedBy`

### 3.16 `source_policies`

用途:
- 収集可能ソースと利用規約条件の管理

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `sourceType` (`x` / `youtube` / `paper` / `github` / `nisshokin`)
- `enabled` (boolean)
- `termsVersion` (string)
- `redistributionAllowed` (boolean)
- `dailyQuota` (number)
- `sourceConfig` (map)
- `sourceConfig.x.accountHandles` (array<string>, sourceType=`x` の場合必須)
- `sourceConfig.x.keywordQuery` (string)
- `sourceConfig.x.excludeKeywords` (array<string>)
- `sourceConfig.x.includeReplies` (boolean, default=false)
- `sourceConfig.x.minEngagement` (number, default=3)
- `sourceConfig.x.soWhatThreshold` (number, default=0.70)
- `sourceConfig.x.scoringWeights` (map{freshness,credibility,reproducibility,marketRelevance})
- `sourceConfig.youtube.channelIdentifiers` (array<string>, sourceType=`youtube` の場合必須)
- `sourceConfig.youtube.keywordQuery` (string)
- `sourceConfig.youtube.includeLive` (boolean, default=true)
- `sourceConfig.youtube.includeComments` (boolean, default=true)
- `sourceConfig.youtube.maxCommentsPerVideo` (number, default=20)
- `sourceConfig.youtube.transcriptProvider` (`none` / `approved`)
- `sourceConfig.youtube.soWhatThreshold` (number, default=0.70)
- `sourceConfig.youtube.scoringWeights` (map{freshness,credibility,reproducibility,marketRelevance})
- `sourceConfig.paper.providers` (array<string>, sourceType=`paper` の場合必須)
- `sourceConfig.paper.query` (string)
- `sourceConfig.paper.maxItemsPerRun` (number, default=200)
- `sourceConfig.paper.soWhatThreshold` (number, default=0.70)
- `sourceConfig.paper.scoringWeights` (map{freshness,credibility,reproducibility,marketRelevance})
- `sourceConfig.github.repositories` (array<string>, sourceType=`github` の場合必須)
- `sourceConfig.github.includeReadme` (boolean, default=true)
- `sourceConfig.github.includeReleases` (boolean, default=true)
- `sourceConfig.github.maxItemsPerRun` (number, default=200)
- `sourceConfig.github.soWhatThreshold` (number, default=0.70)
- `sourceConfig.github.scoringWeights` (map{freshness,credibility,reproducibility,marketRelevance})
- `updatedAt` (timestamp)
- `updatedBy` (string)

### 3.17 `code_reference_templates`

用途:
- 自作コード参照テンプレート管理（プロンプト再現性担保）

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `name`
- `scope` (`insight` / `hypothesis` / `validation`)
- `version`
- `markdownPath`
- `updatedAt`
- `updatedBy`

### 3.18 `risk_assessments`

用途:
- 注文審査結果の正本管理（`risk-guard` オーナー）

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `order`
- `decision` (`approved` / `rejected`)
- `reasonCode` (string, optional)
- `actionReasonCode` (string, optional)
- `trace`
- `evaluatedAt`
- `version`

### 3.19 `order_executions`

用途:
- 注文執行結果の正本管理（`execution` オーナー）

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `status` (`APPROVED` / `EXECUTED` / `FAILED`)
- `attemptCount`
- `brokerOrder` (string, optional)
- `reasonCode` (string, optional)
- `trace`
- `executedAt` (timestamp, optional)
- `updatedAt` (timestamp)
- `version`

### 3.20 `access_decisions`

用途:
- BFFの認証認可判定結果を保持（`bff` オーナー）

ドキュメントID:
- `identifier`

主要フィールド:
- `identifier`
- `trace`
- `user`
- `endpoint`
- `permission`
- `result` (`allow` / `deny`)
- `reasonCode` (string, optional)
- `decidedAt` (timestamp)

### 3.21 `feature_generations`

用途:
- 特徴量生成処理の状態管理（`feature-engineering` オーナー）

ドキュメントID:
- `identifier` (ULID)

主要フィールド:
- `identifier`
- `status` (`pending` / `generated` / `failed`)
- `market` (map: `targetDate`, `storagePath`, `sourceStatus`)
- `trace`
- `insight` (map, optional)
- `featureArtifact` (map, optional)
- `failureDetail` (map, optional)
- `processedAt` (timestamp, optional)
- `updatedAt` (timestamp, optional)

### 3.22 `feature_dispatches`

用途:
- 特徴量イベント配信の状態管理（`feature-engineering` オーナー）

ドキュメントID:
- `identifier` (ULID)

主要フィールド:
- `identifier`
- `dispatchStatus` (`pending` / `published` / `failed`)
- `trace`
- `dispatchDecision` (map: `dispatchStatus`, `publishedEvent`, `reasonCode`)
- `processedAt` (timestamp, optional)
- `updatedAt` (timestamp, optional)

## 4. 主要アクセスパターン

| 画面/サービス | クエリ | 期待件数 |
|---|---|---|
| SCR-001 ダッシュボード | `operations/runtime` 直接取得 | 1件 |
| SCR-002 戦略設定 | `settings/strategy` 直接取得・更新 | 1件 |
| SCR-003 注文管理 | `orders` + `risk_assessments` + `order_executions` を `identifier` で統合し `createdAt desc` で取得 | 50件/ページ |
| SCR-004 監査ログ | `audit_logs` を `trace` or `eventType` + `occurredAt desc` で取得 | 50件/ページ |
| SCR-005 モデル検証 | `model_registry` を `status` + `createdAt desc` で取得 | 20件 |
| risk-guard | `operations/runtime` と `settings/strategy` と `compliance_controls/trading` を点取得 | 3件 |
| SCR-006 インサイト管理 | `insight_records` を `theme` + `collectedAt desc` で取得 | 50件/ページ |
| SCR-007 仮説ラボ | `hypothesis_registry` を `status` + `updatedAt desc` で取得 | 30件 |
| insight-collector | `source_policies` を `sourceType` + `enabled` で取得 | 5件以内 |
| agent-orchestrator | `skill_registry` と `instruction_profiles` と `code_reference_templates` と `failure_knowledge` を点取得 | 3〜15件 |

## 5. インデックス設計

定義ファイル:
- `外部設計/db/firestore.indexes.json`

主要複合インデックス:
1. `orders(createdAt DESC)`
2. `orders(symbol ASC, createdAt DESC)`
3. `orders(symbol ASC, side ASC, createdAt DESC)`
4. `audit_logs(trace ASC, occurredAt DESC)`
5. `audit_logs(eventType ASC, occurredAt DESC)`
6. `model_registry(status ASC, createdAt DESC)`
7. `insight_records(theme ASC, collectedAt DESC)`
8. `hypothesis_registry(status ASC, updatedAt DESC)`
9. `failure_knowledge(similarityHash ASC, createdAt DESC)`
10. `source_policies(sourceType ASC, enabled ASC, updatedAt DESC)`
11. `code_reference_templates(scope ASC, updatedAt DESC)`
12. `risk_assessments(decision ASC, evaluatedAt DESC)`
13. `order_executions(status ASC, updatedAt DESC)`
14. `access_decisions(user ASC, decidedAt DESC)`

## 6. TTL設計

TTL対象:
- `idempotency_keys.expiresAt`（30日）
- `audit_logs.expiresAt`（90日）
- `insight_records.expiresAt`（365日、必要に応じて延長）

補足:
- 監査の長期保管はCloud Logging/アーカイブ側（7年）を正とする。

## 7. 整合性と同時更新

1. 更新競合対策
- `orders`, `risk_assessments`, `order_executions`, `settings`, `operations` は `version` を持ち、楽観ロックで更新する。

2. トランザクション方針
- 単一ドキュメント更新は通常更新。
- 複数ドキュメント整合が必要な場合のみFirestore Transactionを使用。

3. 禁止事項
- サービス間で同一ドキュメントを無制限に共有更新しない。

## 8. セキュリティルール方針

ルールファイル:
- `外部設計/db/firestore.rules`

方針:
- クライアントSDKからの直接 read/write は禁止（`allow false`）。
- サーバーサイド（BFF/マイクロサービス）はAdmin SDK + IAMでアクセス制御。

## 9. コスト最適化方針

1. リスナーを常時利用しない（MVPはポーリング/都度取得）。
2. 一覧APIは必ず `limit` + `cursor` を使う。  
3. 不要な全件スキャンを禁止する。  
4. 監査詳細は `payloadSummary` を優先し、大きいpayloadはCloud Logging参照。  

## 10. バックアップ/復旧方針

- Firestore Exportを日次実行（GCS保存）。
- 重大障害時は最新エクスポートから復旧。
- 復旧後は `operations/runtime=STOPPED` を初期状態とする。

## 11. 参照

- OpenAPI: `外部設計/api/openapi.yaml`
- AsyncAPI: `外部設計/api/asyncapi.yaml`
- 状態遷移: `外部設計/state/状態遷移設計.md`
- 内部共通設計: `内部設計/共通設計.md`
