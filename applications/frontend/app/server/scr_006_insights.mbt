///| SCR-006 インサイト管理ページ (/insights) — SSR page handler
///|
///| Server component: renders the insight-management page.
///| Fetches the insight list from BFF GET /insights at SSR time, renders the
///| insight list table (F-0061 identifier, F-0062 sourceType, F-0063 summary)
///| as an SSR placeholder, and embeds the InsightsActions Island for theme/source
///| filtering (R-01), detail (R-03) and hypothesize/adopt/reject (R-04).
///|
///| Design (SCR-006):
///|  - R-01 フィルタ:   ソース · テーマ (Island, client-side over the loaded list)
///|  - R-02 一覧:       要約 · センチメント/シグナル · So What (SSR + Island)
///|  - R-03 詳細:       evidenceSnippet · 収集Skill版 · sourceUrl (Island, 選択時)
///|  - R-04 操作:       仮説化 / 採用 / 却下 (Island, 選択時)
///|
///| Data: GET /insights via BFF (SSR), GET /insights/{identifier} via Island.
///| Operations: POST /insights/{identifier}/{hypothesize,adopt,reject} via Island.
///|
///| Ref: documents/外部設計/screens/SCR-006_インサイト管理.md
///| Ref: documents/外部設計/api/openapi.yaml

///|
/// A single insight row fetched from BFF GET /insights at SSR time.
priv struct InsightSsrRow {
  identifier : String
  source_type : String
  summary : String
  source_url : String
  signal_class : String
  so_what_score : Double
}

///|
/// Server page handler for /insights.
/// Fetches the insight list from BFF and renders the page.
pub async fn insights_page(_props : @router.PageProps) -> @server_dom.ServerNode {
  let bff_base_url = insights_get_bff_base_url()
  let fetched = insights_fetch_sync(bff_base_url)
  let rows = fetched.rows
  let next_cursor = fetched.next_cursor

  // Build Island props from fetched data.
  let actions_props : @types.InsightsActionsProps = {
    bff_base_url,
    initial_next_cursor: next_cursor,
    initial_insights: rows.map(fn(row) {
      (@types.InsightRowProps::{
        identifier: row.identifier,
        source_type: row.source_type,
        summary: row.summary,
        source_url: row.source_url,
        collected_at: "",
        signal_class: row.signal_class,
        so_what_score: row.so_what_score,
      } : @types.InsightRowProps)
    }),
  }

  // SSR placeholder for the Island (progressive enhancement): renders the same
  // list so content is visible before JS hydrates.
  let actions_placeholder = insights_render_placeholder(rows)
  let page_content = div(
    style="min-height:100vh;background:var(--color-background,#020617);padding:24px;box-sizing:border-box;",
    [
      // Page header
      div(
        style="display:flex;align-items:center;justify-content:space-between;margin-bottom:32px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.5rem;font-weight:700;margin:0;",
            [text("インサイト管理")],
          ),
          span(
            style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
            [text("alpha-mind")],
          ),
        ],
      ),
      p(
        style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0 0 24px;",
        [text("定性インサイトの根拠を確認し、採否・仮説化を判断します。")],
      ),
      // Insights actions Island (filter + list + detail + operations)
      @server_dom.client(
        @types.insights_actions(actions_props),
        [actions_placeholder],
      ),
    ],
  )
  @server_dom.ServerNode::sync(page_content)
}

///|
/// SSR placeholder for the InsightsActions Island.
/// Renders the insight list table so content is visible before hydration.
fn insights_render_placeholder(
  rows : Array[InsightSsrRow]
) -> @luna.Node[Unit, String] {
  let table_body = if rows.length() == 0 {
    div(
      style="padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
      [text("該当インサイトがありません。")],
    )
  } else {
    @server_dom.fragment(rows.map(fn(row) { insights_render_row_ssr(row) }))
  }
  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      // Filter placeholder (R-01)
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:16px 24px;display:flex;gap:16px;align-items:flex-end;flex-wrap:wrap;",
        [
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(
              for_="insights-theme-filter",
              style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
              [text("テーマフィルタ")],
            ),
            input(
              type_="text",
              id="insights-theme-filter",
              name="insights-theme-filter",
              style="background:rgba(15,23,42,0.5);color:rgba(248,250,252,0.5);border:1px solid rgba(248,250,252,0.08);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;min-width:280px;box-sizing:border-box;",
            ),
          ]),
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(
              for_="insights-source-filter",
              style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
              [text("ソースフィルタ")],
            ),
            input(
              type_="text",
              id="insights-source-filter",
              name="insights-source-filter",
              style="background:rgba(15,23,42,0.5);color:rgba(248,250,252,0.5);border:1px solid rgba(248,250,252,0.08);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;min-width:240px;box-sizing:border-box;",
            ),
          ]),
        ],
      ),
      // Insight list table (R-02)
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
        attrs=[
          ("role", @luna.attr_static("table")),
          ("aria-label", @luna.attr_static("インサイト一覧")),
        ],
        [insights_render_header_ssr(), table_body],
      ),
    ],
  )
}

///|
/// SSR header row (column headers).
fn insights_render_header_ssr() -> @luna.Node[Unit, String] {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style=insights_grid_style_ssr() +
      "border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      insights_header_cell_ssr(cell, "ソース"),
      insights_header_cell_ssr(cell, "要約"),
      insights_header_cell_ssr(cell, "シグナル"),
      insights_header_cell_ssr(cell, "So What"),
      insights_header_cell_ssr(cell, "操作"),
    ],
  )
}

///|
fn insights_header_cell_ssr(
  style : String,
  label : String
) -> @luna.Node[Unit, String] {
  div(style=style, attrs=[("role", @luna.attr_static("columnheader"))], [
    text(label),
  ])
}

///|
/// Shared CSS grid template for SSR header and rows.
fn insights_grid_style_ssr() -> String {
  "display:grid;grid-template-columns:minmax(110px,0.9fr) minmax(260px,3fr) minmax(150px,1.1fr) minmax(90px,0.7fr) minmax(220px,1.6fr);align-items:center;"
}

///|
/// SSR badge style for a source type (mirrors the Island colours).
fn insights_source_badge_style_ssr(source_type : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = if source_type == "x" {
    "background:rgba(99,102,241,0.18);color:#818CF8;border:1px solid rgba(99,102,241,0.35);"
  } else if source_type == "youtube" {
    "background:rgba(248,113,113,0.14);color:#F87171;border:1px solid rgba(248,113,113,0.35);"
  } else if source_type == "paper" {
    "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
  } else if source_type == "github" {
    "background:rgba(248,250,252,0.1);color:rgba(248,250,252,0.85);border:1px solid rgba(248,250,252,0.2);"
  } else {
    "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// SSR badge style for a signal class.
fn insights_signal_badge_style_ssr(signal_class : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = if signal_class == "structural_anomaly" {
    "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
  } else {
    "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// SSR row for a single insight entry.
fn insights_render_row_ssr(row : InsightSsrRow) -> @luna.Node[Unit, String] {
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  div(
    style=insights_grid_style_ssr() +
      "border-bottom:1px solid rgba(248,250,252,0.06);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        span(style=insights_source_badge_style_ssr(row.source_type), [
          text(row.source_type),
        ]),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.summary),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        span(style=insights_signal_badge_style_ssr(row.signal_class), [
          text(row.signal_class),
        ]),
      ]),
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(insights_format_score_ssr(row.so_what_score)),
      ]),
      div(
        style="padding:8px 12px;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;",
        attrs=[("role", @luna.attr_static("cell"))],
        [text("仮説化 / 採用 / 却下")],
      ),
    ],
  )
}

///|
/// Read the BFF base URL from environment.
/// (`ffi_get_env` is defined at package scope in scr_000_login.mbt.)
fn insights_get_bff_base_url() -> String {
  ffi_get_env("BFF_BASE_URL", "http://localhost:8080")
}

///|
/// Format a soWhatScore (0..1) for SSR display (2 fraction digits).
fn insights_format_score_ssr(value : Double) -> String {
  insights_ffi_format_ratio(value)
}

///|
/// Format a ratio value (JS toLocaleString, 2 fraction digits).
extern "js" fn insights_ffi_format_ratio(value : Double) -> String =
  #| (value) => {
  #|   try { return value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
  #|   catch { return String(value); }
  #| }

///|
/// Result of the synchronous SSR insight fetch (rows + pagination cursor).
priv struct InsightSsrResult {
  rows : Array[InsightSsrRow]
  next_cursor : String
}

///|
/// Synchronous BFF call for GET /insights. Returns an empty result when the BFF
/// is unavailable. Maps the OpenAPI InsightListResponse.
extern "js" fn insights_fetch_sync(base_url : String) -> InsightSsrResult =
  #| (base_url) => {
  #|   try {
  #|     const token = globalThis?.process?.env?.['SSR_BFF_TOKEN'] ?? '';
  #|     const url = new URL('/insights', base_url);
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
  #|       return {
  #|         rows: result.items.map(o => ({
  #|           identifier: o.identifier ?? '',
  #|           source_type: o.sourceType ?? '',
  #|           summary: o.summary ?? '',
  #|           source_url: o.sourceUrl ?? '',
  #|           signal_class: o.signalClass ?? '',
  #|           so_what_score: typeof o.soWhatScore === 'number' ? o.soWhatScore : 0.0,
  #|         })),
  #|         next_cursor: result.nextCursor ?? '',
  #|       };
  #|     }
  #|   } catch (_) {}
  #|   return { rows: [], next_cursor: '' };
  #| }
