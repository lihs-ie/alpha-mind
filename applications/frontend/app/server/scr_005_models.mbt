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
  // ページ本文を Organisms の PageLayout シェル（AppHeader + Sidebar + main）で
  // ラップする。
  let page_content = @organisms.page_layout(
    current_path="/models/validation",
    page_title="モデル検証",
    user_name="運用者",
    user_role="admin",
    body=[
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
  // モデル検証一覧は Organisms の汎用 DataTable で構築（列定義 + 行データ +
  // empty 状態）。状態/劣化フラグはこの SSR 時点ではテキスト表示で、ハイドレー
  // ション後に Island がリッチ表示へ差し替える。
  let table_columns : Array[@organisms.TableColumn] = [
    { label: "モデル版", width: "minmax(200px,2fr)", mono: true },
    { label: "状態", width: "1fr", mono: false },
    { label: "劣化フラグ", width: "1fr", mono: false },
    { label: "作成日時", width: "1.6fr", mono: true },
  ]
  let table_rows = rows.map(fn(row) {
    [row.model_version, models_status_label(row.status), row.degradation_flag, row.created_at]
  })
  let models_table = @organisms.data_table(
    table_columns,
    table_rows,
    caption="モデル検証一覧",
    empty_message="候補モデルがありません。",
  )
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
      // Model list table (R-01, Organisms DataTable)
      models_table,
    ],
  )
}

///|
/// Human-readable model-status label used in the SSR table.
/// Mirrors the badge mapping (candidate→候補, approved→承認, rejected→却下).
fn models_status_label(status : String) -> String {
  if status == "candidate" {
    "候補"
  } else if status == "approved" {
    "承認"
  } else if status == "rejected" {
    "却下"
  } else {
    status
  }
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
