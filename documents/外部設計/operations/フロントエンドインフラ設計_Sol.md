# フロントエンドインフラ設計（Sol）

最終更新日: 2026-02-28

## 1. 目的

- `applications/frontend-sol/`（MoonBit + Sol）の本番/検証デプロイ設計を定義する。
- 既存の GCP 中心運用（`STG環境構築設計.md`）と整合する形で、フロントエンド配信基盤を確定する。

## 2. 調査対象と結論

### 2.1 調査対象

- ローカル一次情報（`references/sol.mbt`）
  - `README.md`
  - `docs/deploy.md`
  - `src/cli/deploy.mbt`
  - `spec/005-cloudflare-hybrid.md`
- プロジェクト現状
  - `applications/frontend-sol/sol.config.json`
  - `applications/frontend-sol/app/server/routes.mbt`
- 外部一次情報
  - Cloud Run公式ドキュメント
  - Cloudflare Workers公式ドキュメント

### 2.2 結論（採用方針）

1. 採用基盤は **Cloud Run（GCP）** とする。
2. `frontend-sol` は現状 `runtime: "node"` のため、Cloud Runと整合する。
3. Sol CLIの `deploy` は Cloudflare 向け（`cloudflare-workers` / `cloudflare-pages`）が中心のため、GCP配備は CI/CD 側で実装する。
4. Cloudflare Workers 配備は「代替案（将来のEdge最適化）」として設計に残す。

## 3. 前提

### 3.1 アプリ前提

- `sol.config.json`: `runtime = "node"`
- ルート:
  - `GET /`（SSR + Island）
  - `GET /about`
  - `GET /api/health`（ヘルスチェック用）
- ローダー: `/static/loader.js`

### 3.2 CLI前提

- `applications/frontend-sol` の `pnpm build` は現状 `sol` コマンド未解決で失敗する。
- 実行コマンドはローカルビルドした Sol CLI を固定使用する:
  - `node ../../references/sol.mbt/_build/js/debug/build/cli/cli.js <command>`

## 4. 採用アーキテクチャ（Cloud Run）

### 4.1 構成

```text
User Browser
  -> https://staging.app.alpha-mind.dev / https://app.alpha-mind.dev
  -> Cloud Run Service: frontend-sol
  -> (API呼び出し) BFF: https://staging.api.alpha-mind.dev / https://api.alpha-mind.dev
```

### 4.2 環境

| 環境 | GCP Project | Cloud Run Service | URL |
|---|---|---|---|
| STG | `alpha-mind-stg` | `frontend-sol` | `https://staging.app.alpha-mind.dev` |
| PROD | `alpha-mind-prod` | `frontend-sol` | `https://app.alpha-mind.dev` |

### 4.3 Cloud Run 実行パラメータ（初期値）

| 項目 | STG | PROD |
|---|---:|---:|
| CPU | 1 vCPU | 1 vCPU |
| Memory | 512Mi | 512Mi |
| Request Timeout | 30s | 30s |
| Concurrency | 80 | 80 |
| Min Instances | 0 | 0 |
| Max Instances | 10 | 10 |
| Ingress | all | all |

補足:

- 単一ユーザー運用前提でコスト優先の `min instances=0` とする。
- 将来、コールドスタートが問題化した場合のみ PROD を `min instances=1` に変更する。

## 5. コンテナ設計

### 5.1 ビルド成果物

- `sol build` 実行後、以下をランタイムに含める:
  - `.sol/prod/server/main.js`
  - `.sol/prod/static/`
  - `_build/js/release/build/**`

### 5.2 起動コマンド

- Cloud Run 起動コマンド:
  - `node .sol/prod/server/main.js`

### 5.3 必須環境変数

| ENV Key | STG | PROD | 用途 |
|---|---|---|---|
| `APP_ENV` | `stg` | `prod` | 実行環境識別 |
| `PORT` | Cloud Run 自動注入 | Cloud Run 自動注入 | リッスンポート |
| `BFF_BASE_URL` | `https://staging.api.alpha-mind.dev` | `https://api.alpha-mind.dev` | API接続先 |

## 6. CI/CD 設計（frontend-sol）

### 6.1 パイプライン

1. `validate`
- `moon check --target js`（`applications/frontend-sol`）
- ルート整合確認: `sol generate --mode prod` 実行可否

2. `build`
- `references/sol.mbt` で `moon build --target js`（CLI生成）
- `applications/frontend-sol` で Sol CLI 経由 `build`
- Docker image build
- Artifact Registry へ push（digest保存）

3. `deploy-stg`
- digest固定で Cloud Run `frontend-sol`（STG）へ反映
- `GET /api/health` の疎通確認

4. `promote-prod`（手動承認）
- STG動作確認後、同一digestをPRODへ反映

### 6.2 デプロイ不変条件

1. PRODで再buildしない（STGで検証済みdigestを昇格）。
2. ロールバックは前回正常digestへ即時切替する。
3. デプロイ・ロールバック操作は `trace`, `actionReasonCode`, `user` を監査記録する。

## 7. 監視・運用

### 7.1 監視項目

| ID | 指標 | 目標 |
|---|---|---|
| FE-SLO-001 | `/api/health` 成功率 | 99.5%以上 |
| FE-SLO-002 | `/` 応答時間（p95） | 1000ms 以下 |
| FE-SLO-003 | 5xx 比率 | 0.5% 未満 |

### 7.2 運用ルール

1. フロント単体障害時も BFF への異常トラフィック増幅を防ぐ（再試行上限をUI側で制御）。
2. 静的アセットのキャッシュ方針は段階導入し、初期はCloud Run直配信で開始する。
3. カスタムドメイン運用は、Cloud Run ドメインマッピング制約を考慮し、必要に応じてロードバランサ経由へ移行する。

## 8. 代替案（Cloudflare Workers）

### 8.1 適用条件

- `sol.config` の `runtime` を `cloudflare` に変更し、`wrangler` 運用を採用する場合。

### 8.2 特徴

1. Sol CLI の `sol deploy` と整合しやすい。
2. `spec/005-cloudflare-hybrid.md` の `run_worker_first` 設計で静的/動的ルート分離が可能。
3. 既存GCP基盤（BFF/監視/IAM）と運用面が分断されるため、現時点では不採用。

## 9. 実装タスク

1. `applications/frontend-sol/package.json` をローカルCLI呼び出しに置換（`sol` 直呼びを廃止）。
2. `applications/frontend-sol` 用 Dockerfile を追加（build成果物を本番イメージへコピー）。
3. `frontend-sol` 用 Cloud Run サービス定義を Terraform `infra/platform` に追加。
4. CI ワークフローに frontend-sol build/deploy ジョブを追加。

## 10. 根拠ソース

- Sol README（Quick Start / runtime / deploy CLI）  
  `references/sol.mbt/README.md`
- Sol deploy 実装（provider対応範囲）  
  `references/sol.mbt/src/cli/deploy.mbt`
- Sol Cloudflare hybrid spec  
  `references/sol.mbt/spec/005-cloudflare-hybrid.md`
- Cloud Run: Deploying to Cloud Run（コンテナデプロイ）  
  https://cloud.google.com/run/docs/deploying
- Cloud Run: Container runtime contract（PORTなど）  
  https://cloud.google.com/run/docs/container-contract
- Cloud Run: Custom domains（ドメインマッピング制約）  
  https://cloud.google.com/run/docs/mapping-custom-domains
- Cloudflare Workers Static Assets（`run_worker_first`）  
  https://developers.cloudflare.com/workers/static-assets/routing/worker-script/
