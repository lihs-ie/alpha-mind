///| SCR-007 仮説ラボページ (/hypotheses) — SSR page handler
///|
///| Server component: renders the hypothesis-lab page.
///| Fetches the hypothesis list from BFF GET /hypotheses at SSR time, renders the
///| hypothesis list table (F-0071 identifier, symbol, instrumentType, F-0072 status,
///| title, updatedAt) as an SSR placeholder, and embeds the HypothesesActions Island
///| for status filtering (R-01), metrics/detail (R-02) and 再検証/昇格申請/却下/MNPI
///| operations (R-03).
///|
///| Design (SCR-007):
///|  - R-01 仮説一覧:  状態 · 作成日 · 最終更新 (SSR + Island)
///|  - R-02 指標領域:  バックテスト/デモ成績 · コスト控除指標 (Island, 選択時)
///|  - R-03 操作領域:  再検証 / 昇格申請 / 却下 / MNPI自己申告 (Island, 選択時)
///|
///| Data: GET /hypotheses via BFF (SSR), GET /hypotheses/{identifier} via Island.
///| Operations:
///|  - POST /hypotheses/{identifier}/retest                  (再検証, Island)
///|  - POST /hypotheses/{identifier}/promote                 (昇格申請, Island)
///|  - POST /hypotheses/{identifier}/reject                  (却下, Island)
///|  - PUT  /hypotheses/{identifier}/mnpi-self-declaration   (MNPI自己申告, Island)
///|
///| 安全性 (CLAUDE.md / 条件付き自動昇格設計): AI 提案戦略は Walk-forward/DSR/PBO 通過 +
///| コンプライアンスレビュー済みでないと本番利用 (live) 不可。個別株 (STOCK) は手動昇格必須。
///|
///| Ref: documents/外部設計/screens/SCR-007_仮説ラボ.md
///| Ref: documents/外部設計/api/openapi.yaml
///| Ref: documents/外部設計/state/状態遷移設計.md §6

///|
/// A single hypothesis row fetched from BFF GET /hypotheses at SSR time.
priv struct HypothesisSsrRow {
  identifier : String
  symbol : String
  instrument_type : String
  status : String
  title : String
  updated_at : String
}

///|
/// Server page handler for /hypotheses.
/// Fetches the hypothesis list from BFF and renders the page.
pub async fn hypotheses_page(
  _props : @router.PageProps
) -> @server_dom.ServerNode {
  let bff_base_url = hypotheses_get_bff_base_url()
  let fetched = hypotheses_fetch_sync(bff_base_url)
  let rows = fetched.rows
  let next_cursor = fetched.next_cursor

  // Build Island props from fetched data.
  let actions_props : @types.HypothesesActionsProps = {
    bff_base_url,
    initial_next_cursor: next_cursor,
    initial_hypotheses: rows.map(fn(row) {
      (
        @types.HypothesisRowProps::{
          identifier: row.identifier,
          symbol: row.symbol,
          instrument_type: row.instrument_type,
          status: row.status,
          title: row.title,
          updated_at: row.updated_at,
        } :
        @types.HypothesisRowProps)
    }),
  }

  // SSR placeholder for the Island (progressive enhancement): renders the same
  // list so content is visible before JS hydrates.
  let actions_placeholder = hypotheses_render_placeholder(rows)
  let page_content = div(
    style="min-height:100vh;background:var(--color-background,#020617);padding:24px;box-sizing:border-box;",
    [
      // Page header
      div(
        style="display:flex;align-items:center;justify-content:space-between;margin-bottom:32px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.5rem;font-weight:700;margin:0;",
            [text("仮説ラボ")],
          ),
          span(
            style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
            [text("alpha-mind")],
          ),
        ],
      ),
      p(
        style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0 0 24px;",
        [
          text(
            "仮説の検証状況と採否を管理します。昇格は本番運用に直結するため、デモ期間・コンプライアンス・MNPI自己申告の条件を満たす必要があります。",
          ),
        ],
      ),
      // Hypotheses actions Island (filter + list + detail + operations)
      @server_dom.client(
        @types.hypotheses_actions(actions_props),
        [actions_placeholder],
      ),
    ],
  )
  @server_dom.ServerNode::sync(page_content)
}

///|
/// SSR placeholder for the HypothesesActions Island.
/// Renders the hypothesis list table so content is visible before hydration.
fn hypotheses_render_placeholder(
  rows : Array[HypothesisSsrRow]
) -> @luna.Node[Unit, String] {
  let table_body = if rows.length() == 0 {
    div(
      style="padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
      [text("該当する仮説がありません。")],
    )
  } else {
    @server_dom.fragment(rows.map(fn(row) { hypotheses_render_row_ssr(row) }))
  }
  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      // Filter placeholder (R-01)
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:16px 24px;display:flex;flex-direction:column;gap:8px;",
        [
          span(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
            [text("状態フィルタ")],
          ),
          div(style="display:flex;gap:8px;flex-wrap:wrap;", [
            hypotheses_filter_chip_ssr("すべて"),
            hypotheses_filter_chip_ssr("draft"),
            hypotheses_filter_chip_ssr("backtested"),
            hypotheses_filter_chip_ssr("demo"),
            hypotheses_filter_chip_ssr("live"),
            hypotheses_filter_chip_ssr("rejected"),
          ]),
        ],
      ),
      // Hypothesis list table (R-01)
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
        attrs=[
          ("role", @luna.attr_static("table")),
          ("aria-label", @luna.attr_static("仮説一覧")),
        ],
        [hypotheses_render_header_ssr(), table_body],
      ),
    ],
  )
}

///|
/// SSR filter chip (static placeholder mirroring the Island button group).
fn hypotheses_filter_chip_ssr(label : String) -> @luna.Node[Unit, String] {
  span(
    style="display:inline-block;border-radius:999px;padding:6px 14px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;background:rgba(15,23,42,0.6);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.12);",
    [text(label)],
  )
}

///|
/// SSR header row (column headers).
fn hypotheses_render_header_ssr() -> @luna.Node[Unit, String] {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style=hypotheses_grid_style_ssr() +
      "border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      hypotheses_header_cell_ssr(cell, "銘柄"),
      hypotheses_header_cell_ssr(cell, "仮説"),
      hypotheses_header_cell_ssr(cell, "種別"),
      hypotheses_header_cell_ssr(cell, "状態"),
      hypotheses_header_cell_ssr(cell, "最終更新"),
    ],
  )
}

///|
fn hypotheses_header_cell_ssr(
  style : String,
  label : String
) -> @luna.Node[Unit, String] {
  div(style=style, attrs=[("role", @luna.attr_static("columnheader"))], [
    text(label),
  ])
}

///|
/// Shared CSS grid template for SSR header and rows.
fn hypotheses_grid_style_ssr() -> String {
  "display:grid;grid-template-columns:minmax(90px,0.8fr) minmax(260px,3fr) minmax(80px,0.6fr) minmax(120px,0.9fr) minmax(150px,1.1fr);align-items:center;"
}

///|
/// SSR badge style for a hypothesis status (mirrors the Island colours).
fn hypotheses_status_badge_style_ssr(status : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = if status == "draft" {
    "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  } else if status == "backtested" {
    "background:rgba(99,102,241,0.18);color:#818CF8;border:1px solid rgba(99,102,241,0.35);"
  } else if status == "demo" {
    "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
  } else if status == "live" {
    "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
  } else if status == "rejected" {
    "background:rgba(248,113,113,0.12);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.35);"
  } else {
    "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// SSR badge style for an instrumentType.
fn hypotheses_instrument_badge_style_ssr(instrument_type : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = if instrument_type == "ETF" {
    "background:rgba(34,197,94,0.12);color:#22C55E;border:1px solid rgba(34,197,94,0.3);"
  } else if instrument_type == "STOCK" {
    "background:rgba(99,102,241,0.14);color:#818CF8;border:1px solid rgba(99,102,241,0.3);"
  } else {
    "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// SSR row for a single hypothesis entry.
fn hypotheses_render_row_ssr(
  row : HypothesisSsrRow
) -> @luna.Node[Unit, String] {
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  div(
    style=hypotheses_grid_style_ssr() +
      "border-bottom:1px solid rgba(248,250,252,0.06);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.symbol),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.title),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        span(style=hypotheses_instrument_badge_style_ssr(row.instrument_type), [
          text(row.instrument_type),
        ]),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        span(style=hypotheses_status_badge_style_ssr(row.status), [
          text(row.status),
        ]),
      ]),
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.updated_at),
      ]),
    ],
  )
}

///|
/// Read the BFF base URL from environment.
/// (`ffi_get_env` is defined at package scope in scr_000_login.mbt.)
fn hypotheses_get_bff_base_url() -> String {
  ffi_get_env("BFF_BASE_URL", "http://localhost:8080")
}

///|
/// Result of the synchronous SSR hypothesis fetch (rows + pagination cursor).
priv struct HypothesisSsrResult {
  rows : Array[HypothesisSsrRow]
  next_cursor : String
}

///|
/// Synchronous BFF call for GET /hypotheses. Returns an empty result when the BFF
/// is unavailable. Maps the OpenAPI HypothesisListResponse.
extern "js" fn hypotheses_fetch_sync(base_url : String) -> HypothesisSsrResult =
  #| (base_url) => {
  #|   try {
  #|     const token = globalThis?.process?.env?.['SSR_BFF_TOKEN'] ?? '';
  #|     const url = new URL('/hypotheses', base_url);
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
  #|           symbol: o.symbol ?? '',
  #|           instrument_type: o.instrumentType ?? '',
  #|           status: o.status ?? '',
  #|           title: o.title ?? '',
  #|           updated_at: o.updatedAt ?? '',
  #|         })),
  #|         next_cursor: result.nextCursor ?? '',
  #|       };
  #|     }
  #|   } catch (_) {}
  #|   return { rows: [], next_cursor: '' };
  #| }
