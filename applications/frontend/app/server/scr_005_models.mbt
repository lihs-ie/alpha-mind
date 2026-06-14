///| SCR-005 モデル検証ページ (/models/validation) — SSR page handler
///|
///| Server component: renders the model-validation page.
///| Fetches the model-validation list from BFF GET /models/validation at SSR
///| time, renders the model list table (F-0051,F-0052,degradationFlag,createdAt)
///| as an SSR placeholder, and embeds the ModelValidationActions Island for
///| interactive filtering, metric detail (R-02) and promote/reject (R-03).
///|
///| Design (SCR-005):
///|  - R-01 モデル一覧: モデル版 · 状態 · 劣化フラグ · 作成日時 (SSR + Island)
///|  - R-02 指標パネル: OOS · Sharpe · DD · 回転率 · PBO/DSR ほか (Island, 選択時)
///|  - R-03 判定操作: 昇格 / 差し戻し + 理由コード/コメント (Island, 選択時)
///|
///| Data: GET /models/validation via BFF (SSR), GET /models/validation/{v} via Island.
///| Operations: POST /models/validation/{v}/{approve,reject} via Island.
///|
///| Ref: documents/外部設計/screens/SCR-005_モデル検証.md
///| Ref: documents/外部設計/api/openapi.yaml
///| Ref: documents/外部設計/state/状態遷移設計.md (Model Status: candidate→approved|rejected)

///|
/// A single model-validation row fetched from BFF GET /models/validation at SSR time.
priv struct ModelSsrRow {
  model_version : String
  status : String
  degradation_flag : String
  created_at : String
}

///|
/// Server page handler for /models/validation.
/// Fetches the model list from BFF and renders the page.
pub async fn models_page(_props : @router.PageProps) -> @server_dom.ServerNode {
  let bff_base_url = models_get_bff_base_url()
  let rows = fetch_models_sync(bff_base_url)

  // Build Island props from fetched data.
  let actions_props : @types.ModelsActionsProps = {
    bff_base_url,
    initial_models: rows.map(fn(row) {
      (@types.ModelValidationRowProps::{
        model_version: row.model_version,
        status: row.status,
        degradation_flag: row.degradation_flag,
        created_at: row.created_at,
      } : @types.ModelValidationRowProps)
    }),
  }

  // SSR placeholder for the Island (progressive enhancement): renders the same
  // list so content is visible before JS hydrates.
  let actions_placeholder = models_render_placeholder(rows)
  let page_content = div(
    style="min-height:100vh;background:var(--color-background,#020617);padding:24px;box-sizing:border-box;",
    [
      // Page header
      div(
        style="display:flex;align-items:center;justify-content:space-between;margin-bottom:32px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.5rem;font-weight:700;margin:0;",
            [text("モデル検証")],
          ),
          span(
            style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
            [text("alpha-mind")],
          ),
        ],
      ),
      p(
        style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0 0 24px;",
        [text("モデル評価結果を確認し、昇格/差し戻しを判断します。")],
      ),
      // Model validation actions Island (filter + list + metrics + decisions)
      @server_dom.client(
        @types.models_actions(actions_props),
        [actions_placeholder],
      ),
    ],
  )
  @server_dom.ServerNode::sync(page_content)
}

///|
/// SSR placeholder for the ModelValidationActions Island.
/// Renders the model list table so content is visible before hydration.
fn models_render_placeholder(
  rows : Array[ModelSsrRow]
) -> @luna.Node[Unit, String] {
  let table_body = if rows.length() == 0 {
    div(
      style="padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
      [text("候補モデルがありません。")],
    )
  } else {
    @server_dom.fragment(rows.map(fn(row) { models_render_row_ssr(row) }))
  }
  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      // Status filter placeholder (R-01)
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:16px 24px;display:flex;gap:12px;align-items:flex-end;flex-wrap:wrap;",
        [
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(
              for_="models-status-filter",
              style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
              [text("状態フィルタ")],
            ),
            input(
              type_="text",
              id="models-status-filter",
              name="models-status-filter",
              style="background:rgba(15,23,42,0.5);color:rgba(248,250,252,0.5);border:1px solid rgba(248,250,252,0.08);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;min-width:280px;box-sizing:border-box;",
            ),
          ]),
          span(
            style="background:rgba(99,102,241,0.2);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:8px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;opacity:0.7;",
            [text("フィルタ適用")],
          ),
        ],
      ),
      // Model list table (R-01)
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
        attrs=[
          ("role", @luna.attr_static("table")),
          ("aria-label", @luna.attr_static("モデル検証一覧")),
        ],
        [models_render_header_ssr(), table_body],
      ),
    ],
  )
}

///|
/// SSR header row (column headers).
fn models_render_header_ssr() -> @luna.Node[Unit, String] {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style=models_grid_style_ssr() +
      "border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      models_header_cell_ssr(cell, "モデル版"),
      models_header_cell_ssr(cell, "状態"),
      models_header_cell_ssr(cell, "劣化フラグ"),
      models_header_cell_ssr(cell, "作成日時"),
      models_header_cell_ssr(cell, "操作"),
    ],
  )
}

///|
fn models_header_cell_ssr(
  style : String,
  label : String
) -> @luna.Node[Unit, String] {
  div(style=style, attrs=[("role", @luna.attr_static("columnheader"))], [
    text(label),
  ])
}

///|
/// Shared CSS grid template for SSR header and rows.
fn models_grid_style_ssr() -> String {
  "display:grid;grid-template-columns:minmax(200px,2fr) 1fr 1fr 1.6fr minmax(200px,1.4fr);align-items:center;"
}

///|
/// SSR badge style for a model status (mirrors the Island colours).
fn models_status_badge_style_ssr(status : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = if status == "approved" {
    "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
  } else if status == "candidate" {
    "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
  } else if status == "rejected" {
    "background:rgba(248,113,113,0.12);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.35);"
  } else {
    "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// SSR badge style for a degradation flag.
fn models_flag_badge_style_ssr(flag : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = if flag == "warn" {
    "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
  } else if flag == "block" {
    "background:rgba(248,113,113,0.18);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.5);"
  } else {
    "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// SSR action hint per status (interactive buttons appear after hydration).
fn models_action_hint_ssr(status : String) -> String {
  if status == "candidate" {
    "昇格 / 差し戻し"
  } else {
    "—"
  }
}

///|
/// SSR row for a single model-validation entry.
fn models_render_row_ssr(row : ModelSsrRow) -> @luna.Node[Unit, String] {
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  div(
    style=models_grid_style_ssr() +
      "border-bottom:1px solid rgba(248,250,252,0.06);",
    attrs=[("role", @luna.attr_static("row"))],
    [
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.model_version),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        span(style=models_status_badge_style_ssr(row.status), [
          text(row.status),
        ]),
      ]),
      div(style=cell, attrs=[("role", @luna.attr_static("cell"))], [
        span(style=models_flag_badge_style_ssr(row.degradation_flag), [
          text(row.degradation_flag),
        ]),
      ]),
      div(style=mono, attrs=[("role", @luna.attr_static("cell"))], [
        text(row.created_at),
      ]),
      div(
        style="padding:8px 12px;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;",
        attrs=[("role", @luna.attr_static("cell"))],
        [text(models_action_hint_ssr(row.status))],
      ),
    ],
  )
}

///|
/// Read the BFF base URL from environment.
/// (`ffi_get_env` is defined at package scope in scr_000_login.mbt.)
fn models_get_bff_base_url() -> String {
  ffi_get_env("BFF_BASE_URL", "http://localhost:8080")
}

///|
/// Synchronous BFF call for GET /models/validation. Returns [] when the BFF
/// is unavailable. Maps the OpenAPI ModelValidationListResponse.
extern "js" fn fetch_models_sync(base_url : String) -> Array[ModelSsrRow] =
  #| (base_url) => {
  #|   try {
  #|     const token = globalThis?.process?.env?.['SSR_BFF_TOKEN'] ?? '';
  #|     const url = new URL('/models/validation', base_url);
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
  #|         model_version: o.modelVersion ?? '',
  #|         status: o.status ?? '',
  #|         degradation_flag: o.degradationFlag ?? '',
  #|         created_at: o.createdAt ?? '',
  #|       }));
  #|     }
  #|   } catch (_) {}
  #|   return [];
  #| }
