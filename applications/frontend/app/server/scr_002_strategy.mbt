///| SCR-002 戦略設定ページ (/settings/strategy) — SSR page handler
///|
///| Server component: renders the strategy settings page.
///| Fetches current strategy and compliance settings from BFF at SSR time.
///| Embeds StrategyFormIsland for interactive editing.
///|
///| Design:
///|  - R-01 基本設定: 対象市場、売買頻度 (SSR + Island)
///|  - R-02 ユニバース設定: 対象銘柄一覧 (SSR + Island)
///|  - R-03 リスク設定: 日次損失上限、ポジション集中上限、日次注文上限 (SSR + Island)
///|  - R-04 操作領域: 保存、初期値へ戻す (Island)
///|  + コンプライアンス制御: 制限銘柄、ブラックアウト期間 (Island)
///|
///| Data: GET /settings/strategy, GET /compliance/controls via BFF (SSR)
///| Operations: PUT /settings/strategy, PUT /compliance/controls via Island
///|
///| Ref: documents/外部設計/screens/SCR-002_戦略設定.md
///| Ref: documents/外部設計/api/openapi.yaml

///|
/// Strategy settings data fetched from BFF at SSR time.
struct StrategySettingsData {
  market : String
  rebalance_frequency : String
  symbols : Array[String]
  daily_loss_limit : Double
  position_concentration_limit : Double
  daily_order_limit : Int
}

///|
/// Blackout window entry
struct BlackoutWindowData {
  symbol : String
  start_at : String
  end_at : String
  action_reason_code : String
}

///|
/// Compliance controls data fetched from BFF at SSR time.
struct ComplianceControlsData {
  restricted_symbols : Array[String]
  blackout_windows : Array[BlackoutWindowData]
}

///|
/// Server page handler for /settings/strategy.
/// Fetches both strategy and compliance settings from BFF and renders the page.
pub async fn strategy_page(_props : @router.PageProps) -> @server_dom.ServerNode {
  let bff_base_url = get_bff_base_url_strategy()
  let strategy_data = fetch_strategy_settings_sync(bff_base_url)
  let compliance_data = fetch_compliance_controls_sync(bff_base_url)

  // Build Island props from fetched data
  let form_props : @types.StrategyFormProps = {
    bff_base_url,
    initial_market: strategy_data.market,
    initial_rebalance_frequency: strategy_data.rebalance_frequency,
    initial_symbols: strategy_data.symbols,
    initial_daily_loss_limit: strategy_data.daily_loss_limit,
    initial_position_concentration_limit: strategy_data.position_concentration_limit,
    initial_daily_order_limit: strategy_data.daily_order_limit,
    initial_restricted_symbols: compliance_data.restricted_symbols,
    initial_blackout_windows: compliance_data.blackout_windows
      .map(fn(w) {
        (@types.BlackoutWindowProps::{
          symbol: w.symbol,
          start_at: w.start_at,
          end_at: w.end_at,
          action_reason_code: w.action_reason_code,
        } : @types.BlackoutWindowProps)
      }),
  }

  // SSR placeholder for Island (progressive enhancement)
  let form_placeholder = render_strategy_form_placeholder(
    strategy_data,
    compliance_data,
  )

  let page_content = div(
    style="min-height:100vh;background:var(--color-background,#020617);padding:24px;box-sizing:border-box;",
    [
      // Page header
      div(
        style="display:flex;align-items:center;justify-content:space-between;margin-bottom:32px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.5rem;font-weight:700;margin:0;",
            [text("戦略設定")],
          ),
          span(
            style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
            [text("alpha-mind")],
          ),
        ],
      ),
      // Strategy form Island
      @server_dom.client(
        @types.strategy_form(form_props),
        [form_placeholder],
      ),
    ],
  )

  @server_dom.ServerNode::sync(page_content)
}

///|
/// SSR placeholder for StrategyForm Island.
/// Shows current settings in a read-only card while JS loads and hydrates.
fn render_strategy_form_placeholder(
  strategy : StrategySettingsData,
  compliance : ComplianceControlsData
) -> @luna.Node[Unit, String] {
  let symbols_text = ffi_join_array_strategy(strategy.symbols, "、")
  let restricted_text = if compliance.restricted_symbols.length() == 0 {
    "（なし）"
  } else {
    ffi_join_array_strategy(compliance.restricted_symbols, "、")
  }

  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      // R-01 基本設定
      render_settings_section(
        "基本設定",
        [
          render_field_row("対象市場", strategy.market),
          render_field_row(
            "売買頻度",
            if strategy.rebalance_frequency == "daily" {
              "毎日"
            } else {
              "毎週"
            },
          ),
        ],
      ),
      // R-02 ユニバース設定
      render_settings_section(
        "ユニバース設定（対象銘柄）",
        [render_field_row("銘柄リスト", symbols_text)],
      ),
      // R-03 リスク設定
      render_settings_section(
        "リスク設定",
        [
          render_field_row(
            "1日損失上限",
            ffi_format_percent_strategy(strategy.daily_loss_limit) + " %",
          ),
          render_field_row(
            "1銘柄上限",
            ffi_format_percent_strategy(
              strategy.position_concentration_limit,
            ) +
              " %",
          ),
          render_field_row(
            "1日注文上限件数",
            ffi_format_int_strategy(strategy.daily_order_limit) + " 件",
          ),
        ],
      ),
      // コンプライアンス制御
      render_settings_section(
        "コンプライアンス制御",
        [render_field_row("制限銘柄リスト", restricted_text)],
      ),
      // R-04 操作領域 placeholder
      div(
        style="display:flex;gap:12px;",
        [
          button(
            attrs=[
              ("type", @luna.attr_static("button")),
              (
                "style",
                @luna.attr_static(
                  "background:var(--color-cta,#6366F1);color:#fff;border:none;border-radius:6px;padding:12px 28px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;opacity:0.7;",
                ),
              ),
            ],
            [text("保存")],
          ),
          button(
            attrs=[
              ("type", @luna.attr_static("button")),
              (
                "style",
                @luna.attr_static(
                  "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.12);border-radius:6px;padding:12px 28px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;opacity:0.7;",
                ),
              ),
            ],
            [text("初期値へ戻す")],
          ),
        ],
      ),
    ],
  )
}

///|
/// Render a settings section card with a title and content rows.
fn render_settings_section(
  title : String,
  children : Array[@luna.Node[Unit, String]]
) -> @luna.Node[Unit, String] {
  div(
    style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:24px;",
    [
      h2(
        style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0 0 16px;letter-spacing:0.04em;",
        [text(title)],
      ),
      div(
        style="display:flex;flex-direction:column;gap:12px;",
        children,
      ),
    ],
  )
}

///|
/// Render a label/value row for a read-only field.
fn render_field_row(label : String, value : String) -> @luna.Node[Unit, String] {
  div(
    style="display:flex;align-items:baseline;gap:12px;",
    [
      span(
        style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;min-width:160px;flex-shrink:0;",
        [text(label)],
      ),
      span(
        style="color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.875rem;",
        [text(value)],
      ),
    ],
  )
}

///|
/// Read the BFF base URL from environment.
fn get_bff_base_url_strategy() -> String {
  ffi_get_env("BFF_BASE_URL", "http://localhost:8080")
}

///|
/// Synchronous BFF call for GET /settings/strategy.
/// Returns safe defaults when the BFF is unavailable.
extern "js" fn fetch_strategy_settings_sync(
  base_url : String
) -> StrategySettingsData =
  #| (base_url) => {
  #|   try {
  #|     const token = globalThis?.process?.env?.['SSR_BFF_TOKEN'] ?? '';
  #|     const url = new URL('/settings/strategy', base_url);
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
  #|     if (result) {
  #|       return {
  #|         market: result.market ?? 'JP',
  #|         rebalance_frequency: result.rebalanceFrequency ?? 'daily',
  #|         symbols: result.symbols ?? [],
  #|         daily_loss_limit: result.dailyLossLimit ?? 0.0,
  #|         position_concentration_limit: result.positionConcentrationLimit ?? 0.0,
  #|         daily_order_limit: result.dailyOrderLimit ?? 1,
  #|       };
  #|     }
  #|   } catch (_) {}
  #|   return {
  #|     market: 'JP',
  #|     rebalance_frequency: 'daily',
  #|     symbols: [],
  #|     daily_loss_limit: 0.0,
  #|     position_concentration_limit: 0.0,
  #|     daily_order_limit: 1,
  #|   };
  #| }

///|
/// Synchronous BFF call for GET /compliance/controls.
/// Returns safe defaults when the BFF is unavailable.
extern "js" fn fetch_compliance_controls_sync(
  base_url : String
) -> ComplianceControlsData =
  #| (base_url) => {
  #|   try {
  #|     const token = globalThis?.process?.env?.['SSR_BFF_TOKEN'] ?? '';
  #|     const url = new URL('/compliance/controls', base_url);
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
  #|     if (result) {
  #|       const windows = (result.blackoutWindows ?? []).map(w => ({
  #|         symbol: w.symbol ?? '',
  #|         start_at: w.startAt ?? '',
  #|         end_at: w.endAt ?? '',
  #|         action_reason_code: w.actionReasonCode ?? '',
  #|       }));
  #|       return {
  #|         restricted_symbols: result.restrictedSymbols ?? [],
  #|         blackout_windows: windows,
  #|       };
  #|     }
  #|   } catch (_) {}
  #|   return { restricted_symbols: [], blackout_windows: [] };
  #| }

///|
extern "js" fn ffi_join_array_strategy(arr : Array[String], sep : String) -> String =
  #| (arr, sep) => arr.join(sep)

///|
extern "js" fn ffi_format_percent_strategy(value : Double) -> String =
  #| (value) => value.toLocaleString('ja-JP', { minimumFractionDigits: 1, maximumFractionDigits: 2 })

///|
extern "js" fn ffi_format_int_strategy(value : Int) -> String =
  #| (value) => String(value)
