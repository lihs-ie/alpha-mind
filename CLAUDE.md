# alpha-mind

AI投資運用MVP。日本株を売買対象とし、日本+米国の市場情報からシグナルを生成するイベント駆動マイクロサービスアプリケーション。

## プロジェクト概要

- 想定ユーザー: 1名（個人運用者）
- 売買対象: 日本株（現物）
- シグナル情報源: 日本 + 米国市場データ
- アーキテクチャ: イベント駆動マイクロサービス（Cloud Run + Pub/Sub）
- 月額コスト目標: 30〜60 USD以内

## ディレクトリ構成

```
alpha-mind/
├── CLAUDE.md                    # このファイル
├── documents/
│   ├── investment-ai-requirements.md  # 要件定義
│   ├── 機能仕様書.md                   # 機能仕様
│   ├── 外部設計/                       # 外部設計書一式
│   │   ├── api/                       #   OpenAPI / AsyncAPI
│   │   ├── db/                        #   Firestore設計
│   │   ├── error/                     #   エラーコード設計
│   │   ├── operations/                #   運用・監視設計
│   │   ├── screens/                   #   画面外部設計 (SCR-000〜SCR-005)
│   │   ├── security/                  #   認証認可設計
│   │   ├── services/                  #   サービス別外部設計
│   │   └── state/                     #   状態遷移設計
│   └── 内部設計/                       # 内部設計書一式
│       ├── 共通設計.md                 #   共通内部設計
│       ├── json/                      #   サービス定義JSON
│       └── services/                  #   サービス別内部設計
├── frontend/                    # Next.js フロントエンド
│   └── src/
│       ├── app/                 #   App Router ページ
│       ├── components/          #   UIコンポーネント (actions/data-display/feedback/form/layouts/skeleton)
│       ├── constants/           #   定数 (routes, screenIds, actionIds, messages)
│       ├── features/            #   画面単位の機能モジュール (dashboard/strategy/orders/audit/modelValidation/authentication)
│       ├── hooks/               #   共通カスタムフック
│       ├── lib/                 #   ユーティリティ (apiClient, traceId, formatters, validators)
│       ├── mocks/               #   MSW モックサーバー
│       ├── providers/           #   Context Provider (Auth/Toast/Theme/Msw)
│       └── types/               #   型定義 (api/domain/errors/ui)
└── design-system/
    └── alpha-mind/MASTER.md     # デザインシステム定義
```

## 技術スタック

### フロントエンド

| 領域 | 技術 | バージョン |
|------|------|-----------|
| フレームワーク | Next.js (App Router, Turbopack) | 16.1.6 |
| UI | React | 19.2.3 |
| コンパイラ | React Compiler | 1.0.0 |
| 言語 | TypeScript (strict) | ^5 |
| パッケージ管理 | pnpm | - |
| スタイリング | CSS Modules (Tailwind不使用) | - |
| テスト | Vitest（予定） | - |
| モック | MSW (Service Worker) | ^2.12.10 |
| Lint | ESLint + eslint-config-next | ^9 |
| フォント | Inter + Noto Sans JP / JetBrains Mono (数値) | - |

### バックエンド — Haskell APIサービス（設計済み・未実装）

対象: svc-bff, svc-data-collector, svc-portfolio-planner, svc-risk-guard, svc-execution, svc-audit-log

| 領域 | ライブラリ | バージョン | 用途 |
|------|-----------|-----------|------|
| コンパイラ | GHC | 9.14.1 (LTS) | Haskell コンパイラ |
| ビルド | Cabal | 3.16 | パッケージビルド |
| Webフレームワーク | Servant (servant-server) | 0.20.3.0 | 型安全REST API定義 |
| HTTPサーバー | Warp | 3.4.12 | 高性能HTTPサーバー |
| WAI | wai | 3.2.4 | Web Application Interface |
| JSON | aeson | 2.2.3.0 | JSON シリアライズ/デシリアライズ |
| JWT認証 | jose | 0.12 | JOSE/JWT (RS256署名検証) |
| GCP Pub/Sub | gogol-pubsub | 1.0.0 | イベントバス連携 |
| GCP Firestore | gogol-firestore | 1.0.0 | トランザクションDB |
| HTTP クライアント | http-conduit | 2.3.9.1 | 外部API呼び出し (ブローカー等) |
| ロギング | katip | 0.8.8.0 | 構造化ログ (Cloud Logging連携) |
| 並行処理 | unliftio | 0.2.25.1 | async/STM/例外の統合 |
| テスト | hspec | 2.11.16 | BDDテストフレームワーク |
| プロパティテスト | QuickCheck | 2.17.1.0 | プロパティベーステスト |

### バックエンド — Python 学習/推論サービス（設計済み・未実装）

対象: svc-signal-generator, svc-feature-engineering

| 領域 | 技術 | 用途 |
|------|------|------|
| 学習 | scikit-learn + LightGBM | 表形式特徴量の学習・推論 |
| 実験管理 | MLflow | モデルバージョン・評価結果追跡 |
| 検証 | Walk-forward + DSR/PBO | 過学習評価 |

### インフラ

| 領域 | 技術 |
|------|------|
| 実行基盤 | Cloud Run (`min instances=0`) |
| イベントバス | Google Cloud Pub/Sub |
| 定期実行 | Cloud Scheduler + Pub/Sub |
| DB | Firestore |
| データレイク | Cloud Storage (Parquet) |
| シークレット | Secret Manager |
| 監視 | Cloud Logging + Error Reporting |

### マイクロサービス構成

```
Cloud Scheduler → Event Bus (Pub/Sub)
  → svc-data-collector    : 市場データ収集（日本/米国）
  → svc-feature-engineering: 特徴量生成
  → svc-signal-generator  : シグナル生成（期待リターン/スコア算出）
  → svc-portfolio-planner : 注文候補作成（リバランス案）
  → svc-risk-guard        : リスクチェック（損失上限、集中度、kill switch）
  → svc-execution         : ブローカーAPI発注・約定結果保存
  → svc-audit-log         : 監査ログ記録

Web Console → svc-bff (API Gateway) → Firestore / Event Bus
```

## 開発コマンド

### フロントエンド

```bash
cd frontend
pnpm install          # 依存インストール
pnpm dev              # 開発サーバー起動
pnpm build            # プロダクションビルド
pnpm lint             # ESLint 実行
```

### バックエンド (Makefile)

```bash
cd backend
make setup            # GHC + Cabal セットアップ
make build            # 全サービスビルド
make build-service SVC=svc-bff  # 個別サービスビルド
make test             # 全テスト実行 (hspec + QuickCheck)
make test-service SVC=svc-bff   # 個別サービステスト
make lint             # HLint 実行
make format           # fourmolu フォーマット
make clean            # ビルド成果物削除
make docker-build     # Cloud Run 用 Docker イメージビルド
make docker-build-service SVC=svc-bff  # 個別 Docker ビルド
```

## コーディングルール

### 全般

- 変数名・関数名・クラス名は略さず記述する（`URL`, `UUID` 等の広く認知された略語は除く）
- `as any`, `as unknown` は禁止

```typescript
// OK
URL, UUID, ULID

// NG
GC_TIME    // → GARBAGE_COLLECTION_TIME
userRepo   // → userRepository
req        // → request
res        // → response
```

### スタイリング

- **Tailwind CSS は使用しない** — CSS Modules (`.module.css`) を使用する
- デザインシステムのCSS変数は `frontend/src/app/globals.css` で管理する
- ダークモードは `.dark` クラスで切り替え（CSS変数のオーバーライド）

### フォント

| 用途 | フォント |
|------|---------|
| UIテキスト | Inter + Noto Sans JP |
| 数値表示 | JetBrains Mono |

### CSS変数体系

`globals.css` で定義。主要トークン:

| カテゴリ | 例 |
|---------|-----|
| カラー | `--color-background`, `--color-surface`, `--color-accent`, `--color-profit`, `--color-loss` |
| シャドウ | `--shadow-sm`, `--shadow-md`, `--shadow-lg` |
| 角丸 | `--radius-sm`, `--radius-md`, `--radius-lg` |
| Z-index | `--z-dropdown(10)`, `--z-sticky(20)`, `--z-overlay(30)`, `--z-modal(40)`, `--z-toast(50)` |
| レイアウト | `--header-height(56px)`, `--sidebar-width(240px)` |

### コンポーネント設計

- `components/` : 汎用UIコンポーネント（画面非依存）
- `features/` : 画面固有のコンポーネントとフック
- パスエイリアス: `@/*` → `./src/*`

### イベント共通仕様

CloudEvents互換JSON。すべてのイベントに必須:

| 属性 | 説明 |
|------|------|
| `eventId` | 冪等性キー |
| `eventType` | イベント種別（例: `signal.generated`） |
| `occurredAt` | ISO8601 UTC |
| `traceId` | 横断追跡ID |
| `schemaVersion` | 後方互換管理用 |
| `payload` | 業務データ |

### エラーハンドリング

- API: RFC 9457互換 (`application/problem+json`)
- 一時障害: 指数バックオフで最大3回再試行
- 恒久障害: DLQへ転送、`*.failed` イベント発行
- バリデーション違反: 再試行せず即時失敗

### 認証・認可

- 外部公開は BFF のみ。内部サービスはインターネット非公開
- API認証: Bearer JWT (OIDC準拠、RS256)
- 認可: ロール (`admin` / `viewer`) + permission ベース
- サービス間通信: GCP IAM (Service Account)
- シークレット: Secret Manager

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

### Orders

`PROPOSED → APPROVED → EXECUTED` (正常系)
`PROPOSED → REJECTED` (却下)
`APPROVED → FAILED → PROPOSED` (失敗→再試行)

### Operations

- Runtime: `STOPPED ↔ RUNNING`
- Kill Switch: `DISABLED ↔ ENABLED`（有効時は承認/執行系を停止）

### Model Status

`candidate → approved` または `candidate → rejected`（終端。再遷移なし）

## 設計ドキュメント参照

設計判断の根拠や詳細仕様は以下を参照:

| ドキュメント | パス |
|-------------|------|
| 要件定義 | `documents/investment-ai-requirements.md` |
| 機能仕様 | `documents/機能仕様書.md` |
| API設計 (OpenAPI) | `documents/外部設計/api/openapi.yaml` |
| API設計 (AsyncAPI) | `documents/外部設計/api/asyncapi.yaml` |
| Firestore設計 | `documents/外部設計/db/firestore設計.md` |
| エラーコード | `documents/外部設計/error/error-codes.json` |
| 認証認可 | `documents/外部設計/security/認証認可設計.md` |
| 状態遷移 | `documents/外部設計/state/状態遷移設計.md` |
| 運用設計 | `documents/外部設計/operations/運用設計.md` |
| デザインシステム | `design-system/alpha-mind/MASTER.md` |
| 共通内部設計 | `documents/内部設計/共通設計.md` |

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

## テストポリシー

テストピラミッドに基づき、可能な限り低レイヤーでテストする。

| レイヤー | 対象 | 備考 |
|---------|------|------|
| Unit (Vitest) | 純粋ロジック、フック、ユーティリティ | DOM非依存を優先 |
| Integration (Vitest + MSW) | API連携、画面単位の振る舞い | MSWでモック |
| E2E (Playwright) | 画面遷移、認証フロー、クリティカルパス | 統合テスト |

## 安全性・コンプライアンス

- データ取り込みは「公開済み情報の許可ソース」のみ許可
- 手動入力はコード化理由 + 短文コメント（最大120文字）に制限
- MNPI（未公表の重要事実）疑義検知フィルタを適用
- 制限銘柄・ブラックアウト期間の注文は常に拒否
- AI提案戦略は Walk-forward/DSR/PBO 通過 + コンプライアンスレビュー済みでないと本番利用不可
- kill switch 有効時は `svc-execution` が全注文を拒否
