# Next.js プロトタイプ vs Sol (MoonBit) 再構築 比較ドキュメント

本ドキュメントは `applications/frontend-prototype/` (Next.js 16 + React 19) の構成を Sol (MoonBit) で再構築する場合の詳細な比較を記載する。

> **Sol バージョン**: mizchi/sol 0.8.0 (luna 0.13.0, signals 0.6.3, mars 0.3.9)
> **参照**: `references/sol.mbt/`

---

## 目次

1. [プロジェクト構成の比較](#1-プロジェクト構成の比較)
2. [設定ファイルの対応表](#2-設定ファイルの対応表)
3. [ルーティングの比較](#3-ルーティングの比較)
4. [レイアウト・認証ガードの比較](#4-レイアウト認証ガードの比較)
5. [状態管理の比較](#5-状態管理の比較)
6. [コンポーネント設計の比較](#6-コンポーネント設計の比較)
7. [スタイリングの比較](#7-スタイリングの比較)
8. [APIクライアントの比較](#8-apiクライアントの比較)
9. [型定義の比較](#9-型定義の比較)
10. [テスト・モックの比較](#10-テストモックの比較)
11. [6画面すべての対応詳細](#11-6画面すべての対応詳細)
12. [自作が必要なコンポーネント一覧](#12-自作が必要なコンポーネント一覧)
13. [移行ロードマップ](#13-移行ロードマップ)

---

## 1. プロジェクト構成の比較

### Next.js (現行)

```
applications/frontend-prototype/
├── package.json
├── tsconfig.json
├── next.config.ts
├── public/
│   └── mockServiceWorker.js
└── src/
    ├── app/
    │   ├── layout.tsx              # RootLayout
    │   ├── page.tsx                # / → /dashboard リダイレクト
    │   ├── globals.css             # デザインシステム CSS変数
    │   ├── login/page.tsx
    │   └── (authenticated)/        # Route Group (認証ガード)
    │       ├── layout.tsx
    │       ├── dashboard/page.tsx
    │       ├── orders/page.tsx
    │       ├── audit/page.tsx
    │       ├── settings/strategy/page.tsx
    │       └── models/validation/page.tsx
    ├── components/                 # 汎用UIコンポーネント
    │   ├── actions/                #   Button, IconButton
    │   ├── data-display/           #   DataTable, KpiCard, StatusBadge, ...
    │   ├── feedback/               #   ConfirmationModal, Toast, ...
    │   ├── form/                   #   TextInput, SelectInput, ...
    │   ├── layouts/                #   Header, Sidebar
    │   └── skeleton/               #   CardSkeleton, TableSkeleton, ...
    ├── features/                   # 画面固有コンポーネント + フック
    │   ├── authentication/
    │   ├── dashboard/
    │   ├── orders/
    │   ├── audit/
    │   ├── strategy/
    │   └── modelValidation/
    ├── constants/                  # routes, screenIds, actionIds, messages
    ├── hooks/                      # useAuth, useToast, useTheme, ...
    ├── lib/                        # apiClient, authToken, formatters, ...
    ├── types/                      # api.ts, domain.ts, errors.ts, ui.ts
    ├── providers/                  # AuthProvider, ThemeProvider, ToastProvider, MswProvider
    └── mocks/                      # MSW handlers + data
```

### Sol (提案構成)

```
applications/frontend-sol/
├── moon.mod.json                   # MoonBit モジュール定義
├── package.json                    # npm (Hono サーバー、ビルドツール)
├── sol.config.ts                   # Sol 設定
├── worker.ts                       # Hono エントリポイント (認証ミドルウェア統合)
├── static/
│   ├── loader.js                   # Island ローダー
│   ├── sol-nav.js                  # CSR ナビゲーション
│   └── globals.css                 # デザインシステム CSS変数 (既存流用)
├── app/
│   ├── server/                     # サーバーコンポーネント (SSR)
│   │   ├── moon.pkg.json
│   │   ├── routes.mbt              # ルート定義 + RouterConfig
│   │   ├── layout.mbt              # ルートレイアウト + 認証レイアウト
│   │   ├── auth.mbt                # 認証ユーティリティ (FFI)
│   │   ├── api_client.mbt          # BFF API呼び出し (サーバーサイド)
│   │   ├── types.mbt               # ドメイン型 (struct/enum)
│   │   ├── constants.mbt           # 定数定義
│   │   ├── formatters.mbt          # 数値・日時フォーマッタ
│   │   │
│   │   ├── page_login.mbt          # SCR-000 ログイン
│   │   ├── page_dashboard.mbt      # SCR-001 ダッシュボード
│   │   ├── page_strategy.mbt       # SCR-002 戦略設定
│   │   ├── page_orders.mbt         # SCR-003 注文管理
│   │   ├── page_audit.mbt          # SCR-004 監査ログ
│   │   └── page_model_validation.mbt # SCR-005 モデル検証
│   │
│   ├── client/                     # クライアントコンポーネント (Islands)
│   │   ├── moon.pkg.json
│   │   ├── dashboard_controls.mbt  # 運用操作パネル
│   │   ├── order_actions.mbt       # 注文承認/却下/再送
│   │   ├── strategy_form.mbt       # 戦略設定フォーム
│   │   ├── filter_panel.mbt        # フィルタ操作
│   │   ├── confirmation_modal.mbt  # 確認モーダル
│   │   ├── toast.mbt               # トースト通知
│   │   ├── toggle_switch.mbt       # トグルスイッチ
│   │   └── theme_toggle.mbt        # テーマ切替
│   │
│   └── __gen__/                    # sol generate 自動生成
│       ├── client/
│       └── server/
```

### 構造上の主要な違い

| 観点 | Next.js | Sol |
|------|---------|-----|
| レンダリングモデル | CSR中心 (SPA) | SSR-first (Island Architecture) |
| コンポーネント分離 | すべてクライアント | サーバー / クライアント (Island) を明確に分離 |
| ルーティング | ファイルベース (App Router) | 宣言的定義 (`routes.mbt`) |
| ビルドシステム | webpack/Turbopack | Moon + Rolldown |
| パッケージ管理 | pnpm (npm) | Moon (mooncakes) + pnpm (TS部分) |
| エントリポイント | Next.js が自動管理 | Hono サーバー (`worker.ts`) |

---

## 2. 設定ファイルの対応表

| Next.js | Sol | 説明 |
|---------|-----|------|
| `package.json` | `package.json` + `moon.mod.json` | npm依存 + MoonBit依存を分離管理 |
| `next.config.ts` | `sol.config.ts` | フレームワーク設定 |
| `tsconfig.json` | `moon.pkg.json` (各パッケージ) | 型チェック・モジュール設定 |
| `.env.local` | 環境変数 / Secret Manager | API_BASE_URL 等 |
| `eslint.config.js` | `moon fmt` + `moon check` | Lint・フォーマット |

### next.config.ts → sol.config.ts

```typescript
// Next.js (現行)
const nextConfig: NextConfig = {
  reactCompiler: true,
};

// Sol (対応)
export default {
  islands: ["app/client"],
  routes: "app/server",
  output: "app/__gen__",
  runtime: "node",           // Cloud Run 向け
  client_auto_exports: false,
};
```

### moon.mod.json

```json
{
  "name": "alpha-mind/frontend",
  "version": "0.1.0",
  "deps": {
    "mizchi/sol": "0.8.0",
    "mizchi/luna": "0.13.0",
    "mizchi/signals": "0.6.3",
    "mizchi/mars": "0.3.9",
    "mizchi/js": "0.10.14"
  },
  "source": "app",
  "preferred-target": "js"
}
```

### moon.pkg.json (server)

```json
{
  "supported-targets": ["js"],
  "import": [
    { "path": "mizchi/luna", "alias": "luna" },
    { "path": "mizchi/sol", "alias": "sol" },
    { "path": "mizchi/sol/router", "alias": "router" },
    { "path": "mizchi/sol/middleware", "alias": "mw" },
    { "path": "mizchi/sol/action", "alias": "action" },
    { "path": "mizchi/signals", "alias": "signal" },
    { "path": "mizchi/sol/server_dom", "alias": "server_dom" },
    { "path": "mizchi/sol/styled", "alias": "styled" }
  ]
}
```

### moon.pkg.json (client)

```json
{
  "supported-targets": ["js"],
  "import": [
    { "path": "mizchi/luna/element", "alias": "element" },
    { "path": "mizchi/signals", "alias": "signal" },
    { "path": "mizchi/sol/action", "alias": "action" },
    { "path": "mizchi/js", "alias": "js" },
    { "path": "mizchi/js/dom", "alias": "js_dom" }
  ],
  "link": {
    "js": {
      "exports": [
        "dashboard_controls",
        "order_actions",
        "strategy_form",
        "filter_panel",
        "confirmation_modal",
        "toast",
        "toggle_switch",
        "theme_toggle"
      ],
      "format": "esm"
    }
  }
}
```

---

## 3. ルーティングの比較

### Next.js App Router (現行)

ファイルシステムベースの暗黙的ルーティング:

```
src/app/
├── page.tsx                           → /         (→ /dashboard リダイレクト)
├── login/page.tsx                     → /login
└── (authenticated)/                   → Route Group (URLに影響しない)
    ├── layout.tsx                     → 認証ガード + Header/Sidebar
    ├── dashboard/page.tsx             → /dashboard
    ├── orders/page.tsx                → /orders
    ├── audit/page.tsx                 → /audit
    ├── settings/strategy/page.tsx     → /settings/strategy
    └── models/validation/page.tsx     → /models/validation
```

### Sol 宣言的ルーティング (提案)

```moonbit
pub fn routes() -> Array[@router.SolRoutes] {
  [
    @router.SolRoutes::WithMiddleware(
      middleware=[@mw.security_headers(), @mw.logger()],
      children=[
        // ログインページ (認証不要)
        @router.SolRoutes::Layout(segment="", layout=root_layout, children=[
          @router.SolRoutes::Page(
            path="/login",
            handler=@router.PageHandler(login_page),
            title="Login - alpha-mind",
            meta=[], revalidate=None, cache=None,
          ),
        ]),

        // 認証必須ページ群 (authenticated レイアウト)
        @router.SolRoutes::Layout(
          segment="",
          layout=authenticated_layout,   // 認証チェック + Header + Sidebar
          children=[
            // / → /dashboard リダイレクト (サーバーサイド)
            @router.SolRoutes::Get(
              path="/",
              handler=@router.ApiHandler(redirect_to_dashboard),
            ),
            @router.SolRoutes::Page(
              path="/dashboard",
              handler=@router.PageHandler(dashboard_page),
              title="Dashboard - alpha-mind",
              meta=[], revalidate=None, cache=None,
            ),
            @router.SolRoutes::Page(
              path="/orders",
              handler=@router.PageHandler(orders_page),
              title="Orders - alpha-mind",
              meta=[], revalidate=None, cache=None,
            ),
            @router.SolRoutes::Page(
              path="/audit",
              handler=@router.PageHandler(audit_page),
              title="Audit - alpha-mind",
              meta=[], revalidate=None, cache=None,
            ),
            @router.SolRoutes::Page(
              path="/settings/strategy",
              handler=@router.PageHandler(strategy_page),
              title="Strategy Settings - alpha-mind",
              meta=[], revalidate=None, cache=None,
            ),
            @router.SolRoutes::Page(
              path="/models/validation",
              handler=@router.PageHandler(model_validation_page),
              title="Model Validation - alpha-mind",
              meta=[], revalidate=None, cache=None,
            ),
          ],
        ),

        // BFF API プロキシ
        @router.SolRoutes::WithMiddleware(
          middleware=[@mw.cors()],
          children=[
            @router.SolRoutes::Get(
              path="/api/dashboard/summary",
              handler=@router.ApiHandler(api_dashboard_summary),
            ),
            @router.SolRoutes::Post(
              path="/api/operations/runtime",
              handler=@router.ApiHandler(api_operations_runtime),
            ),
            // ... 他のAPI
          ],
        ),
      ],
    ),
  ]
}
```

### 比較ポイント

| 観点 | Next.js App Router | Sol SolRoutes |
|------|-------------------|---------------|
| ルート定義方法 | ファイルシステム規約 | コードで宣言 (`routes.mbt`) |
| Route Group | `(authenticated)/` ディレクトリ | `Layout(segment="", ...)` |
| 動的パラメータ | `[param]/page.tsx` | `path="/@[user_id]"` |
| キャッチオール | `[...slug]/page.tsx` | `path="/docs/[...slug]"` |
| ミドルウェア | `middleware.ts` (グローバル) | `WithMiddleware` (ルート単位) |
| APIルート | `route.ts` | `Get` / `Post` バリアント |
| レイアウトネスト | 暗黙的 (ディレクトリ構造) | 明示的 (`Layout` ネスト) |
| リダイレクト | `redirect()` / `useRouter` | `ApiHandler` でHTTPリダイレクト |
| ISR | `revalidate` export | `revalidate=Some(秒数)` |

### 主要な違い

1. **明示性**: Sol はすべてのルートがコードで定義されるため、ルーティングの全体像が1ファイルで把握できる
2. **ミドルウェア粒度**: Sol は `WithMiddleware` でルートグループ単位の適用が可能。Next.js は `middleware.ts` でパスパターンマッチ
3. **型安全性**: Sol のルート定義は MoonBit の型チェックを受ける。ハンドラの型不一致はコンパイルエラー

---

## 4. レイアウト・認証ガードの比較

### Next.js (現行)

```tsx
// src/app/(authenticated)/layout.tsx
"use client";

export default function AuthenticatedLayout({ children }) {
  const { isAuthenticated, isLoading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!isLoading && !isAuthenticated) {
      router.push(ROUTES.LOGIN);
    }
  }, [isAuthenticated, isLoading, router]);

  if (isLoading || !isAuthenticated) {
    return <div>Loading...</div>;
  }

  return (
    <div className={styles.layout}>
      <Header />
      <Sidebar />
      <main className={styles.main}>{children}</main>
    </div>
  );
}
```

- クライアントサイドで認証チェック (useEffect)
- 未認証時はクライアントサイドリダイレクト
- ローディング中はフラッシュが発生する可能性あり

### Sol (提案)

```moonbit
/// 認証済みレイアウト — サーバーサイドで認証チェック
pub fn authenticated_layout(
  props : @router.PageProps,
  content : @server_dom.ServerNode,
) -> @server_dom.ServerNode raise Error {
  @server_dom.ServerNode::async_(async fn() {
    // サーバーサイドで認証チェック
    let session = get_session()
    match session {
      None =>
        // 未認証: ログインページへリダイレクト (302)
        @luna.raw_html(
          "<script>window.location.href='/login';</script>"
        )
      Some(user) => {
        let inner = content.resolve()
        div(class="app-layout", [
          // Header (SSR)
          header_component(user),
          div(class="app-body", [
            // Sidebar (SSR)
            sidebar_component(props),
            // メインコンテンツ
            main(class="main-content", [inner]),
          ]),
        ])
      }
    }
  })
}
```

### 比較ポイント

| 観点 | Next.js | Sol |
|------|---------|-----|
| 認証チェック場所 | クライアント (useEffect) | サーバー (SSR時) |
| 未認証時のリダイレクト | `router.push()` (CSR) | HTTP 302 or script redirect |
| ローディングフラッシュ | あり (CSR) | なし (SSR完了後に配信) |
| Header/Sidebar | React コンポーネント | SSR VNode (静的HTML) |
| キルスイッチ状態 | Context (クライアント状態) | サーバーサイドfetch + SSR |

**Sol の利点**: 認証チェックがサーバーサイドで完結するため、未認証ユーザーに対してページコンテンツが一瞬表示される問題がない。

---

## 5. 状態管理の比較

### Next.js: React Context + hooks

```
Provider Stack (RootLayout):
  MswProvider → ThemeProvider → AuthProvider → ToastProvider
    └── children

状態の種類:
├── AuthContext: user, isAuthenticated, killSwitchEnabled, login, logout
├── ThemeContext: theme ("light" | "dark"), toggleTheme
├── ToastContext: showToast(type, message)
└── 各画面フック: useDashboardSummary, useOrders, useAuditLogs, ...
```

各画面フックの実装パターン:

```typescript
// 例: useDashboardSummary.ts
function useDashboardSummary() {
  const [data, setData] = useState<DashboardSummary | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<ApiError | null>(null);

  const fetchSummary = useCallback(async () => {
    setLoading(true);
    try {
      const result = await apiClient<DashboardSummary>(API_ROUTES.DASHBOARD_SUMMARY);
      setData(result);
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { fetchSummary(); }, [fetchSummary]);

  return { data, loading, error, refetch: fetchSummary };
}
```

### Sol: Luna Signals (Fine-Grained Reactivity)

Sol ではサーバーコンポーネントとクライアントコンポーネント (Island) で状態管理のアプローチが異なる。

**サーバーコンポーネント** — 状態は不要 (リクエスト毎にデータfetch → SSR):

```moonbit
/// ダッシュボードページ — サーバーサイドでデータ取得してSSR
async fn dashboard_page(props : @router.PageProps) -> @server_dom.ServerNode {
  // サーバーサイドでBFF APIを呼び出し
  let summary = fetch_dashboard_summary()
  let session = get_session()
  let kill_switch = match session {
    Some(_) => fetch_kill_switch_status()
    None => false
  }
  // SSRでHTMLを生成 (Island を埋め込み)
  let content = [
    h1([text("Dashboard")]),
    // KPI カード群 (静的SSR)
    render_kpi_cards(summary),
    // 操作パネル (Island — クライアントでハイドレーション)
    @server_dom.client(
      @types.dashboard_controls(DashboardControlsProps::{
        runtime_state: summary.runtime_state,
        kill_switch_enabled: kill_switch,
      }),
      [render_dashboard_controls_fallback(summary)],
    ),
  ]
  @server_dom.ServerNode::sync(@luna.fragment(content))
}
```

**クライアントコンポーネント (Island)** — Signals で状態管理:

```moonbit
/// ダッシュボード操作パネル (Island)
pub fn dashboard_controls(props : DashboardControlsProps) -> DomNode {
  // Signal: リアクティブ状態
  let runtime_state = @signal.signal(props.runtime_state)
  let kill_switch = @signal.signal(props.kill_switch_enabled)
  let is_loading = @signal.signal(false)

  // Computed: 派生状態
  let can_operate = @signal.memo(fn() {
    not(kill_switch.get()) && not(is_loading.get())
  })

  // イベントハンドラ
  let handle_toggle_runtime = fn(_event) {
    is_loading.set(true)
    let new_state = if runtime_state.get() == "RUNNING" { "STOPPED" } else { "RUNNING" }
    post_runtime_action(new_state, fn(success) {
      if success { runtime_state.set(new_state) }
      is_loading.set(false)
    })
  }

  div(class="controls-panel", [
    // runtime_state.get() が変更されると自動的にDOMが更新される
    span([text_of(runtime_state)]),
    button(
      on=events().click(handle_toggle_runtime),
      [text("Toggle Runtime")],
    ),
  ])
}
```

### 比較表

| 観点 | Next.js (React) | Sol (Luna Signals) |
|------|-----------------|-------------------|
| リアクティビティ | Virtual DOM 差分検出 | Fine-Grained (Signal依存追跡) |
| グローバル状態 | Context API + Provider | サーバー状態 (SSR) + Island ローカルシグナル |
| データフェッチ | クライアント (useEffect) | サーバーサイド (SSR時) + Island (操作時) |
| 再レンダリング範囲 | コンポーネントツリー全体 | Signal依存ノードのみ |
| 状態の永続化 | sessionStorage / localStorage | Cookie (認証) + サーバー状態 |
| テーマ切替 | ThemeContext + CSS変数 | Island (theme_toggle) + CSS変数 |
| トースト通知 | ToastContext + Provider | Island (toast) + Signal |
| メモ化 | useMemo / useCallback / React Compiler | `@signal.memo` (自動追跡) |

### SSR-first による簡素化

Next.js では「データフェッチ → 状態更新 → 再レンダリング」のサイクルをクライアントで管理する必要がある。Sol ではページ表示に必要なデータはサーバーサイドでfetchし、SSR結果を配信する。インタラクティブな操作のみ Island + Signals で対応するため、クライアント側の状態管理が大幅に削減される。

---

## 6. コンポーネント設計の比較

### Next.js: React TSX

```tsx
// components/data-display/KpiCard.tsx
interface KpiCardProps {
  label: string;
  value: string;
  valueColor?: "profit" | "loss" | "neutral";
  subtitle?: string;
  icon?: ReactNode;
}

export function KpiCard({ label, value, valueColor, subtitle, icon }: KpiCardProps) {
  return (
    <div className={styles.card}>
      <div className={styles.header}>
        {icon && <span className={styles.icon}>{icon}</span>}
        <span className={styles.label}>{label}</span>
      </div>
      <div className={`${styles.value} ${styles[valueColor ?? "neutral"]}`}>
        {value}
      </div>
      {subtitle && <div className={styles.subtitle}>{subtitle}</div>}
    </div>
  );
}
```

### Sol: サーバーコンポーネント (VNode)

```moonbit
/// KPI カード — サーバーコンポーネント (静的HTML)
pub fn kpi_card(
  label~ : String,
  value~ : String,
  value_color~ : String = "neutral",  // "profit" | "loss" | "neutral"
  subtitle~ : String = "",
) -> @luna.Node[Unit, String] {
  div(class="kpi-card", [
    div(class="kpi-header", [
      span(class="kpi-label", [text(label)]),
    ]),
    div(
      class="kpi-value kpi-" + value_color,
      [text(value)],
    ),
    if subtitle != "" {
      div(class="kpi-subtitle", [text(subtitle)])
    } else {
      @luna.fragment([])
    },
  ])
}
```

### Sol: クライアントコンポーネント (Island)

```moonbit
/// トグルスイッチ — クライアントコンポーネント (インタラクティブ)
pub(all) struct ToggleSwitchProps {
  label : String
  initial_checked : Bool
  disabled : Bool
} derive(ToJson, FromJson)

pub fn toggle_switch(props : ToggleSwitchProps) -> DomNode {
  let checked = @signal.signal(props.initial_checked)

  let handle_change = fn(_event) {
    if not(props.disabled) {
      checked.update(fn(current) { not(current) })
    }
  }

  div(class="toggle-switch", [
    label(for_="toggle", [
      text(props.label),
      input(
        type_="checkbox",
        id="toggle",
        on=events().change(handle_change),
      ),
      span(class="toggle-slider", []),
    ]),
  ])
}
```

### コンポーネントの分類方針

Sol では、コンポーネントを **サーバー/クライアント** のどちらで動作させるかを明確に決定する必要がある:

| 分類 | 条件 | 例 |
|------|------|-----|
| **サーバーコンポーネント** | 表示のみ、イベントハンドラなし | KpiCard, StatusBadge, DataTable (表示), Header, Sidebar |
| **クライアントコンポーネント (Island)** | ユーザー操作、状態変更あり | Button (onClick), ToggleSwitch, ConfirmationModal, Toast, フォーム |
| **ハイブリッド** | SSR表示 + Island埋め込み | DashboardPage (SSR) + DashboardControls (Island) |

---

## 7. スタイリングの比較

### Next.js: CSS Modules

```css
/* Button.module.css */
.button {
  display: inline-flex;
  gap: 8px;
  border-radius: var(--radius-md);
  transition: 0.15s;
}
.primary {
  background-color: var(--color-accent);
  color: #ffffff;
}
```

```tsx
import styles from './Button.module.css';

<button className={`${styles.button} ${styles[variant]}`}>
  {children}
</button>
```

### Sol: Luna 公式 CSS 戦略 (3層構造)

Luna/Sol には**公式のCSS戦略**が設計文書 (ADR) として定義されている。CSS Modules の代わりに、以下の3層構造でスタイリングを行う。

> **参照**: `references/sol.mbt/.mooncakes/mizchi/luna/spec/luna/002-css-utilities.md` (ADR-002: Accepted)
> **参照**: `references/sol.mbt/.mooncakes/mizchi/luna/spec/luna/005-web-components.md` (ADR-005: Accepted)

#### 第1層: Atomic CSS ユーティリティ (`@luna/x/css`) — メイン手法

CSS-in-JS のランタイムオーバーヘッド、Tailwind のビルド依存、Tachyons の冗長性を踏まえ、**WASM-first のUIライブラリ向けに Atomic CSS ユーティリティ**が採用されている。

**設計原則**:
- **ゼロランタイムCSS解析**: クラス名はビルド時に生成
- **最小CSSサイズ**: 同一宣言は一度だけ出力 (DJB2ハッシュによる自動重複排除)
- **CSSプロパティ名をそのまま使用**: Tailwind のような独自語彙を覚える必要がない

**コア API** (`@css` モジュール):

```moonbit
/// 単一CSSプロパティ → ハッシュ化クラス名を返す
pub fn css(property : String, value : String) -> String
// @css.css("display", "flex") → "_swuc"

/// 複数CSSプロパティ → スペース区切りのクラス名を返す
pub fn styles(props : Array[(String, String)]) -> String
// @css.styles([("display", "flex"), ("gap", "1rem")]) → "_swuc _a1b2"

/// クラス名を結合
pub fn combine(classes : Array[String]) -> String
// @css.combine([flex, gap1]) → "_swuc _a1b2"
```

**擬似クラスサポート**:

```moonbit
@css.hover("background", "var(--color-accent-hover)")   // :hover
@css.focus("outline", "2px solid var(--color-accent)")   // :focus
@css.active("transform", "scale(0.98)")                  // :active
@css.on(":first-child", "margin-top", "0")               // 汎用
```

**メディアクエリ / レスポンシブ**:

```moonbit
@css.at_sm("padding", "1rem")           // min-width: 640px
@css.at_md("padding", "2rem")           // min-width: 768px
@css.at_lg("padding", "3rem")           // min-width: 1024px
@css.at_xl("padding", "4rem")           // min-width: 1280px
@css.dark("background", "#0b0f19")      // prefers-color-scheme: dark
```

**CSS 生成**:

```moonbit
// 登録された全スタイルからCSSを生成
@css.generate_full_css()
// → "._swuc{display:flex}._a1b2{gap:1rem}._swuc:hover{background:...}@media(min-width:768px){._m0{padding:2rem}}"
```

**重複排除の仕組み** (DJB2ハッシュ):

```moonbit
// 同一宣言は常に同一クラス名を返す
let a = @css.css("display", "flex")  // → "_swuc"
let b = @css.css("display", "flex")  // → "_swuc" (同じ)
// CSSには1回だけ出力: ._swuc{display:flex}
```

**実用例** — TodoMVC スタイル定義 (`references/sol.mbt/.mooncakes/mizchi/luna/src/examples/todomvc/styles.mbt`):

```moonbit
// スタイルを定数として事前定義 (ゼロランタイム抽出可能)
pub let display_flex : String = @css.css("display", "flex")
pub let align_items_center : String = @css.css("align-items", "center")
pub let cursor_pointer : String = @css.css("cursor", "pointer")
pub let color_profit : String = @css.css("color", "var(--color-profit)")
pub let font_mono : String = @css.css("font-family", "var(--font-mono)")

// 条件付きクラス
pub fn when(condition : Bool, cls : String) -> String {
  if condition { cls } else { "" }
}

// 使用例
div(class=@css.combine([display_flex, align_items_center, when(is_active, color_profit)]), [...])
```

#### 第2層: Shadow DOM による Scoped CSS (Island)

Island Architecture では、Web Components の Declarative Shadow DOM によりスタイルを隔離する。

**SSR 出力**:

```html
<alpha-dashboard-controls>
  <template shadowrootmode="open">
    <style>
      :host { display: block; }
      .controls-panel { padding: 1rem; border: 1px solid var(--color-border); }
      .btn-danger { background: var(--color-loss); color: #fff; }
    </style>
    <div class="controls-panel">...</div>
  </template>
</alpha-dashboard-controls>
```

**MoonBit 側での定義**:

```moonbit
@server_dom.wc_island(
  "alpha-dashboard-controls",
  "/static/dashboard_controls.js",
  children,
  styles=dashboard_controls_scoped_css(),  // Shadow DOM 内に閉じるCSS
  state=initial_state_json,
  trigger=@luna.TriggerType::Load,
)
```

**利点**:
- スタイルが外部に漏れない (ネイティブブラウザ機能)
- Island 間のクラス名衝突が原理的に発生しない
- SSR で Declarative Shadow DOM として出力されるため、JS無効時でも正しく表示される

#### 第3層: ビルド時CSS最適化

Luna には CSS サイズ削減のための最適化パイプラインが用意されている:

| ツール | 機能 | ファイル |
|--------|------|---------|
| CSS Optimizer | 頻繁に共起するAtomicクラスを統合 (共起行列分析) | `luna/js/luna/tests/css-optimizer.test.ts` |
| Scoped CSS Minifier | クラス名マングリング + CSS圧縮 | `luna/experiments/css-minify/minify-scoped-css.js` |
| CSS Runtime (フォールバック) | SSR未抽出CSSのブラウザ側自動生成 | `luna/js/luna/tests/css-runtime.test.ts` |
| Sol CSS Processor | SSG/SSR用CSS処理・テーマ変数生成 | `sol/src/ssg/generator/css_processor.mbt` |

#### globals.css のCSS変数との統合

既存の `globals.css` のCSS変数体系はそのまま `@css` から参照可能:

```moonbit
// globals.css の CSS変数を Atomic CSS から参照
let surface_bg = @css.css("background", "var(--color-surface)")
let accent_color = @css.css("color", "var(--color-accent)")
let border_standard = @css.css("border", "1px solid var(--color-border)")
let radius_md = @css.css("border-radius", "var(--radius-md)")
let shadow_md = @css.css("box-shadow", "var(--shadow-md)")
let font_mono = @css.css("font-family", "var(--font-mono)")

// ダークモードはCSS変数のオーバーライドで対応 (globals.css の .dark クラス)
// @css.dark() でメディアクエリベースのダークモードも可能
let dark_surface = @css.dark("background", "var(--color-surface)")
```

### 比較表

| 観点 | Next.js CSS Modules | Sol (Luna Atomic CSS + Shadow DOM) |
|------|-------------------|-----|
| スコーピング | 自動 (ビルド時ハッシュ) | Atomic CSS (DJB2ハッシュ) + Shadow DOM |
| CSS変数 | `globals.css` で定義 | `globals.css` をそのまま参照可能 |
| ダークモード | `.dark` クラス切替 | CSS変数切替 + `@css.dark()` |
| 型安全性 | なし (`styles.xxx` は string) | 部分的 (MoonBit 定数で管理可能) |
| Dead Code Elimination | ビルド時 (未使用CSS除去) | 自動 (使用した宣言のみ生成) |
| 重複排除 | なし (同一プロパティが複数出力) | 自動 (DJB2ハッシュで同一宣言 = 同一クラス) |
| 擬似クラス | CSS ファイルに直接記述 | `@css.hover()`, `@css.focus()` 関数 |
| レスポンシブ | CSS ファイルにメディアクエリ記述 | `@css.at_sm()`, `@css.at_md()` 関数 |
| CSSサイズ | コンポーネント数に比例 | 宣言数に比例 (同一宣言は1回のみ) |
| ホットリロード | Turbopack 自動 | `sol dev` が再ビルド |
| Island 間隔離 | — (SPA のため不要) | Shadow DOM (ネイティブ隔離) |

### 既知の制限と注意点

| 制限 | 詳細 | 参照 |
|------|------|------|
| 動的クラスの追跡 | `class={condition() ? "a" : "b"}` がSignal変化時に更新されない | [luna.mbt Issue #7](https://github.com/mizchi/luna.mbt/issues/7) (OPEN) |
| プロパティ名の検証 | `@css.css()` の第1引数は文字列のため、タイポはコンパイル時に検出されない | ADR-002 Negative consequences |
| ショートハンドプロパティ | `margin: 1rem 2rem` 等は使えるが、個別指定が推奨 | ADR-002 |
| クラス名の可読性 | `_swuc` のようなハッシュ名のためデバッグ時に直感的でない | `generate_css_pretty()` で開発時は可読形式出力可能 |

### 移行方針

1. `globals.css` を `static/globals.css` として配置し、CSS変数体系を維持
2. 各コンポーネントのスタイルを `@css.css()` ベースの Atomic CSS に移行 (styles.mbt にまとめて定義)
3. Island コンポーネントは Shadow DOM の Scoped CSS でスタイル隔離
4. `@css.generate_full_css()` の出力を `<head>` 内の `<style>` タグで配信

---

## 8. APIクライアントの比較

### Next.js: fetch ラッパー (クライアントサイド)

```typescript
// lib/apiClient.ts
async function apiClient<T>(path: string, options?: ApiOptions): Promise<T> {
  const token = getAccessToken();
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    ...(token && { Authorization: `Bearer ${token}` }),
    "X-Trace-Id": generateTraceId(),
    ...(options?.screenId && { "X-Screen-Id": options.screenId }),
    ...(options?.actionId && { "X-Action-Id": options.actionId }),
  };

  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: options?.method ?? "GET",
    headers,
    body: options?.body ? JSON.stringify(options.body) : undefined,
  });

  if (!response.ok) {
    const problem = await response.json();
    throw new ApiError(problem);
  }
  if (response.status === 204) return undefined as T;
  return response.json();
}
```

### Sol: サーバーサイド fetch (MoonBit JS FFI)

Sol の SSR-first アーキテクチャでは、データフェッチはサーバーサイドで行う:

```moonbit
/// BFF API クライアント (サーバーサイド)

/// fetch ラッパー (JS FFI)
extern "js" fn fetch_json(url : String, options : String) -> @core.Any =
  #| async (url, options) => {
  #|   const opts = JSON.parse(options);
  #|   const res = await fetch(url, opts);
  #|   if (!res.ok) {
  #|     const body = await res.text();
  #|     throw new Error(JSON.stringify({ status: res.status, body }));
  #|   }
  #|   if (res.status === 204) return null;
  #|   return await res.json();
  #| }

/// BFF API Base URL
extern "js" fn get_api_base_url() -> String =
  #| () => process.env.API_BASE_URL || "http://localhost:8080"

/// トレースID生成
extern "js" fn generate_trace_id() -> String =
  #| () => "trc_" + Date.now().toString(36) + "_" + Math.random().toString(36).slice(2, 10)

/// ダッシュボードサマリー取得
pub fn fetch_dashboard_summary() -> @core.Any raise Error {
  let url = get_api_base_url() + "/dashboard/summary"
  let session = get_session()
  let token = match session {
    Some(_) => get_access_token()
    None => ""
  }
  let options_json =
    "{\"method\":\"GET\",\"headers\":{\"Authorization\":\"Bearer " + token + "\",\"X-Trace-Id\":\"" + generate_trace_id() + "\",\"X-Screen-Id\":\"SCR-001\"}}"
  fetch_json(url, options_json)
}
```

**クライアントサイド (Island 内) の場合**: Server Actions を使用

```moonbit
/// Island からのAPI呼び出しは Server Action 経由
let approve_order_handler = @action.ActionHandler(async fn(ctx) {
  let order_id = get_field(parse_json(ctx.body), "orderId")
  // サーバーサイドでBFF APIを呼び出し
  let result = call_bff_api("/orders/" + order_id + "/approve", "POST", "")
  match result {
    Ok(_) => @action.ActionResult::ok(@sol.json_obj([("success", @core.any(true))]))
    Err(error) => @action.ActionResult::server_error(error.to_string())
  }
})
```

### 比較表

| 観点 | Next.js | Sol |
|------|---------|-----|
| データフェッチ場所 | クライアント (ブラウザ) | サーバー (SSR時) |
| 認証トークン管理 | sessionStorage (ブラウザ) | Cookie / サーバーサイドセッション |
| APIリクエストヘッダー | X-Trace-Id, X-Screen-Id, X-Action-Id | 同一 (サーバーサイドで付与) |
| エラーハンドリング | ApiError クラス + catch | MoonBit Error型 + pattern match |
| CORS | ブラウザが自動処理 | 不要 (同一オリジン or サーバー間通信) |
| Island からのAPI呼び出し | 直接 fetch | Server Actions 経由 |

### Sol の利点

- **CORSが不要**: BFF APIへの呼び出しがサーバー間通信になるため
- **トークン露出なし**: 認証トークンがブラウザに送信されない
- **レイテンシ削減**: サーバー間通信は同一ネットワーク内で高速

---

## 9. 型定義の比較

### Next.js: TypeScript

```typescript
// types/api.ts
type OrderStatus = "PROPOSED" | "APPROVED" | "REJECTED" | "EXECUTED" | "FAILED";
type OrderSide = "BUY" | "SELL";

interface OrderSummary {
  orderId: string;
  symbol: string;
  side: OrderSide;
  qty: number;
  status: OrderStatus;
  createdAt: string;
}

interface OrderDetail extends OrderSummary {
  reasonCode?: string;
  traceId?: string;
  brokerOrderId?: string;
  updatedAt?: string;
}

// types/errors.ts
class ApiError extends Error {
  status: number;
  reasonCode: ReasonCode;
  traceId?: string;
  retryable: boolean;
  get isAuthError(): boolean { return this.status === 401; }
  get isKillSwitchError(): boolean { return this.reasonCode === "KILL_SWITCH_ENABLED"; }
}
```

### Sol: MoonBit struct/enum

```moonbit
/// types.mbt — ドメイン型定義

/// 注文ステータス
pub enum OrderStatus {
  Proposed
  Approved
  Rejected
  Executed
  Failed
} derive(Eq, Show, ToJson, FromJson)

/// 注文方向
pub enum OrderSide {
  Buy
  Sell
} derive(Eq, Show, ToJson, FromJson)

/// 注文サマリー
pub struct OrderSummary {
  order_id : String
  symbol : String
  side : OrderSide
  quantity : Int
  status : OrderStatus
  created_at : String
} derive(ToJson, FromJson)

/// 注文詳細
pub struct OrderDetail {
  order_id : String
  symbol : String
  side : OrderSide
  quantity : Int
  status : OrderStatus
  created_at : String
  reason_code : String?      // Option型 (None | Some)
  trace_id : String?
  broker_order_id : String?
  updated_at : String?
} derive(ToJson, FromJson)

/// ランタイム状態
pub enum RuntimeState {
  Running
  Stopped
} derive(Eq, Show, ToJson, FromJson)

/// モデルステータス
pub enum ModelStatus {
  Candidate
  Approved
  Rejected
} derive(Eq, Show, ToJson, FromJson)

/// APIエラー (RFC 9457)
pub struct ProblemDetail {
  type_ : String
  title : String
  status : Int
  detail : String?
  instance : String?
  trace_id : String?
  reason_code : String
  retryable : Bool
} derive(ToJson, FromJson)

/// APIエラー判定
pub fn is_auth_error(problem : ProblemDetail) -> Bool {
  problem.status == 401
}

pub fn is_kill_switch_error(problem : ProblemDetail) -> Bool {
  problem.reason_code == "KILL_SWITCH_ENABLED"
}

/// ダッシュボードサマリー
pub struct DashboardSummary {
  pnl_today : Double
  pnl_total : Double
  max_drawdown : Double
  runtime_state : RuntimeState
  kill_switch_enabled : Bool
  latest_signal_at : String?
} derive(ToJson, FromJson)

/// 画面状態
pub enum ScreenState {
  Initial
  Loading
  Empty
  Error
  Disabled
} derive(Eq, Show)

/// テーマ
pub enum Theme {
  Light
  Dark
} derive(Eq, Show)
```

### 比較表

| 観点 | TypeScript | MoonBit |
|------|-----------|---------|
| String Literal Union | `"BUY" \| "SELL"` | `enum OrderSide { Buy; Sell }` |
| Optional フィールド | `field?: Type` | `field : Type?` (Option型) |
| 継承 / extends | `interface B extends A` | 不可。フィールドを再定義 |
| class メソッド | `class ApiError { get isAuth() }` | `pub fn is_auth_error(p : ProblemDetail) -> Bool` |
| ジェネリクス | `Array<T>` | `Array[T]` |
| 型ガード | `value is Type` | pattern match |
| derive 自動実装 | なし | `derive(Eq, Show, ToJson, FromJson)` |
| Null安全 | `?? / ?.` | `Option[T]` + pattern match |
| パターンマッチ | switch/if | `match` (網羅性チェック付き) |

### MoonBit の型安全上の利点

1. **網羅的パターンマッチ**: `match` 式で全バリアントの処理が必須。新規ステータス追加時にコンパイルエラーで漏れを検出
2. **Option型の強制**: `null` / `undefined` が型レベルで排除される
3. **derive による自動実装**: JSON シリアライズ/デシリアライズがボイラープレートなし

---

## 10. テスト・モックの比較

### Next.js: MSW + Vitest (予定)

```
テスト構成:
├── MSW (Mock Service Worker)
│   ├── browser.ts          → Service Worker セットアップ
│   ├── handlers.ts         → HTTP モックハンドラ
│   ├── data.ts             → モックデータ
│   └── init.ts             → 開発環境初期化
├── Vitest (予定)
│   ├── Unit: フック、ユーティリティ
│   └── Integration: API連携、画面振る舞い
└── Playwright (予定)
    └── E2E: 画面遷移、認証フロー
```

開発時のモック動作:

```typescript
// mocks/handlers.ts
export const handlers = [
  http.post("/auth/login", async ({ request }) => {
    const { email, password } = await request.json();
    if (email === "admin@alpha-mind.local" && password === "password") {
      return HttpResponse.json({
        accessToken: "mock-jwt-token",
        tokenType: "Bearer",
        expiresIn: 3600,
        user: MOCK_USER,
      });
    }
    return HttpResponse.json({ /* RFC 9457 error */ }, { status: 401 });
  }),
  http.get("/dashboard/summary", () => {
    return HttpResponse.json(MOCK_DASHBOARD);
  }),
  // ...
];
```

### Sol: MoonBit テスト + E2E

```
テスト構成:
├── MoonBit Unit Test (moon test)
│   ├── 型のシリアライズ/デシリアライズ
│   ├── ビジネスロジック (フォーマッタ、バリデータ)
│   ├── ルート定義の正当性
│   └── VNode構造のスナップショット
├── Playwright E2E
│   └── 画面遷移、認証フロー、操作
└── 開発サーバーモック
    └── Hono ミドルウェアでモックレスポンス
```

#### MoonBit ユニットテスト

```moonbit
test "OrderStatus の JSON ラウンドトリップ" {
  let status = OrderStatus::Proposed
  let json = status.to_json()
  let restored : OrderStatus = @json.from_json(json)
  assert_eq(status, restored)
}

test "is_auth_error は 401 で true を返す" {
  let problem = ProblemDetail::{
    type_: "about:blank",
    title: "Unauthorized",
    status: 401,
    detail: None,
    instance: None,
    trace_id: None,
    reason_code: "AUTH_INVALID_CREDENTIALS",
    retryable: false,
  }
  assert_true(is_auth_error(problem))
  assert_false(is_kill_switch_error(problem))
}

test "format_currency は通貨フォーマットする" {
  inspect(format_currency(1234567.89), content="1,234,567.89")
  inspect(format_currency(-500.0), content="-500.00")
}
```

#### 開発サーバーモック (worker.ts)

```typescript
// MSW の代替: Hono ミドルウェアでモック
import { Hono } from "hono";

const app = new Hono();

// 開発時のみモックミドルウェアを適用
if (process.env.NODE_ENV === "development") {
  app.post("/api/auth/login", async (c) => {
    const { email, password } = await c.req.json();
    if (email === "admin@alpha-mind.local" && password === "password") {
      return c.json({ accessToken: "mock-jwt-token", /* ... */ });
    }
    return c.json({ /* RFC 9457 */ }, 401);
  });

  app.get("/api/dashboard/summary", (c) => {
    return c.json(MOCK_DASHBOARD);
  });
  // ...
}
```

### 比較表

| 観点 | Next.js (MSW) | Sol |
|------|--------------|-----|
| 開発モック | MSW Service Worker (ブラウザ内) | Hono ミドルウェア (サーバーサイド) |
| ユニットテスト | Vitest | `moon test` |
| コンポーネントテスト | Vitest + Testing Library | VNode スナップショット (`inspect`) |
| E2E | Playwright | Playwright |
| プロパティテスト | なし (予定なし) | MoonBit QuickCheck |
| テスト実行 | `pnpm test` | `moon test --target js` |
| モックデータ管理 | `mocks/data.ts` | `worker.ts` 内 or 別ファイル |

### Sol のテスト戦略上の特徴

- **SSR出力のテスト**: サーバーコンポーネントの出力はHTML文字列としてスナップショットテスト可能
- **型安全なモック不要**: MoonBit の型システムが多くの不整合をコンパイル時に検出
- **Island単体テスト**: Island コンポーネントは独立した関数として単体テスト可能

---

## 11. 6画面すべての対応詳細

### SCR-000: 認証 (`/login`)

| 観点 | Next.js | Sol |
|------|---------|-----|
| コンポーネント | `LoginForm.tsx` (CSR) | `page_login.mbt` (SSR) + Island |
| 認証方式 | クライアント fetch → sessionStorage | Hono middleware + better-auth + Cookie |
| フォームバリデーション | クライアント (useState) | Island (Signal) |
| エラー表示 | useState → ErrorBanner | Signal → 動的テキスト更新 |
| リダイレクト | `router.push("/dashboard")` | HTTP 302 or `window.location.href` |

**Sol での実装方針**:

```moonbit
// page_login.mbt
async fn login_page(_props : @router.PageProps) -> @server_dom.ServerNode {
  // 既にログイン済みならリダイレクト
  if is_authenticated() {
    return @server_dom.ServerNode::sync(
      @luna.raw_html("<script>window.location.href='/dashboard';</script>")
    )
  }
  let content = [
    h1([text("alpha-mind")]),
    // ログインフォーム Island を埋め込み
    @server_dom.client(
      @types.login_form(LoginFormProps::{ action: "login" }),
      [render_login_form_fallback()],  // SSR フォールバック (no-JS対応)
    ),
  ]
  @server_dom.ServerNode::sync(@luna.fragment(content))
}
```

### SCR-001: ダッシュボード (`/dashboard`)

| 観点 | Next.js | Sol |
|------|---------|-----|
| データフェッチ | `useDashboardSummary` (CSR) | SSR時にサーバーサイドfetch |
| KPIカード | `KpiCard` コンポーネント (CSR) | サーバーコンポーネント (静的HTML) |
| 操作パネル | ボタン群 + useConfirmation | Island `dashboard_controls` |
| キルスイッチ | AuthContext 同期 | サーバー状態 + Island |
| リアルタイム更新 | setInterval (予定) | CSR ナビゲーション再取得 or Island ポーリング |

**Sol での実装方針**:

サーバーサイドでデータを取得し、KPIカードは静的HTMLとしてSSR。操作パネルのみ Island としてハイドレーション。

```
SSR部分:
├── KPIカード群 (PnL Today, PnL Total, MaxDrawdown, Runtime State)
├── 最新シグナル情報
└── [Island 埋め込み] dashboard_controls
    ├── 運用開始/停止ボタン
    ├── 手動サイクル実行ボタン
    └── Kill Switch トグル
```

### SCR-002: 戦略設定 (`/settings/strategy`)

| 観点 | Next.js | Sol |
|------|---------|-----|
| データフェッチ | `useStrategySettings` (CSR) | SSR時にサーバーサイドfetch |
| フォーム | React controlled inputs | Island `strategy_form` (Signals) |
| バリデーション | クライアント useState | Signal + computed validation |
| 保存 | PUT /settings/strategy (CSR) | Server Action |
| リセット | setState(初期値) | Signal.set(初期値) |

**Sol での実装方針**:

設定値の表示はSSR。フォーム操作は Island として実装。保存は Server Action 経由。

```
SSR部分:
├── ページヘッダー
└── [Island 埋め込み] strategy_form
    ├── リバランス頻度選択
    ├── 対象銘柄リスト (追加/削除)
    ├── リスク制限設定 (NumberInput群)
    └── 保存/リセットボタン
```

### SCR-003: 注文管理 (`/orders`)

| 観点 | Next.js | Sol |
|------|---------|-----|
| 一覧表示 | DataTable + useOrders (CSR) | SSR テーブル + Island フィルタ |
| フィルタ | useState → refetch | Island `filter_panel` → CSR ナビゲーション |
| 詳細パネル | 右側 DetailPanel (CSR) | Island `order_detail_panel` |
| 承認/却下/再送 | fetch + useConfirmation | Server Action + `confirmation_modal` Island |
| ページネーション | "さらに読み込む" (cursor) | クエリパラメータ + SSR再取得 |

**Sol での実装方針**:

注文一覧はSSRテーブルとして配信。フィルタ変更時はCSRナビゲーション (`sol_link` + クエリパラメータ) でページを再取得。詳細パネルと操作ボタンは Island。

```
SSR部分:
├── [Island 埋め込み] filter_panel (Status, Symbol, DateRange)
├── 注文テーブル (SSR)
│   ├── ヘッダー行
│   └── データ行 (クリッカブル)
├── ページネーションリンク (SSR)
└── [Island 埋め込み] order_actions
    ├── 詳細パネル
    ├── 承認/却下/再送ボタン
    └── 却下理由入力
```

### SCR-004: 監査ログ (`/audit`)

| 観点 | Next.js | Sol |
|------|---------|-----|
| 一覧表示 | DataTable + useAuditLogs (CSR) | SSR テーブル + Island フィルタ |
| フィルタ | TraceId, EventType, DateRange (CSR) | Island `filter_panel` |
| 詳細パネル | DetailPanel + payload表示 | SSR or Island |
| TraceId コピー | useClipboard | Island (JS FFI `navigator.clipboard`) |
| ページネーション | cursor ベース (CSR) | クエリパラメータ + SSR |

**Sol での実装方針**:

SCR-003 と類似構造。テーブル表示はSSR、フィルタと詳細操作は Island。

### SCR-005: モデル検証 (`/models/validation`)

| 観点 | Next.js | Sol |
|------|---------|-----|
| 一覧表示 | DataTable + useModelValidation | SSR テーブル |
| フィルタ | Status フィルタ (CSR) | Island `filter_panel` |
| 詳細表示 | メトリクス表示 (CSR) | SSR (数値表示は静的) |
| 昇格/差し戻し | fetch + useConfirmation | Server Action + `confirmation_modal` Island |

**Sol での実装方針**:

メトリクス表示は `font-mono` クラスを適用したSSR。操作ボタンのみ Island。

---

## 12. 自作が必要なコンポーネント一覧

Sol には React のようなコンポーネントエコシステムがないため、すべてのUIコンポーネントを自作する必要がある。

### サーバーコンポーネント (SSR VNode ヘルパー)

表示のみでインタラクティビティが不要なコンポーネント:

| コンポーネント | 元ファイル | 工数目安 | 備考 |
|--------------|-----------|---------|------|
| `kpi_card` | KpiCard.tsx | 小 | 静的表示。CSS変数で色分け |
| `status_badge` | StatusBadge.tsx | 小 | ステータス文字列 → CSS クラスマッピング |
| `data_table` | DataTable.tsx | 中 | ジェネリクスなし。画面ごとに個別実装 |
| `detail_panel` | DetailPanel.tsx | 小 | label-value ペアの一覧表示 |
| `metric_panel` | MetricPanel.tsx | 小 | 数値表示パネル |
| `empty_state` | EmptyState.tsx | 小 | メッセージ表示のみ |
| `header_component` | Header.tsx | 中 | ブランド、ユーザー情報、テーマトグル (Island) |
| `sidebar_component` | Sidebar.tsx | 中 | ナビゲーションリンク (`sol_link`) |
| `card_skeleton` | CardSkeleton.tsx | 小 | SSR では不要 (サーバーで完結) |
| `table_skeleton` | TableSkeleton.tsx | 小 | SSR では不要 |

### クライアントコンポーネント (Island)

ユーザー操作が必要なコンポーネント:

| コンポーネント | 元ファイル | 工数目安 | 備考 |
|--------------|-----------|---------|------|
| `login_form` | LoginForm.tsx | 中 | フォーム入力 + バリデーション + Server Action |
| `dashboard_controls` | DashboardPage.tsx (一部) | 大 | 運用操作 + 確認モーダル + API呼び出し |
| `strategy_form` | StrategyPage.tsx (一部) | 大 | 複数フォーム + バリデーション + 保存 |
| `order_actions` | OrdersPage.tsx (一部) | 大 | 承認/却下/再送 + 理由入力 + Server Action |
| `filter_panel` | 各画面のフィルタ部分 | 中 | 共通化可能。日付範囲、セレクト、テキスト |
| `confirmation_modal` | ConfirmationModal.tsx | 中 | モーダルダイアログ + フォーカストラップ |
| `toast` | Toast.tsx | 中 | 通知表示 + 自動消去タイマー |
| `toggle_switch` | ToggleSwitch.tsx | 小 | チェックボックス + Signal |
| `theme_toggle` | ThemeProvider.tsx (一部) | 小 | ダーク/ライト切替 + localStorage |
| `button` | Button.tsx | 小 | バリアント + ローディング状態 |
| `text_input` | TextInput.tsx | 小 | Signal バインディング |
| `select_input` | SelectInput.tsx | 小 | Signal バインディング |
| `number_input` | NumberInput.tsx | 小 | Signal バインディング + 範囲バリデーション |
| `date_range_picker` | DateRangePicker.tsx | 中 | 2つの日付入力 + Signal |
| `retry_banner` | RetryBanner.tsx | 小 | リトライボタン + ローディング |

### 必要な JS FFI 関数

| 関数 | 用途 |
|------|------|
| `fetch_json` | サーバーサイド HTTP リクエスト |
| `get_access_token` | Cookie / セッションからトークン取得 |
| `generate_trace_id` | トレースID生成 |
| `get_timestamp` | ISO8601 タイムスタンプ |
| `parse_json` / `stringify_json` | JSON パース/シリアライズ |
| `get_field` | Any オブジェクトのフィールドアクセス |
| `redirect_to` | クライアントサイドリダイレクト |
| `clipboard_write` | クリップボードコピー |
| `local_storage_get` / `set` | localStorage 操作 |
| `set_timeout` | タイマー |
| `format_number` | Intl.NumberFormat ラッパー |
| `format_date` | Intl.DateTimeFormat ラッパー |

### 工数サマリー

| カテゴリ | コンポーネント数 | 工数目安 |
|---------|---------------|---------|
| サーバーコンポーネント | 10 | 小〜中 |
| クライアントコンポーネント (Island) | 15 | 小〜大 |
| JS FFI 関数 | 12 | 小 |
| CSS移行 | globals.css + Atomic CSS styles.mbt | 中 |
| **合計** | **37要素** | - |

---

## 13. 移行ロードマップ

### Phase 0: 基盤構築

**目標**: Sol プロジェクトのスケルトン + デザインシステム移植

| タスク | 詳細 |
|--------|------|
| プロジェクト作成 | `sol new frontend-sol --user alpha-mind` |
| 依存関係設定 | `moon.mod.json`, `sol.config.ts` |
| globals.css 配置 | `static/globals.css` に既存CSS変数をコピー |
| styles.mbt 作成 | `@css.css()` でコンポーネントスタイルを Atomic CSS 定数として定義 |
| Hono エントリポイント | `worker.ts` 作成 |
| JS FFI 基盤 | `fetch_json`, `parse_json`, `generate_trace_id` 等 |
| 型定義 | `types.mbt` に全ドメイン型を定義 |
| 定数定義 | `constants.mbt` にルート、スクリーンID等を定義 |

### Phase 1: 認証 + レイアウト

**目標**: ログインからダッシュボードまでの基本フロー

| タスク | 詳細 |
|--------|------|
| 認証ミドルウェア | `worker.ts` に認証処理を実装 (better-auth or カスタム) |
| `auth.mbt` | セッション取得 FFI |
| `root_layout` | ルートレイアウト (HTML構造) |
| `authenticated_layout` | 認証チェック + Header + Sidebar |
| `page_login.mbt` | ログインページ (SSR) |
| `login_form` Island | フォーム入力 + 認証API呼び出し |
| `theme_toggle` Island | ダーク/ライトモード切替 |

### Phase 2: ダッシュボード

**目標**: SCR-001 完全実装

| タスク | 詳細 |
|--------|------|
| `page_dashboard.mbt` | SSR ページ (KPIカード群) |
| `kpi_card` ヘルパー | サーバーコンポーネント |
| BFF API クライアント | `/dashboard/summary` fetch |
| `dashboard_controls` Island | 運用操作パネル |
| `confirmation_modal` Island | 確認ダイアログ |
| `toast` Island | 通知表示 |
| Server Actions | runtime toggle, kill switch, manual cycle |

### Phase 3: 注文管理 + 監査ログ

**目標**: SCR-003, SCR-004 実装

| タスク | 詳細 |
|--------|------|
| `filter_panel` Island | 共通フィルタコンポーネント |
| `data_table` ヘルパー | サーバーコンポーネント (SSR テーブル) |
| `page_orders.mbt` | 注文一覧 + 詳細 |
| `order_actions` Island | 承認/却下/再送操作 |
| `page_audit.mbt` | 監査ログ一覧 + 詳細 |
| Server Actions | 注文操作 API |
| ページネーション | クエリパラメータベース |

### Phase 4: 戦略設定 + モデル検証

**目標**: SCR-002, SCR-005 実装

| タスク | 詳細 |
|--------|------|
| `page_strategy.mbt` | 戦略設定ページ |
| `strategy_form` Island | 設定フォーム全体 |
| `page_model_validation.mbt` | モデル検証ページ |
| モデル操作 Server Actions | 昇格/差し戻し |

### Phase 5: 品質・最適化

**目標**: テスト、アクセシビリティ、パフォーマンス

| タスク | 詳細 |
|--------|------|
| MoonBit ユニットテスト | 型、フォーマッタ、バリデータ |
| Playwright E2E | 全画面の主要フロー |
| アクセシビリティ | `aria-*` 属性、キーボードナビゲーション |
| パフォーマンス計測 | Lighthouse、SSR レイテンシ |
| エラーハンドリング | 全API呼び出しの異常系対応 |

### Phase 間の依存関係

```
Phase 0 (基盤)
  └─→ Phase 1 (認証 + レイアウト)
        └─→ Phase 2 (ダッシュボード)
              ├─→ Phase 3 (注文 + 監査)
              └─→ Phase 4 (戦略 + モデル)
                    └─→ Phase 5 (品質)
```

### リスクと注意点

| リスク | 影響 | 対策 |
|--------|------|------|
| MoonBit/Sol の成熟度 | APIブレイキングチェンジ | Sol のバージョンをピン留め、`references/` で管理 |
| Island 間の状態共有 | グローバル状態管理が困難 | `globalThis` 経由 or SSR再取得で対応 |
| 動的クラスの追跡 (luna #7) | Signal変化時にクラス更新されない | 回避策の採用 or Issue 解決を待つ |
| JS FFI の型安全性 | ランタイムエラー | FFI関数を最小限にし、テストで検証 |
| エコシステムの小ささ | ライブラリ不足 | 必要なものは自作 + JS FFI で補完 |
| デバッグツール | Source Map 対応が限定的 | `console.log` ベース + MoonBit テスト強化 |

---

## 付録: 開発コマンド対応表

| 操作 | Next.js | Sol |
|------|---------|-----|
| 依存インストール | `pnpm install` | `pnpm install && moon install` |
| 開発サーバー | `pnpm dev` | `sol dev` (port 7777) |
| ビルド | `pnpm build` | `sol build` |
| 本番起動 | `pnpm start` | `sol serve` |
| Lint | `pnpm lint` | `moon check --target js` |
| フォーマット | (Prettier) | `moon fmt` |
| テスト | `pnpm test` | `moon test --target js` |
| クリーン | `rm -rf .next` | `sol clean` |
| デプロイ | Vercel / Cloud Run | `sol deploy` (Cloudflare) or Cloud Run |
