# Sol フレームワーク 実装ガイド

Sol (MoonBit SSR/SSG フレームワーク) を alpha-mind プロジェクトで使用する際の環境構築手順、遭遇した問題と解決策を記録する。

---

## 1. 前提条件

| ツール | バージョン | 用途 |
|--------|-----------|------|
| Node.js | 24+ | Sol ランタイム (Hono サーバー) |
| pnpm | 10+ | npm パッケージ管理 |
| MoonBit (`moon`) | 0.1.x | MoonBit コンパイラ・ビルドツール |

---

## 2. 環境構築

### 2.1 MoonBit ツールチェーンのインストール

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
```

インストール後、`~/.moon/bin` に PATH を通す。

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon version  # moon 0.1.20260209 等が表示されること
```

### 2.2 Sol CLI のビルド（重要）

**npm 公開版 (`npx @luna_ui/sol`) は使用しない。** 公開版のテンプレートは古いパッケージ構成（`mizchi/luna/sol/router`）を生成し、依存解決に失敗する。

リファレンスリポジトリから CLI をビルドして使用する。

```bash
cd references/sol.mbt

# 依存インストール
pnpm install
moon update

# CLI ビルド（debug モード）
moon build --target js
# => _build/js/debug/build/cli/cli.js が生成される
```

以降の `sol` コマンドはすべて以下で実行する。

```bash
node /path/to/references/sol.mbt/_build/js/debug/build/cli/cli.js <command>
```

> **背景**: Sol は `mizchi/sol` として `mizchi/luna` から分離された独立パッケージだが、npm 公開版のテンプレートはこの分離前の構成（`mizchi/luna: 0.0.1` + `mizchi/luna/sol/router`）をハードコードしている。ローカルビルド版は正しい構成（`mizchi/sol: 0.8.0` + `mizchi/luna: 0.13.0` + `mizchi/sol/router`）を生成する。

### 2.3 プロジェクト生成

```bash
cd applications

# プロジェクト作成
node /path/to/sol-cli/cli.js new frontend-sol --user alpha-mind

cd frontend-sol

# npm 依存インストール
pnpm install

# MoonBit 依存インストール
moon update
```

### 2.4 生成されるプロジェクト構造

```
frontend-sol/
├── moon.mod.json          # MoonBit モジュール定義（依存パッケージ）
├── package.json           # npm パッケージ定義（hono, rolldown）
├── sol.config.json        # Sol 設定（islands, routes, output）
├── static/                # 静的ファイル（loader.js 等）
│   └── loader.js          # Island hydration ローダー
├── app/
│   ├── client/            # クライアントコンポーネント（Island）
│   │   ├── counter.mbt    #   例: カウンターコンポーネント
│   │   └── moon.pkg       #   パッケージ定義
│   ├── layout/            # レイアウト（サーバーコンポーネント）
│   │   ├── layout.mbt     #   HTML 構造・head 定義
│   │   └── moon.pkg       #   パッケージ定義
│   ├── server/            # ルート定義・ページハンドラ
│   │   ├── routes.mbt     #   ルーティング・ページ定義
│   │   └── moon.pkg       #   パッケージ定義
│   └── __gen__/           # 自動生成（sol generate で再生成）
│       ├── types/         #   Props 型定義
│       ├── client/        #   hydrate ラッパー
│       └── server/        #   サーバーエントリポイント
└── .sol/                  # ビルド成果物（sol dev/build で生成）
    └── dev/
        ├── static/        #   バンドル済みクライアント JS
        ├── client/        #   クライアントエントリ
        └── server/        #   サーバー JS
```

### 2.5 正しい依存関係

`moon.mod.json` の依存パッケージは以下であること。

```json
{
  "name": "alpha-mind/frontend-sol",
  "version": "0.1.0",
  "deps": {
    "mizchi/sol": "0.8.0",
    "mizchi/mars": "0.3.9",
    "mizchi/luna": "0.13.0",
    "mizchi/signals": "0.6.3",
    "mizchi/js": "0.10.14",
    "mizchi/npm_typed": "0.1.11"
  },
  "source": "app",
  "preferred-target": "js"
}
```

> **注意**: `mizchi/luna: "0.0.1"` は古い。`0.13.0` が必要。

### 2.6 開発サーバーの起動

```bash
cd applications/frontend-sol
node /path/to/sol-cli/cli.js dev
# => http://localhost:7777 でアクセス可能
```

内部で実行される処理:

1. `sol generate` — `__gen__/` ディレクトリを生成
2. `moon build --target js` — MoonBit コンパイル
3. rolldown でクライアント JS をバンドル
4. Hono サーバー起動 (port 7777)
5. HMR WebSocket 起動 (port 7877)

---

## 3. 解決済みの問題

### 3.1 `sol dev` で `Cannot find import 'mizchi/luna/sol/router'`

| 項目 | 内容 |
|------|------|
| **発生状況** | `npx @luna_ui/sol new` で生成したプロジェクトで `sol dev` を実行 |
| **エラー** | `Cannot find import 'mizchi/luna/sol/router'` |
| **根本原因** | npm 公開版の `sol new` テンプレートが古い依存構成を生成する |
| **詳細** | テンプレートが `mizchi/luna: 0.0.1` を指定するが、v0.0.1 には `sol/router`, `sol/action` サブパッケージが存在しない。現行の Sol は `mizchi/sol` として Luna から分離されており、正しいインポートパスは `mizchi/sol/router` |

**解決策**: リファレンスリポジトリ (`references/sol.mbt`) から Sol CLI をビルドし、それを使ってプロジェクトを生成する（→ セクション 2.2）。

**正しいインポートパス対応表**:

| 古い（npm 公開版） | 正しい（ローカルビルド版） |
|--------------------|--------------------------|
| `mizchi/luna/sol` | `mizchi/sol` |
| `mizchi/luna/sol/router` | `mizchi/sol/router` |
| `mizchi/luna/sol/action` | `mizchi/sol/action` |

### 3.2 カウンターの +/- ボタンが反応しない（Island hydration が実行されない）

| 項目 | 内容 |
|------|------|
| **発生状況** | `sol dev` でサーバーは起動し、カウンター UI は SSR で表示されるが、ボタンをクリックしてもカウンターが変化しない |
| **根本原因** | 2つの問題が複合していた |

#### 原因 1: `static/loader.js` がスタブ

生成されたプロジェクトの `static/loader.js` は以下のスタブのみだった。

```javascript
// 生成されたスタブ（機能しない）
(function(){ window.__LUNA_STATE__ = {}; window.__LUNA_SCAN__ = function(){}; })();
```

本来は luna loader v4（`[luna:url]` 属性をスキャンし、動的 import で Island モジュールを読み込み、hydrate 関数を呼ぶ）が必要。

**解決策**: `references/sol.mbt/examples/sol_auth/static/loader.js` から本物の loader をコピー。

```bash
cp references/sol.mbt/examples/sol_auth/static/loader.js \
   applications/frontend-sol/static/loader.js
```

#### 原因 2: `layout.mbt` の `head()` に loader script タグがない

```moonbit
// 修正前（loader 読み込みなし）
pub fn head() -> String {
  default_style
}

// 修正後（loader 読み込みあり）
let loader_script : String = "<script type=\"module\" src=\"/static/loader.js\"></script>"

pub fn head() -> String {
  default_style + loader_script
}
```

#### Island hydration の仕組み

```
SSR HTML                     Client
┌─────────────────────┐     ┌──────────────────────┐
│ <div luna:id="..."   │     │ loader.js             │
│      luna:url="..."  │────→│  scan [luna:url]       │
│      luna:state="..."│     │  import(url)           │
│      luna:client-    │     │  mod.hydrate(el,state) │
│        trigger="load"│     │  → DOM にイベント接続   │
│ >                    │     └──────────────────────┘
│   <button>+</button> │
│ </div>               │
└─────────────────────┘
```

1. サーバーが `luna:*` 属性付きの HTML を出力
2. `loader.js` が DOM を走査し `[luna:url]` 要素を検出
3. `luna:client-trigger` に応じたタイミング（`load`, `idle`, `visible` 等）で `luna:url` のモジュールを動的 import
4. モジュールの `hydrate` 関数に要素と `luna:state` の JSON を渡す
5. hydrate 関数がクライアントコンポーネント（Signal + イベントハンドラ）を既存 DOM に接続

---

## 4. 開発コマンドリファレンス

```bash
# Sol CLI（リファレンスからビルドした版を使用）
sol dev            # 開発サーバー起動 (http://localhost:7777)
sol generate       # __gen__ 再生成
sol build          # プロダクションビルド
sol serve          # プロダクション配信

# MoonBit
moon check --target js   # 型チェック（高速）
moon build --target js   # ビルド
moon test --target js    # ユニットテスト
moon update              # mooncakes 依存更新
moon fmt                 # コードフォーマット
```

---

## 5. 主要パッケージの役割

| パッケージ | 用途 | インポートエイリアス例 |
|-----------|------|----------------------|
| `mizchi/luna` | UI ライブラリ本体（VNode, Signal, Renderer） | `@luna` |
| `mizchi/luna/dom` | ブラウザ DOM 操作（クライアント） | `@element` |
| `mizchi/luna/dom/static` | サーバーサイド DOM 要素生成 | `@server_dom` |
| `mizchi/sol` | SSR フレームワーク（Hono 統合） | `@sol` |
| `mizchi/sol/router` | ルーティング（SolRoutes, PageProps） | `@router` |
| `mizchi/sol/action` | Server Actions（CSRF 保護付き） | `@action` |
| `mizchi/signals` | リアクティブシグナル（alien-signals ベース） | `@signal` |
| `mizchi/mars` | HTTP サーバー抽象化 | `@mars` |
| `mizchi/js/core` | MoonBit-JS FFI コア | `@core` |

---

## 6. ファイルの役割と編集ガイド

### `app/server/routes.mbt` — ルート定義

すべてのルートの単一ソース。`sol generate` がこのファイルを読んで `__gen__/` を生成する。

```moonbit
pub fn routes() -> Array[@router.SolRoutes] {
  [
    @router.SolRoutes::Layout(segment="", layout=@layout.root_layout, children=[
      @router.SolRoutes::Page(
        path="/",
        handler=@router.PageHandler(home),
        title="Home",
        meta=[], revalidate=None, cache=None,
      ),
    ]),
    @router.SolRoutes::Get(
      path="/api/health",
      handler=@router.ApiHandler(api_health),
    ),
  ]
}
```

### `app/client/*.mbt` — クライアントコンポーネント（Island）

ブラウザで実行されるインタラクティブなコンポーネント。Props を受け取り DomNode を返す。

```moonbit
pub(all) struct CounterProps {
  initial_count : Int
} derive(ToJson, FromJson)

pub fn counter(props : CounterProps) -> DomNode {
  let count = @signal.signal(props.initial_count)
  div(class="counter", [
    span(class="count-display", [text_of(count)]),
    button(on=events().click(_ => count.update(n => n + 1)), [text("+")]),
  ])
}
```

### `app/layout/layout.mbt` — レイアウト

HTML の `<head>` 内容とページ共通構造を定義するサーバーコンポーネント。

```moonbit
// head() の返り値が <head> タグ内に挿入される
pub fn head() -> String {
  default_style + loader_script
}

// layout() がページコンテンツをラップする
pub fn layout(inner : Array[@luna.Node[Unit, String]]) -> @luna.Node[Unit, String] {
  div(class="container", [ nav([...]), outlet(name="main", inner) ])
}
```

**重要**: `head()` に `loader_script` を含めないと Island hydration が実行されない。

### `static/loader.js` — Island Hydration ローダー

`luna:*` 属性を持つ DOM 要素を検出し、クライアントモジュールを動的にロードして hydration を実行する。

**このファイルを手動編集する必要はないが、正しい loader が配置されていることを確認すること。** 生成テンプレートのスタブでは hydration が動作しない。

---

## 変更履歴

| 日付 | 内容 |
|------|------|
| 2026-02-27 | 初版作成。環境構築手順、問題 3.1 (依存パス不一致)・3.2 (hydration 未実行) の記録 |
