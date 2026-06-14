///| SCR-001 ダッシュボードページ (/dashboard) — SSR page handler
///|
///| Server component: renders the dashboard page with runtime status, P&L KPIs,
///| and embeds the DashboardOperationsIsland for interactive emergency controls.
///|
///| Design:
///|  - R-01 KPIカード: 当日損益、累積損益、最大DD、稼働状態 (SSR)
///|  - R-02 最新実行情報: 最新シグナル時刻 (SSR)
///|  - R-03 操作パネル: 運用開始/停止、kill switch切替 (Island: app/client/dashboard_operations.mbt)
///|
///| Data: GET /dashboard/summary via BFF (server-side fetch at SSR time)
///| Operations: POST /operations/runtime, POST /operations/kill-switch via Island
///|
///| Ref: documents/外部設計/screens/SCR-001_ダッシュボード.md
///| Ref: documents/外部設計/state/状態遷移設計.md

///|
/// Server page handler for /dashboard.
/// Fetches summary from BFF and renders the full dashboard SSR.
pub async fn dashboard_page(_props : @router.PageProps) -> @server_dom.ServerNode {
  let bff_base_url = get_bff_base_url_dashboard()
  let summary_result = fetch_dashboard_summary_sync(bff_base_url)

  let operations_props : @types.DashboardOperationsProps = {
    bff_base_url,
    initial_runtime_state: summary_result.runtime_state,
    initial_kill_switch_enabled: summary_result.kill_switch_enabled,
  }

  // SSR placeholder for the Island (progressive enhancement).
  let operations_placeholder = render_operations_placeholder(
    summary_result.runtime_state,
    summary_result.kill_switch_enabled,
  )

  // Kill switch warning banner (conditional)
  let kill_switch_warning = if summary_result.kill_switch_enabled {
    div(
      style="background:rgba(234,179,8,0.12);border:1px solid rgba(234,179,8,0.35);border-radius:6px;padding:12px 16px;margin-bottom:16px;color:#EAB308;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
      [text("⚠ kill switch が有効です。発注系操作は停止中です。")],
    )
  } else {
    span(style="display:none;", [])
  }

  let page_content = div(
    style="min-height:100vh;background:var(--color-background,#020617);padding:24px;box-sizing:border-box;",
    [
      // Page header
      div(
        style="display:flex;align-items:center;justify-content:space-between;margin-bottom:32px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.5rem;font-weight:700;margin:0;",
            [text("ダッシュボード")],
          ),
          span(
            style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
            [text("alpha-mind")],
          ),
        ],
      ),
      kill_switch_warning,
      // R-01 KPIカード section header
      h2(
        style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0 0 16px;letter-spacing:0.05em;text-transform:uppercase;",
        [text("運用状態")],
      ),
      div(
        style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;margin-bottom:32px;",
        [
          render_kpi_status_card(
            "稼働状態",
            summary_result.runtime_state,
            if summary_result.runtime_state == "RUNNING" {
              "color:#22C55E;"
            } else {
              "color:rgba(248,250,252,0.5);"
            },
          ),
          render_kpi_number_card("当日損益", summary_result.pnl_today),
          render_kpi_number_card("累積損益", summary_result.pnl_total),
          render_kpi_status_card(
            "最大DD",
            format_percent_value(summary_result.max_drawdown),
            "color:#F87171;",
          ),
        ],
      ),
      // R-02 最新実行情報
      h2(
        style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0 0 16px;letter-spacing:0.05em;text-transform:uppercase;",
        [text("最新実行情報")],
      ),
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:20px;margin-bottom:32px;",
        [
          div(
            style="display:flex;align-items:center;gap:12px;",
            [
              span(
                style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
                [text("最新シグナル時刻")],
              ),
              span(
                style="color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.875rem;",
                [text(summary_result.latest_signal_at)],
              ),
            ],
          ),
        ],
      ),
      // R-03 操作パネル
      h2(
        style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0 0 16px;letter-spacing:0.05em;text-transform:uppercase;",
        [text("緊急操作パネル")],
      ),
      @server_dom.client(
        @types.dashboard_operations(operations_props),
        [operations_placeholder],
      ),
    ],
  )

  @server_dom.ServerNode::sync(page_content)
}

///|
/// KPI card for text/enum values.
fn render_kpi_status_card(
  label : String,
  value : String,
  value_style : String
) -> @luna.Node[Unit, String] {
  div(
    style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:20px;",
    [
      p(
        style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:500;margin:0 0 8px;letter-spacing:0.05em;text-transform:uppercase;",
        [text(label)],
      ),
      p(
        style="font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:1.5rem;font-weight:700;margin:0;" +
          value_style,
        [text(value)],
      ),
    ],
  )
}

///|
/// KPI card for numeric values (P&L).
fn render_kpi_number_card(label : String, value : Double) -> @luna.Node[Unit, String] {
  let value_str = format_currency_value(value)
  let value_style = if value >= 0.0 {
    "color:#22C55E;"
  } else {
    "color:#F87171;"
  }
  render_kpi_status_card(label, value_str, value_style)
}

///|
/// Format a number with sign.
fn format_currency_value(value : Double) -> String {
  if value >= 0.0 {
    "+" + ffi_format_number_dashboard(value)
  } else {
    ffi_format_number_dashboard(value)
  }
}

///|
/// Format a percentage value.
fn format_percent_value(value : Double) -> String {
  ffi_format_number_dashboard(value) + "%"
}

///|
/// SSR placeholder for DashboardOperations Island.
fn render_operations_placeholder(
  runtime_state : String,
  kill_switch_enabled : Bool
) -> @luna.Node[Unit, String] {
  let runtime_button_label = if runtime_state == "RUNNING" {
    "運用停止"
  } else {
    "運用開始"
  }
  let runtime_button_bg = if runtime_state == "RUNNING" {
    "background:#F87171;"
  } else {
    "background:var(--color-cta,#22C55E);"
  }
  let kill_switch_label = if kill_switch_enabled {
    "Kill Switch: 有効 (無効化する)"
  } else {
    "Kill Switch: 無効 (有効化する)"
  }
  div(
    style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:24px;display:flex;flex-direction:column;gap:16px;",
    [
      button(
        attrs=[
          ("type", @luna.attr_static("button")),
          (
            "style",
            @luna.attr_static(
              "color:#fff;border:none;border-radius:6px;padding:12px 24px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;width:100%;max-width:240px;" +
                runtime_button_bg,
            ),
          ),
        ],
        [text(runtime_button_label)],
      ),
      button(
        attrs=[
          ("type", @luna.attr_static("button")),
          (
            "style",
            @luna.attr_static(
              "background:rgba(234,179,8,0.15);color:#EAB308;border:1px solid rgba(234,179,8,0.35);border-radius:6px;padding:12px 24px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;width:100%;max-width:240px;",
            ),
          ),
        ],
        [text(kill_switch_label)],
      ),
      button(
        attrs=[
          ("type", @luna.attr_static("button")),
          (
            "style",
            @luna.attr_static(
              "background:rgba(99,102,241,0.15);color:#818CF8;border:1px solid rgba(99,102,241,0.3);border-radius:6px;padding:12px 24px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;width:100%;max-width:240px;",
            ),
          ),
        ],
        [text("手動サイクル実行")],
      ),
    ],
  )
}

///|
/// Dashboard summary data fetched from BFF at SSR time.
struct DashboardSummaryData {
  pnl_today : Double
  pnl_total : Double
  max_drawdown : Double
  runtime_state : String
  kill_switch_enabled : Bool
  latest_signal_at : String
}

///|
/// Synchronous BFF call via JS FFI.
/// Returns safe defaults when the BFF is unavailable (e.g. local dev).
extern "js" fn fetch_dashboard_summary_sync(
  base_url : String
) -> DashboardSummaryData =
  #| (base_url) => {
  #|   try {
  #|     const token = globalThis?.process?.env?.['SSR_BFF_TOKEN'] ?? '';
  #|     // Node.js built-in http/https for SSR synchronous fetch
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
  #|     // Spin wait (SSR context — synchronous is acceptable)
  #|     const deadline = Date.now() + 3000;
  #|     while (!done && Date.now() < deadline) {
  #|       const start = Date.now();
  #|       while (Date.now() - start < 10) {}
  #|     }
  #|     if (result) {
  #|       return {
  #|         pnl_today: result.pnlToday ?? 0.0,
  #|         pnl_total: result.pnlTotal ?? 0.0,
  #|         max_drawdown: result.maxDrawdown ?? 0.0,
  #|         runtime_state: result.runtimeState ?? 'STOPPED',
  #|         kill_switch_enabled: result.killSwitchEnabled ?? false,
  #|         latest_signal_at: result.latestSignalAt ?? '--',
  #|       };
  #|     }
  #|   } catch (_) {}
  #|   return {
  #|     pnl_today: 0.0,
  #|     pnl_total: 0.0,
  #|     max_drawdown: 0.0,
  #|     runtime_state: 'STOPPED',
  #|     kill_switch_enabled: false,
  #|     latest_signal_at: '--',
  #|   };
  #| }

///|
/// Read the BFF base URL from environment.
/// Uses a unique name to avoid collision with scr_000_login.mbt in the same package.
fn get_bff_base_url_dashboard() -> String {
  ffi_get_env("BFF_BASE_URL", "http://localhost:8080")
}

///|
extern "js" fn ffi_format_number_dashboard(value : Double) -> String =
  #| (value) => value.toLocaleString('ja-JP', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
