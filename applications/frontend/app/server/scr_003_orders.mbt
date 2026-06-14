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

  // ページ本文を Organisms の PageLayout シェル（AppHeader + Sidebar + main）で
  // ラップする。
  let page_content = @organisms.page_layout(
    current_path="/orders",
    page_title="注文管理",
    user_name="運用者",
    user_role="admin",
    body=[
      h2(
        style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0 0 16px;letter-spacing:0.05em;text-transform:uppercase;",
        [text("注文候補")],
      ),
      // Orders actions Island (filter + table + actions)
      @server_dom.client(
        @types.orders_actions(actions_props),
        [actions_placeholder],
      ),
      // 承認確認モーダル（Organisms Modal, SSR は閉じた状態）。OrdersActions
      // Island が承認ボタン押下時に開閉・confirm/cancel を配線する。
      @organisms.modal(
        "order-approve-confirm",
        "注文を承認しますか？",
        [
          @server_dom.text(
            "承認すると執行フローに進みます。この操作は監査ログに記録されます。",
          ),
        ],
        actions=@organisms.modal_confirm_actions(
          confirm_label="承認する",
          cancel_label="キャンセル",
        ),
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
  // 注文一覧テーブルは Organisms の OrderTable で構築（状態バッジ + 状態遷移に
  // 応じた操作ボタン + kill switch による承認ゲート）。
  let order_rows = orders.map(fn(order) {
    (@organisms.OrderRow::{
      identifier: order.identifier,
      symbol: order.symbol,
      side: order.side,
      qty: ffi_format_qty_ssr(order.qty),
      status: order.status,
      created_at: order.created_at,
    } : @organisms.OrderRow)
  })
  let orders_table = @organisms.order_table(
    order_rows,
    kill_switch_enabled~,
  )
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
      // Order list table (Organisms OrderTable)
      orders_table,
    ],
  )
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
