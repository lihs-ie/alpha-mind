///| SCR-004 監査ログページ (/audit) — SSR page handler
///|
///| Server component: renders the audit-log page.
///| Fetches the audit-log list from BFF GET /audit at SSR time, renders the
///| time-ordered list table (F-0041..F-0045) as an SSR placeholder, and embeds
///| the AuditSearch Island for interactive search / detail / trace-copy.
///|
///| Design (SCR-004):
///|  - R-01 検索条件: 期間 From/To · eventType · trace (Island)
///|  - R-02 ログ一覧: 時刻順ログテーブル (SSR + Island)
///|  - R-03 ログ詳細: payload要約 · reason (Island, 選択時)
///|
///| Data: GET /audit via BFF (SSR), GET /audit/{identifier} via Island.
///|
///| Ref: documents/外部設計/screens/SCR-004_監査ログ.md
///| Ref: documents/外部設計/api/openapi.yaml

///|
/// A single audit-log row fetched from BFF GET /audit at SSR time.
priv struct AuditSsrRow {
  identifier : String
  occurred_at : String
  event_type : String
  service : String
  result : String
  trace : String
}

///|
/// Server page handler for /audit.
/// Fetches the audit-log list from BFF and renders the page.
pub async fn audit_page(_props : @router.PageProps) -> @server_dom.ServerNode {
  let bff_base_url = get_bff_base_url_audit()
  let logs = fetch_audit_sync(bff_base_url)

  // Build Island props from fetched data.
  let search_props : @types.AuditSearchProps = {
    bff_base_url,
    initial_logs: logs.map(fn(row) {
      (@types.AuditRowProps::{
        identifier: row.identifier,
        occurred_at: row.occurred_at,
        event_type: row.event_type,
        service: row.service,
        result: row.result,
        trace: row.trace,
      } : @types.AuditRowProps)
    }),
  }

  // SSR placeholder for the Island (progressive enhancement): renders the same
  // list so content is visible before JS hydrates.
  let search_placeholder = render_audit_placeholder(logs)

  let page_content = div(
    style="min-height:100vh;background:var(--color-background,#020617);padding:24px;box-sizing:border-box;",
    [
      // Page header
      div(
        style="display:flex;align-items:center;justify-content:space-between;margin-bottom:32px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.5rem;font-weight:700;margin:0;",
            [text("監査ログ")],
          ),
          span(
            style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
            [text("alpha-mind")],
          ),
        ],
      ),
      p(
        style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0 0 24px;",
        [text("イベント時系列を追跡し、障害調査と操作監査を行います。")],
      ),
      // Audit search Island (search conditions + table + detail)
      @server_dom.client(
        @types.audit_search(search_props),
        [search_placeholder],
      ),
    ],
  )
  @server_dom.ServerNode::sync(page_content)
}

///|
/// SSR placeholder for the AuditSearch Island.
/// Renders the audit-log table so content is visible before hydration.
fn render_audit_placeholder(
  logs : Array[AuditSsrRow]
) -> @luna.Node[Unit, String] {
  let table_body = if logs.length() == 0 {
    div(
      style="padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
      [text("該当するログがありません。")],
    )
  } else {
    @server_dom.fragment(logs.map(fn(row) { render_audit_row_ssr(row) }))
  }
  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      // Search conditions placeholder (R-01)
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:16px 24px;display:flex;flex-direction:column;gap:16px;",
        [
          div(
            style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;",
            [
              search_field_ssr("期間 From"),
              search_field_ssr("期間 To"),
              search_field_ssr("イベント種別"),
              search_field_ssr("trace"),
            ],
          ),
          div(style="display:flex;justify-content:flex-end;", [
            span(
              style="background:rgba(99,102,241,0.2);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:8px 24px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;opacity:0.7;",
              [text("検索")],
            ),
          ]),
        ],
      ),
      // Log list table (R-02)
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
        attrs=[
          ("role", @luna.attr_static("table")),
          ("aria-label", @luna.attr_static("監査ログ一覧")),
        ],
        [render_audit_header_ssr(), table_body],
      ),
    ],
  )
}

///|
fn search_field_ssr(label_text : String) -> @luna.Node[Unit, String] {
  div(
    style="display:flex;flex-direction:column;gap:6px;",
    [
      label(
        style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
        [text(label_text)],
      ),
      input(
        type_="text",
        style="background:rgba(15,23,42,0.5);color:rgba(248,250,252,0.5);border:1px solid rgba(248,250,252,0.08);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
      ),
    ],
  )
}

///|
/// SSR header row (column headers).
fn render_audit_header_ssr() -> @luna.Node[Unit, String] {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style=audit_grid_style_ssr() +
      "border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      audit_header_cell_ssr(cell, "発生時刻"),
      audit_header_cell_ssr(cell, "イベント種別"),
      audit_header_cell_ssr(cell, "サービス"),
      audit_header_cell_ssr(cell, "result"),
      audit_header_cell_ssr(cell, "trace"),
      audit_header_cell_ssr(cell, "操作"),
    ],
  )
}

///|
fn audit_header_cell_ssr(style : String, label : String) -> @luna.Node[Unit, String] {
  div(style=style, attrs=[("role", @luna.attr_static("columnheader"))], [
    text(label),
  ])
}

///|
/// Shared CSS grid template for SSR header and rows.
fn audit_grid_style_ssr() -> String {
  "display:grid;grid-template-columns:1.4fr 1.4fr 1fr 0.8fr minmax(220px,1.6fr) minmax(160px,1fr);align-items:center;"
}

///|
/// SSR badge style for a result (mirrors the Island colours).
fn result_badge_style_ssr(result : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = if result == "success" {
    "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
  } else if result == "failed" {
    "background:rgba(248,113,113,0.15);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.4);"
  } else {
    "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// SSR row for a single audit-log entry.
fn render_audit_row_ssr(row : AuditSsrRow) -> @luna.Node[Unit, String] {
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  div(
    style=audit_grid_style_ssr() +
      "border-bottom:1px solid rgba(248,250,252,0.06);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.occurred_at),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.event_type),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.service),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        span(style=result_badge_style_ssr(row.result), [text(row.result)]),
      ]),
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.trace),
      ]),
      div(
        style="padding:8px 12px;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;",
        attrs=[("role", @luna.attr_static("cell"))],
        [text("traceコピー")],
      ),
    ],
  )
}

///|
/// Read the BFF base URL from environment.
fn get_bff_base_url_audit() -> String {
  ffi_get_env("BFF_BASE_URL", "http://localhost:8080")
}

///|
/// Synchronous BFF call for GET /audit. Returns [] when the BFF is unavailable.
extern "js" fn fetch_audit_sync(base_url : String) -> Array[AuditSsrRow] =
  #| (base_url) => {
  #|   try {
  #|     const token = globalThis?.process?.env?.['SSR_BFF_TOKEN'] ?? '';
  #|     const url = new URL('/audit', base_url);
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
  #|         occurred_at: o.occurredAt ?? '',
  #|         event_type: o.eventType ?? '',
  #|         service: o.service ?? '',
  #|         result: o.result ?? '',
  #|         trace: o.trace ?? '',
  #|       }));
  #|     }
  #|   } catch (_) {}
  #|   return [];
  #| }
