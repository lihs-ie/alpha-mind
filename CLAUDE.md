# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

alpha-mind は AI 投資運用 MVP。日本株を売買対象とし、日本+米国の市場情報からシグナルを生成するイベント駆動マイクロサービスアプリケーション。想定ユーザーは 1 名（個人運用者）。

## 開発コマンド

### フロントエンド (Sol / MoonBit)

```bash
cd applications/frontend

# Sol CLI はリファレンスからビルドした版を使用（npm公開版は使用しない）
# CLI パス: references/sol.mbt/_build/js/debug/build/cli/cli.js
node <sol-cli-path> dev          # 開発サーバー起動 (http://localhost:7777)
node <sol-cli-path> generate     # __gen__/ 再生成
node <sol-cli-path> build        # プロダクションビルド
node <sol-cli-path> serve        # プロダクション配信

# MoonBit
moon check --target js           # 型チェック（高速）
moon build --target js           # ビルド
moon test --target js            # ユニットテスト
moon update                      # mooncakes 依存更新
moon fmt                         # コードフォーマット

# npm
pnpm install                     # npm 依存インストール
```

### Sol CLI ビルド手順（初回のみ）

```bash
cd references/sol.mbt
pnpm install && moon update
moon build --target js
# => _build/js/debug/build/cli/cli.js が生成される
```

### バックエンド (Haskell — 設計済み・未実装)

```bash
cd backend
make build            # 全サービスビルド
make test             # 全テスト実行 (hspec + QuickCheck)
make build-service SVC=svc-bff   # 個別サービスビルド
make test-service SVC=svc-bff    # 個別サービステスト
make lint             # HLint
make format           # fourmolu
```

## アーキテクチャ

### マイクロサービス構成

```
Cloud Scheduler → Event Bus (Pub/Sub)
  → svc-data-collector    : 市場データ収集（日本/米国）
  → svc-feature-engineering: 特徴量生成 (Python)
  → svc-signal-generator  : シグナル生成 (Python)
  → svc-portfolio-planner : 注文候補作成
  → svc-risk-guard        : リスクチェック（損失上限、集中度、kill switch）
  → svc-execution         : ブローカーAPI発注
  → svc-audit-log         : 監査ログ記録

Web Console → svc-bff (API Gateway) → Firestore / Event Bus
```

外部公開は BFF のみ。内部サービスはインターネット非公開（GCP IAM）。

### フロントエンド — Sol (MoonBit SSR フレームワーク)

**Next.js プロトタイプから Sol へ移行中。** Sol は SSR-first + Island Architecture のフレームワーク。

| 区分 | 技術 |
|------|------|
| フレームワーク | Sol 0.8.0 (mizchi/sol) |
| 言語 | MoonBit (コンパイル先: JS/WASM) |
| UIライブラリ | Luna 0.13.0 (VNode + Signal) |
| HTTPサーバー | Hono v4 (Mars アダプタ経由) |
| バンドラ | Rolldown |
| リアクティビティ | mizchi/signals 0.6.3 (alien-signals ベース) |

**Sol プロジェクト構造** (`applications/frontend/`):

```
app/
├── server/          # サーバーコンポーネント (SSR)
│   ├── routes.mbt   # ルート定義（単一ソース）
│   └── *.mbt        # ページハンドラ
├── client/          # クライアントコンポーネント (Island, ブラウザで実行)
│   └── *.mbt        # インタラクティブコンポーネント
├── layout/          # レイアウト定義
│   └── layout.mbt   # head() + root_layout()
└── __gen__/         # sol generate 自動生成（手動編集しない）
```

**レンダリングモデル**:
- サーバーコンポーネント (`app/server/`): SSR で HTML を生成。イベントハンドラなし
- クライアントコンポーネント / Island (`app/client/`): ブラウザで hydration 実行。Signal でリアクティブ更新
- `loader.js` が `luna:*` 属性を検出し Island モジュールを動的ロード → hydrate

**ルーティング**: ファイルベースではなく `app/server/routes.mbt` で宣言的に定義。`SolRoutes` enum を使用。

### バックエンド — Haskell APIサービス（設計済み・未実装）

対象: svc-bff, svc-data-collector, svc-portfolio-planner, svc-risk-guard, svc-execution, svc-audit-log

| 区分 | 技術 | バージョン |
|------|------|-----------|
| コンパイラ | GHC | 9.12.2 |
| ビルドツール | Cabal | 3.16.1.0 |
| Web フレームワーク | Servant (servant-server) | 0.20.3.0 |
| HTTP サーバー | Warp | 3.4.12 |
| JSON | aeson | 2.2.3.0 |
| JWT | jose | 0.12 |
| GCP 連携 | gogol-pubsub / gogol-firestore | 1.0.0 |
| ログ | katip | 0.8.8.0 |
| テスト | hspec + QuickCheck | - |

### バックエンド — Python 学習/推論（設計済み・未実装）

対象: svc-signal-generator, svc-feature-engineering

| 区分 | 技術 | バージョン |
|------|------|-----------|
| ランタイム | Python | 3.14 |
| 学習 | scikit-learn + LightGBM | - |
| 実験管理 | MLflow | - |

### インフラ

Cloud Run (`min instances=0`) / Pub/Sub / Cloud Scheduler / Firestore / Cloud Storage (Parquet) / Secret Manager / Cloud Logging

| 区分 | 技術 | バージョン |
|------|------|-----------|
| IaC | Terraform | >= 1.14 |
| GCP Provider | hashicorp/google | ~> 7.0 |
| Node.js (frontend) | Node.js | 24 LTS (Krypton) |

## コーディングルール

### 全般

- 変数名・関数名・クラス名は略さず記述する（`URL`, `UUID`, `ULID` 等の広く認知された略語は除く）
- TypeScript: `as any`, `as unknown` は禁止

```
// NG: userRepo → userRepository, req → request, res → response
```

### スタイリング

- **Tailwind CSS は使用しない**
- デザインシステムの CSS 変数は `globals.css` で管理
- ダークモードは `.dark` クラスで切り替え（CSS 変数オーバーライド）

### CSS 変数体系

`globals.css` で定義。主要トークン:

| カテゴリ | 例 |
|---------|-----|
| カラー | `--color-background`, `--color-surface`, `--color-accent`, `--color-profit`, `--color-loss` |
| シャドウ | `--shadow-sm`, `--shadow-md`, `--shadow-lg` |
| 角丸 | `--radius-sm`, `--radius-md`, `--radius-lg` |
| Z-index | `--z-dropdown(10)`, `--z-sticky(20)`, `--z-overlay(30)`, `--z-modal(40)`, `--z-toast(50)` |
| レイアウト | `--header-height(56px)`, `--sidebar-width(240px)` |

### フォント

UIテキスト: Inter + Noto Sans JP / 数値表示: JetBrains Mono

### Sol 固有のルール

- **`__gen__/` ディレクトリは手動編集しない** — `sol generate` で再生成される
- `head()` に必ず `loader_script` を含める（Island hydration に必須）
- `static/loader.js` はリファレンス (`references/sol.mbt/examples/`) から正しい版をコピーすること（生成テンプレートのスタブでは hydration が動作しない）
- npm 公開版の `sol new` は使用しない（古い依存構成を生成するため）
- 正しいインポートパス: `mizchi/sol/router`（`mizchi/luna/sol/router` は古い）

### MoonBit パッケージのエイリアス

| パッケージ | エイリアス | 用途 |
|-----------|-----------|------|
| `mizchi/luna` | `@luna` | UI ライブラリ (VNode) |
| `mizchi/sol` | `@sol` | SSR フレームワーク |
| `mizchi/sol/router` | `@router` | ルーティング (SolRoutes, PageProps) |
| `mizchi/sol/action` | `@action` | Server Actions (CSRF 保護) |
| `mizchi/sol/server_dom` | `@server_dom` | サーバーサイド DOM |
| `mizchi/signals` | `@signal` | リアクティブシグナル |
| `mizchi/js/core` | `@core` | MoonBit-JS FFI |

## 画面一覧

| ID | 画面名 | URL | 概要 |
|-----|--------|-----|------|
| SCR-000 | 認証 | `/login` | ログイン |
| SCR-001 | ダッシュボード | `/dashboard` | 運用状態把握、緊急操作 |
| SCR-002 | 戦略設定 | `/settings/strategy` | 運用パラメータ設定 |
| SCR-003 | 注文管理 | `/orders` | 注文候補の確認・承認・再送 |
| SCR-004 | 監査ログ | `/audit` | 監査追跡・障害調査 |
| SCR-005 | モデル検証 | `/models/validation` | 評価結果確認とモデル昇格判断 |

## 状態遷移

- **Orders**: `PROPOSED → APPROVED → EXECUTED` / `PROPOSED → REJECTED` / `APPROVED → FAILED → PROPOSED`
- **Runtime**: `STOPPED ↔ RUNNING`
- **Kill Switch**: `DISABLED ↔ ENABLED`（有効時は承認/執行系を停止）
- **Model Status**: `candidate → approved | rejected`（終端、再遷移なし）

## イベント共通仕様

CloudEvents 互換 JSON。必須属性: `identifier`(冪等性キー/ULID), `eventType`, `occurredAt`(ISO8601 UTC), `trace`(ULID), `schemaVersion`, `payload`

## エラーハンドリング

- API: RFC 9457 互換 (`application/problem+json`)
- 一時障害: 指数バックオフで最大 3 回再試行
- 恒久障害: DLQ へ転送、`*.failed` イベント発行
- バリデーション違反: 再試行せず即時失敗

## 認証・認可

- API 認証: Bearer JWT (OIDC 準拠、RS256)
- 認可: ロール (`admin` / `viewer`) + permission ベース
- サービス間通信: GCP IAM (Service Account)

## テストポリシー

テストピラミッドに基づき、可能な限り低レイヤーでテストする。

| レイヤー | 対象 | 備考 |
|---------|------|------|
| Unit (MoonBit `moon test` / Vitest) | 純粋ロジック、ユーティリティ | DOM非依存を優先 |
| Integration | API連携、画面単位の振る舞い | モックで外部依存を分離 |
| E2E (Playwright) | 画面遷移、認証フロー、クリティカルパス | 統合テスト |

## コミットメッセージ

[Conventional Commits](https://www.conventionalcommits.org/) に従う。

```
<type>(<scope>): <description>
```

| type | 用途 |
|------|------|
| `feat` | 新機能 |
| `fix` | バグ修正 |
| `docs` | ドキュメント |
| `refactor` | リファクタリング |
| `perf` | パフォーマンス改善 |
| `test` | テスト追加・修正 |
| `chore` | ビルド・CI・設定変更 |
| `style` | コードスタイル修正（動作変更なし） |

スコープ例: `frontend`, `bff`, `data-collector`, `signal-generator`, `risk-guard`, `docs`

## 設計ドキュメント参照

| ドキュメント | パス |
|-------------|------|
| 要件定義 | `documents/investment-ai-requirements.md` |
| 機能仕様 | `documents/機能仕様書.md` |
| API 設計 (OpenAPI) | `documents/外部設計/api/openapi.yaml` |
| API 設計 (AsyncAPI) | `documents/外部設計/api/asyncapi.yaml` |
| Firestore 設計 | `documents/外部設計/db/firestore設計.md` |
| エラーコード | `documents/外部設計/error/error-codes.json` |
| 認証認可 | `documents/外部設計/security/認証認可設計.md` |
| 状態遷移 | `documents/外部設計/state/状態遷移設計.md` |
| 運用設計 | `documents/外部設計/operations/運用設計.md` |
| デザインシステム | `design-system/alpha-mind/MASTER.md` |
| 共通内部設計 | `documents/内部設計/共通設計.md` |
| Sol 実装ガイド | `documents/sol-insstruction.md` |
| Next.js→Sol 比較 | `documents/nextjs-vs-sol-comparison.md` |
| Sol フレームワーク参照 | `references/sol.mbt/` (git-ignored、ローカルクローン必要) |

## 安全性・コンプライアンス

- データ取り込みは「公開済み情報の許可ソース」のみ許可
- MNPI（未公表の重要事実）疑義検知フィルタを適用
- 制限銘柄・ブラックアウト期間の注文は常に拒否
- AI 提案戦略は Walk-forward/DSR/PBO 通過 + コンプライアンスレビュー済みでないと本番利用不可
- kill switch 有効時は `svc-execution` が全注文を拒否
