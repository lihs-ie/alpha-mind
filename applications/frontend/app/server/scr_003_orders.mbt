///| SCR-003 注文管理ページ (/orders) — SSR page handler
///|
///| Server component: renders the order management page.
///| Fetches the order candidate list and dashboard summary (for kill switch state)
///| from BFF at SSR time, renders the list table (SSR placeholder), and embeds the
///| OrdersActionsIsland for interactive approve/reject/retry and status filtering.
///|
///| Design (SCR-003):
///|  - R-01 フィルタ領域: 状態フィルタ (Island)
///|  - R-02 注文一覧: 候補/承認/却下/執行結果テーブル (SSR + Island)
///|  - R-04 操作領域: 承認/却下/再送 — 状態遷移に応じた表示 (Island)
///|  + kill switch有効時の承認制限表示
///|
///| Data: GET /orders, GET /dashboard/summary via BFF (SSR)
///| Operations: POST /orders/{identifier}/{approve,reject,retry} via Island
///|
///| Ref: documents/外部設計/screens/SCR-003_注文管理.md
///| Ref: documents/外部設計/api/openapi.yaml
///| Ref: documents/外部設計/state/状態遷移設計.md

///|
/// A single order row fetched from BFF GET /orders at SSR time.
priv struct OrderSsrRow {
  identifier : String
  symbol : String
  side : String
  qty : Double
  status : String
  created_at : String
}

///|
/// Server page handler for /orders.
/// Fetches the order list + kill switch state from BFF and renders the page.
pub async fn orders_page(_props : @router.PageProps) -> @server_dom.ServerNode {
  let bff_base_url = get_bff_base_url_orders()
  let orders = fetch_orders_sync(bff_base_url)
  let kill_switch_enabled = fetch_kill_switch_sync(bff_base_url)

  // Build Island props from fetched data.
  let actions_props : @types.OrdersActionsProps = {
    bff_base_url,
    initial_kill_switch_enabled: kill_switch_enabled,
    initial_orders: orders.map(fn(order) {
      (@types.OrderRowProps::{
        identifier: order.identifier,
        symbol: order.symbol,
        side: order.side,
        qty: order.qty,
        status: order.status,
        created_at: order.created_at,
      } : @types.OrderRowProps)
    }),
  }

  // SSR placeholder for the Island (progressive enhancement): renders the same
  // list so content is visible before JS hydrates.
  let actions_placeholder = render_orders_placeholder(orders, kill_switch_enabled)

  let page_content = div(
    style="min-height:100vh;background:var(--color-background,#020617);padding:24px;box-sizing:border-box;",
    [
      // Page header
      div(
        style="display:flex;align-items:center;justify-content:space-between;margin-bottom:32px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.5rem;font-weight:700;margin:0;",
            [text("注文管理")],
          ),
          span(
            style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
            [text("alpha-mind")],
          ),
        ],
      ),
      h2(
        style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0 0 16px;letter-spacing:0.05em;text-transform:uppercase;",
        [text("注文候補")],
      ),
      // Orders actions Island (filter + table + actions)
      @server_dom.client(
        @types.orders_actions(actions_props),
        [actions_placeholder],
      ),
    ],
  )
  @server_dom.ServerNode::sync(page_content)
}

///|
/// SSR placeholder for the OrdersActions Island.
/// Renders the order list table and a (non-interactive) status badge per row,
/// plus the kill switch warning when applicable.
fn render_orders_placeholder(
  orders : Array[OrderSsrRow],
  kill_switch_enabled : Bool
) -> @luna.Node[Unit, String] {
  let kill_switch_warning = if kill_switch_enabled {
    div(
      style="padding:10px 16px;border-radius:6px;background:rgba(234,179,8,0.12);border:1px solid rgba(234,179,8,0.35);color:#EAB308;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
      [text("⚠ kill switch有効中のため承認できません。")],
    )
  } else {
    span(style="display:none;", [])
  }
  let table_body = if orders.length() == 0 {
    div(
      style="padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
      [text("該当する注文がありません。")],
    )
  } else {
    @server_dom.fragment(orders.map(fn(order) { render_order_row_ssr(order) }))
  }
  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      kill_switch_warning,
      // Filter area placeholder
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:16px 24px;display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap;",
        [
          div(
            style="display:flex;flex-direction:column;gap:6px;",
            [
              label(
                for_="orders-status-filter",
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                [text("状態フィルタ")],
              ),
              input(
                type_="text",
                id="orders-status-filter",
                name="orders-status-filter",
                placeholder="例: PROPOSED / APPROVED / FAILED（空=全件）",
                style="background:rgba(15,23,42,0.5);color:rgba(248,250,252,0.5);border:1px solid rgba(248,250,252,0.08);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;min-width:280px;box-sizing:border-box;",
              ),
            ],
          ),
          button(
            attrs=[
              ("type", @luna.attr_static("button")),
              (
                "style",
                @luna.attr_static(
                  "background:rgba(99,102,241,0.2);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:8px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;opacity:0.7;",
                ),
              ),
            ],
            [text("フィルタ適用")],
          ),
        ],
      ),
      // Order list table
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
        attrs=[
          ("role", @luna.attr_static("table")),
          ("aria-label", @luna.attr_static("注文一覧")),
        ],
        [render_order_header_ssr(), table_body],
      ),
    ],
  )
}

///|
/// SSR header row (column headers).
fn render_order_header_ssr() -> @luna.Node[Unit, String] {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style="display:grid;grid-template-columns:minmax(220px,2fr) 1fr 0.7fr 1fr 1fr 1.6fr minmax(220px,1.6fr);align-items:center;border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      header_cell_ssr(cell, "注文ID"),
      header_cell_ssr(cell, "銘柄"),
      header_cell_ssr(cell, "売買"),
      header_cell_ssr(cell, "数量"),
      header_cell_ssr(cell, "状態"),
      header_cell_ssr(cell, "作成日時"),
      header_cell_ssr(cell, "操作"),
    ],
  )
}

///|
fn header_cell_ssr(style : String, label : String) -> @luna.Node[Unit, String] {
  div(
    style=style,
    attrs=[("role", @luna.attr_static("columnheader"))],
    [text(label)],
  )
}

///|
/// SSR row for a single order (badge + state-gated action button labels).
fn render_order_row_ssr(order : OrderSsrRow) -> @luna.Node[Unit, String] {
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  let side_color = if order.side == "BUY" {
    "color:var(--color-profit,#22C55E);"
  } else {
    "color:var(--color-loss,#F87171);"
  }
  div(
    style="display:grid;grid-template-columns:minmax(220px,2fr) 1fr 0.7fr 1fr 1fr 1.6fr minmax(220px,1.6fr);align-items:center;border-bottom:1px solid rgba(248,250,252,0.06);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(order.identifier),
      ]),
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(order.symbol),
      ]),
      div(
        style=mono + side_color + "font-weight:600;",
        attrs=[("role", @luna.attr_static("cell"))],
        [text(order.side)],
      ),
      div(
        style=mono + "text-align:right;",
        attrs=[("role", @luna.attr_static("cell"))],
        [text(ffi_format_qty_ssr(order.qty))],
      ),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        span(style=status_badge_style_ssr(order.status), [text(order.status)]),
      ]),
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(order.created_at),
      ]),
      div(
        style="padding:8px 12px;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;",
        attrs=[("role", @luna.attr_static("cell"))],
        [text(action_hint_ssr(order.status))],
      ),
    ],
  )
}

///|
/// SSR badge style for a status (mirrors the Island colours).
fn status_badge_style_ssr(status : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = if status == "EXECUTED" {
    "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
  } else if status == "APPROVED" {
    "background:rgba(99,102,241,0.15);color:#818CF8;border:1px solid rgba(99,102,241,0.35);"
  } else if status == "PROPOSED" {
    "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
  } else if status == "REJECTED" {
    "background:rgba(248,113,113,0.12);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.35);"
  } else if status == "FAILED" {
    "background:rgba(248,113,113,0.18);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.5);"
  } else {
    "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// SSR action hint text per status (the interactive buttons appear after hydration).
fn action_hint_ssr(status : String) -> String {
  if status == "PROPOSED" {
    "承認 / 却下"
  } else if status == "FAILED" {
    "再送"
  } else {
    "—"
  }
}

///|
/// Read the BFF base URL from environment.
fn get_bff_base_url_orders() -> String {
  ffi_get_env("BFF_BASE_URL", "http://localhost:8080")
}

///|
/// Synchronous BFF call for GET /orders. Returns [] when the BFF is unavailable.
extern "js" fn fetch_orders_sync(base_url : String) -> Array[OrderSsrRow] =
  #| (base_url) => {
  #|   try {
  #|     const token = globalThis?.process?.env?.['SSR_BFF_TOKEN'] ?? '';
  #|     const url = new URL('/orders', base_url);
  #|     const mod = url.protocol === 'https:' ? require('https') : require('http');
  #|     let result = null;
  #|     let done = false;
  #|     const req = mod.request(url.toString(), {
  #|       method: 'GET',
  #|       headers: token ? { 'Authorization': 'Bearer ' + token } : {},
  #|     }, (res) => {
  #|       let data = '';
  #|       res.on('data', (chunk) => { data += chunk; });
  #|       res.on('end', () => { try { result = JSON.parse(data); } catch (_) {} done = true; });
  #|     });
  #|     req.on('error', () => { done = true; });
  #|     req.end();
  #|     const deadline = Date.now() + 3000;
  #|     while (!done && Date.now() < deadline) {
  #|       const start = Date.now();
  #|       while (Date.now() - start < 10) {}
  #|     }
  #|     if (result && Array.isArray(result.items)) {
  #|       return result.items.map(o => ({
  #|         identifier: o.identifier ?? '',
  #|         symbol: o.symbol ?? '',
  #|         side: o.side ?? '',
  #|         qty: o.qty ?? 0.0,
  #|         status: o.status ?? '',
  #|         created_at: o.createdAt ?? '',
  #|       }));
  #|     }
  #|   } catch (_) {}
  #|   return [];
  #| }

///|
/// Synchronous BFF call for GET /dashboard/summary (kill switch state).
/// Returns false when the BFF is unavailable.
extern "js" fn fetch_kill_switch_sync(base_url : String) -> Bool =
  #| (base_url) => {
  #|   try {
  #|     const token = globalThis?.process?.env?.['SSR_BFF_TOKEN'] ?? '';
  #|     const url = new URL('/dashboard/summary', base_url);
  #|     const mod = url.protocol === 'https:' ? require('https') : require('http');
  #|     let result = null;
  #|     let done = false;
  #|     const req = mod.request(url.toString(), {
  #|       method: 'GET',
  #|       headers: token ? { 'Authorization': 'Bearer ' + token } : {},
  #|     }, (res) => {
  #|       let data = '';
  #|       res.on('data', (chunk) => { data += chunk; });
  #|       res.on('end', () => { try { result = JSON.parse(data); } catch (_) {} done = true; });
  #|     });
  #|     req.on('error', () => { done = true; });
  #|     req.end();
  #|     const deadline = Date.now() + 3000;
  #|     while (!done && Date.now() < deadline) {
  #|       const start = Date.now();
  #|       while (Date.now() - start < 10) {}
  #|     }
  #|     if (result) { return result.killSwitchEnabled ?? false; }
  #|   } catch (_) {}
  #|   return false;
  #| }

///|
extern "js" fn ffi_format_qty_ssr(value : Double) -> String =
  #| (value) => value.toLocaleString('ja-JP', { maximumFractionDigits: 4 })
