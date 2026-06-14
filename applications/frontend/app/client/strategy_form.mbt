///| Strategy Form Island Component (SCR-002)
///|
///| Interactive strategy and compliance settings form.
///| This is a client component: it runs in the browser after hydration.
///|
///| Operations:
///|  - A-0021 保存: PUT /settings/strategy
///|  - A-0022 初期値へ戻す: confirmation modal then reset fields
///|  - A-0023 銘柄追加: add symbol to list (dedup guard)
///|  - A-0024 銘柄削除: remove symbol from list (min 1 guard)
///|  - A-0025 コンプライアンス制御保存: PUT /compliance/controls
///|
///| Ref: documents/外部設計/screens/SCR-002_戦略設定.md
///| Ref: documents/外部設計/api/openapi.yaml

///|
/// A single blackout window entry (serialisable for Island props).
pub(all) struct BlackoutWindowProps {
  symbol : String
  start_at : String
  end_at : String
  action_reason_code : String
} derive(ToJson, FromJson)

///|
/// Props passed from the server (SSR initial state).
pub(all) struct StrategyFormProps {
  bff_base_url : String
  initial_market : String
  initial_rebalance_frequency : String
  initial_symbols : Array[String]
  initial_daily_loss_limit : Double
  initial_position_concentration_limit : Double
  initial_daily_order_limit : Int
  initial_restricted_symbols : Array[String]
  initial_blackout_windows : Array[BlackoutWindowProps]
} derive(ToJson, FromJson)

///|
/// Strategy Form Island component.
pub fn strategy_form(props : StrategyFormProps) -> DomNode {
  // ── Strategy state signals ────────────────────────────────────────────────
  let rebalance_frequency = @signal.signal(props.initial_rebalance_frequency)
  let symbols = @signal.signal(ffi_clone_string_array(props.initial_symbols))
  let daily_loss_limit = @signal.signal(
    ffi_double_to_string(props.initial_daily_loss_limit),
  )
  let position_concentration_limit = @signal.signal(
    ffi_double_to_string(props.initial_position_concentration_limit),
  )
  let daily_order_limit = @signal.signal(
    ffi_int_to_string(props.initial_daily_order_limit),
  )

  // Symbol addition input
  let new_symbol_input = @signal.signal("")

  // ── Compliance state signals ──────────────────────────────────────────────
  let restricted_symbols = @signal.signal(
    ffi_clone_string_array(props.initial_restricted_symbols),
  )
  let blackout_windows = @signal.signal(
    ffi_clone_blackout_array(props.initial_blackout_windows),
  )
  let new_restricted_symbol_input = @signal.signal("")

  // Blackout window addition inputs
  let new_blackout_symbol = @signal.signal("")
  let new_blackout_start_at = @signal.signal("")
  let new_blackout_end_at = @signal.signal("")
  let new_blackout_reason_code = @signal.signal("MANUAL_OPERATION")

  // ── UI state signals ──────────────────────────────────────────────────────
  let is_saving = @signal.signal(false)
  let status_message = @signal.signal("")
  let status_is_error = @signal.signal(false)
  let show_reset_modal = @signal.signal(false)

  // ── Validation error signals ──────────────────────────────────────────────
  let error_rebalance_frequency = @signal.signal("")
  let error_symbols = @signal.signal("")
  let error_daily_loss_limit = @signal.signal("")
  let error_position_concentration_limit = @signal.signal("")
  let error_daily_order_limit = @signal.signal("")
  let error_new_symbol = @signal.signal("")
  let error_restricted_symbols = @signal.signal("")
  let error_blackout_window = @signal.signal("")

  // ── Strategy form handlers ────────────────────────────────────────────────

  let handle_frequency_change : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    rebalance_frequency.set(target.value)
    error_rebalance_frequency.set("")
  }

  let handle_daily_loss_limit_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    daily_loss_limit.set(target.value)
    error_daily_loss_limit.set("")
  }

  let handle_position_concentration_limit_input : @element.InputHandler = fn(
    e
  ) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    position_concentration_limit.set(target.value)
    error_position_concentration_limit.set("")
  }

  let handle_daily_order_limit_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    daily_order_limit.set(target.value)
    error_daily_order_limit.set("")
  }

  let handle_new_symbol_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    new_symbol_input.set(target.value)
    error_new_symbol.set("")
  }

  let handle_add_symbol : @element.MouseHandler = fn(_e) {
    let symbol = ffi_trim_string(new_symbol_input.get())
    if symbol == "" {
      error_new_symbol.set("銘柄コードを入力してください")
      return
    }
    let current = symbols.get()
    if ffi_array_includes(current, symbol) {
      error_new_symbol.set("重複する銘柄コードがあります")
      return
    }
    symbols.set(ffi_array_append(current, symbol))
    new_symbol_input.set("")
    error_symbols.set("")
  }

  let handle_remove_symbol : (String) -> @element.MouseHandler = fn(symbol) {
    fn(_e) {
      let current = symbols.get()
      if ffi_array_length(current) <= 1 {
        error_symbols.set("銘柄を1件以上設定してください")
        return
      }
      symbols.set(ffi_array_remove(current, symbol))
    }
  }

  // ── Validate strategy fields ──────────────────────────────────────────────

  let validate_strategy : () -> Bool = fn() {
    let mut valid = true
    if rebalance_frequency.get() == "" {
      error_rebalance_frequency.set("売買頻度を選択してください")
      valid = false
    } else {
      error_rebalance_frequency.set("")
    }
    if ffi_array_length(symbols.get()) < 1 {
      error_symbols.set("銘柄を1件以上設定してください")
      valid = false
    } else {
      error_symbols.set("")
    }
    let loss_val = ffi_parse_double(daily_loss_limit.get())
    if loss_val <= 0.0 || loss_val > 20.0 {
      error_daily_loss_limit.set("0より大きく20以下で入力してください")
      valid = false
    } else {
      error_daily_loss_limit.set("")
    }
    let concentration_val = ffi_parse_double(
      position_concentration_limit.get(),
    )
    if concentration_val <= 0.0 || concentration_val > 50.0 {
      error_position_concentration_limit.set(
        "0より大きく50以下で入力してください",
      )
      valid = false
    } else {
      error_position_concentration_limit.set("")
    }
    let order_val = ffi_parse_int(daily_order_limit.get())
    if order_val < 1 || order_val > 100 {
      error_daily_order_limit.set("1以上100以下で入力してください")
      valid = false
    } else {
      error_daily_order_limit.set("")
    }
    valid
  }

  // ── Save strategy handler ─────────────────────────────────────────────────

  let handle_save_strategy : @element.MouseHandler = fn(_e) {
    if is_saving.get() {
      return
    }
    if not(validate_strategy()) {
      return
    }
    is_saving.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let saving = is_saving
    let msg = status_message
    let is_err = status_is_error
    ffi_put_strategy_settings(
      base_url,
      props.initial_market,
      rebalance_frequency.get(),
      symbols.get(),
      ffi_parse_double(daily_loss_limit.get()),
      ffi_parse_double(position_concentration_limit.get()),
      ffi_parse_int(daily_order_limit.get()),
      fn(success, error_message) {
        saving.set(false)
        if success {
          is_err.set(false)
          msg.set("戦略設定を保存しました。")
        } else {
          is_err.set(true)
          msg.set("戦略設定の保存に失敗しました。 " + error_message)
        }
      },
    )
  }

  // ── Reset modal handlers ──────────────────────────────────────────────────

  let handle_open_reset_modal : @element.MouseHandler = fn(_e) {
    show_reset_modal.set(true)
  }

  let handle_cancel_reset : @element.MouseHandler = fn(_e) {
    show_reset_modal.set(false)
  }

  let handle_confirm_reset : @element.MouseHandler = fn(_e) {
    show_reset_modal.set(false)
    rebalance_frequency.set(props.initial_rebalance_frequency)
    symbols.set(ffi_clone_string_array(props.initial_symbols))
    daily_loss_limit.set(ffi_double_to_string(props.initial_daily_loss_limit))
    position_concentration_limit.set(
      ffi_double_to_string(props.initial_position_concentration_limit),
    )
    daily_order_limit.set(ffi_int_to_string(props.initial_daily_order_limit))
    error_rebalance_frequency.set("")
    error_symbols.set("")
    error_daily_loss_limit.set("")
    error_position_concentration_limit.set("")
    error_daily_order_limit.set("")
    status_message.set("")
  }

  // ── Compliance handlers ───────────────────────────────────────────────────

  let handle_new_restricted_symbol_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    new_restricted_symbol_input.set(target.value)
    error_restricted_symbols.set("")
  }

  let handle_add_restricted_symbol : @element.MouseHandler = fn(_e) {
    let symbol = ffi_trim_string(new_restricted_symbol_input.get())
    if symbol == "" {
      error_restricted_symbols.set("銘柄コードを入力してください")
      return
    }
    let current = restricted_symbols.get()
    if ffi_array_includes(current, symbol) {
      error_restricted_symbols.set("重複する銘柄コードがあります")
      return
    }
    restricted_symbols.set(ffi_array_append(current, symbol))
    new_restricted_symbol_input.set("")
  }

  let handle_remove_restricted_symbol : (String) -> @element.MouseHandler = fn(
    symbol
  ) {
    fn(_e) {
      let current = restricted_symbols.get()
      restricted_symbols.set(ffi_array_remove(current, symbol))
    }
  }

  let handle_new_blackout_symbol_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    new_blackout_symbol.set(target.value)
    error_blackout_window.set("")
  }

  let handle_new_blackout_start_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    new_blackout_start_at.set(target.value)
    error_blackout_window.set("")
  }

  let handle_new_blackout_end_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    new_blackout_end_at.set(target.value)
    error_blackout_window.set("")
  }

  let handle_new_blackout_reason_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    new_blackout_reason_code.set(target.value)
  }

  let handle_add_blackout_window : @element.MouseHandler = fn(_e) {
    let symbol = ffi_trim_string(new_blackout_symbol.get())
    let start = ffi_trim_string(new_blackout_start_at.get())
    let end_date = ffi_trim_string(new_blackout_end_at.get())
    let reason = ffi_trim_string(new_blackout_reason_code.get())
    if symbol == "" || start == "" || end_date == "" {
      error_blackout_window.set("銘柄コード、開始日時、終了日時を入力してください")
      return
    }
    if not(ffi_date_is_before(start, end_date)) {
      error_blackout_window.set("ブラックアウト期間の指定が不正です")
      return
    }
    let new_window : BlackoutWindowProps = {
      symbol,
      start_at: start,
      end_at: end_date,
      action_reason_code: reason,
    }
    blackout_windows.set(
      ffi_array_append_blackout(blackout_windows.get(), new_window),
    )
    new_blackout_symbol.set("")
    new_blackout_start_at.set("")
    new_blackout_end_at.set("")
    new_blackout_reason_code.set("MANUAL_OPERATION")
    error_blackout_window.set("")
  }

  let handle_remove_blackout_window : (Int) -> @element.MouseHandler = fn(
    index
  ) {
    fn(_e) {
      blackout_windows.set(ffi_array_remove_at(blackout_windows.get(), index))
    }
  }

  // ── Validate and save compliance controls ─────────────────────────────────

  let handle_save_compliance : @element.MouseHandler = fn(_e) {
    if is_saving.get() {
      return
    }
    is_saving.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let saving = is_saving
    let msg = status_message
    let is_err = status_is_error
    ffi_put_compliance_controls(
      base_url,
      restricted_symbols.get(),
      blackout_windows.get(),
      fn(success, error_message) {
        saving.set(false)
        if success {
          is_err.set(false)
          msg.set("コンプライアンス制御を保存しました。")
        } else {
          is_err.set(true)
          msg.set("コンプライアンス制御の保存に失敗しました。 " + error_message)
        }
      },
    )
  }

  // ── Render ────────────────────────────────────────────────────────────────

  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      // Status message area
      div(
        attrs=[
          ("role", @element.AttrString("alert")),
          ("aria-live", @element.AttrString("polite")),
        ],
        dyn_attrs=[
          (
            "style",
            @element.Dynamic(
              fn() {
                let message = status_message.get()
                if message == "" {
                  "display:none;"
                } else if status_is_error.get() {
                  "padding:10px 16px;border-radius:6px;background:rgba(248,113,113,0.12);border:1px solid rgba(248,113,113,0.3);color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
                } else {
                  "padding:10px 16px;border-radius:6px;background:rgba(34,197,94,0.12);border:1px solid rgba(34,197,94,0.3);color:#22C55E;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
                }
              },
            ),
          ),
        ],
        [text_of(status_message)],
      ),
      // ── R-01 基本設定 ────────────────────────────────────────────────────
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:24px;display:flex;flex-direction:column;gap:16px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0;letter-spacing:0.04em;",
            [text("基本設定")],
          ),
          // 対象市場 (JP 固定 MVP)
          div(
            style="display:flex;flex-direction:column;gap:6px;",
            [
              label(
                for_="strategy-market",
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                [text("対象市場")],
              ),
              input(
                type_="text",
                id="strategy-market",
                name="strategy-market",
                style="background:rgba(15,23,42,0.5);color:rgba(248,250,252,0.5);border:1px solid rgba(248,250,252,0.08);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;max-width:200px;box-sizing:border-box;cursor:not-allowed;",
                attrs=[("value", @element.AttrString("JP")), ("readonly", @element.AttrString("true")), ("aria-readonly", @element.AttrString("true"))],
              ),
            ],
          ),
          // 売買頻度
          div(
            style="display:flex;flex-direction:column;gap:6px;",
            [
              label(
                for_="strategy-frequency",
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                [text("売買頻度 *")],
              ),
              input(
                type_="text",
                id="strategy-frequency",
                name="strategy-frequency",
                placeholder="daily または weekly",
                style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;max-width:200px;box-sizing:border-box;",
                on=events().input(handle_frequency_change),
                attrs=[("value", @element.AttrString(props.initial_rebalance_frequency))],
              ),
              div(
                attrs=[("role", @element.AttrString("alert"))],
                dyn_style=fn() {
                  if error_rebalance_frequency.get() == "" {
                    "display:none;"
                  } else {
                    "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
                  }
                },
                [text_of(error_rebalance_frequency)],
              ),
            ],
          ),
        ],
      ),
      // ── R-02 ユニバース設定 ───────────────────────────────────────────────
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:24px;display:flex;flex-direction:column;gap:16px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0;letter-spacing:0.04em;",
            [text("ユニバース設定（対象銘柄）")],
          ),
          // 銘柄一覧
          div(
            style="display:flex;flex-direction:column;gap:8px;",
            [
              div(
                attrs=[("role", @element.AttrString("list")), ("aria-label", @element.AttrString("対象銘柄リスト"))],
                dyn_style=fn() {
                  if ffi_array_length(symbols.get()) == 0 {
                    "display:none;"
                  } else {
                    "display:flex;flex-wrap:wrap;gap:8px;margin-bottom:8px;"
                  }
                },
                [
                  text_dyn(
                    @signal.computed(fn() {
                      ffi_render_symbol_chips(symbols.get())
                    }),
                  ),
                ],
              ),
              // Symbol chip list rendered via FFI for dynamic content
              div(
                dyn_style=fn() {
                  if ffi_array_length(symbols.get()) > 0 {
                    "display:flex;flex-wrap:wrap;gap:8px;margin-bottom:8px;"
                  } else {
                    "display:none;"
                  }
                },
                ffi_map_symbols_to_chips(
                  symbols.get(),
                  handle_remove_symbol,
                ),
              ),
            ],
          ),
          // 銘柄追加
          div(
            style="display:flex;gap:8px;align-items:flex-start;",
            [
              div(
                style="display:flex;flex-direction:column;gap:4px;flex:1;max-width:300px;",
                [
                  input(
                    type_="text",
                    id="strategy-new-symbol",
                    name="strategy-new-symbol",
                    placeholder="銘柄コード（例: 1306.T）",
                    style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
                    on=events().input(handle_new_symbol_input),
                    attrs=[("aria-label", @element.AttrString("追加する銘柄コード"))],
                  ),
                  div(
                    attrs=[("role", @element.AttrString("alert"))],
                    dyn_style=fn() {
                      if error_new_symbol.get() == "" {
                        "display:none;"
                      } else {
                        "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
                      }
                    },
                    [text_of(error_new_symbol)],
                  ),
                ],
              ),
              button(
                style="background:rgba(99,102,241,0.2);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:8px 16px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;white-space:nowrap;",
                on=events().click(handle_add_symbol),
                [text("追加")],
              ),
            ],
          ),
          div(
            attrs=[("role", @element.AttrString("alert"))],
            dyn_style=fn() {
              if error_symbols.get() == "" {
                "display:none;"
              } else {
                "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
              }
            },
            [text_of(error_symbols)],
          ),
        ],
      ),
      // ── R-03 リスク設定 ───────────────────────────────────────────────────
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:24px;display:flex;flex-direction:column;gap:16px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0;letter-spacing:0.04em;",
            [text("リスク設定")],
          ),
          render_number_input_field(
            "strategy-daily-loss-limit",
            "1日損失上限 (%) *",
            "例: 5.0（0より大きく20以下）",
            daily_loss_limit.get(),
            handle_daily_loss_limit_input,
            error_daily_loss_limit,
          ),
          render_number_input_field(
            "strategy-position-concentration-limit",
            "1銘柄上限 (%) *",
            "例: 30.0（0より大きく50以下）",
            position_concentration_limit.get(),
            handle_position_concentration_limit_input,
            error_position_concentration_limit,
          ),
          render_number_input_field(
            "strategy-daily-order-limit",
            "1日注文上限件数 *",
            "例: 10（1以上100以下）",
            daily_order_limit.get(),
            handle_daily_order_limit_input,
            error_daily_order_limit,
          ),
        ],
      ),
      // ── R-04 操作領域 (strategy) ──────────────────────────────────────────
      div(
        style="display:flex;gap:12px;",
        [
          button(
            dyn_style=fn() {
              let base = "background:var(--color-cta,#6366F1);color:#fff;border:none;border-radius:6px;padding:12px 28px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;"
              if is_saving.get() {
                base + "opacity:0.6;"
              } else {
                base
              }
            },
            on=events().click(handle_save_strategy),
            [
              text_dyn(
                @signal.computed(fn() {
                  if is_saving.get() {
                    "保存中..."
                  } else {
                    "保存"
                  }
                }),
              ),
            ],
          ),
          button(
            style="background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.12);border-radius:6px;padding:12px 28px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;",
            on=events().click(handle_open_reset_modal),
            [text("初期値へ戻す")],
          ),
        ],
      ),
      // ── コンプライアンス制御 ──────────────────────────────────────────────
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:24px;display:flex;flex-direction:column;gap:16px;",
        [
          h1(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;margin:0;letter-spacing:0.04em;",
            [text("コンプライアンス制御")],
          ),
          // 制限銘柄リスト
          div(
            style="display:flex;flex-direction:column;gap:8px;",
            [
              label(
                for_="compliance-restricted-new",
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                [text("制限銘柄リスト")],
              ),
              div(
                dyn_style=fn() {
                  if ffi_array_length(restricted_symbols.get()) > 0 {
                    "display:flex;flex-wrap:wrap;gap:8px;margin-bottom:8px;"
                  } else {
                    "display:none;"
                  }
                },
                ffi_map_symbols_to_chips(
                  restricted_symbols.get(),
                  handle_remove_restricted_symbol,
                ),
              ),
              div(
                style="display:flex;gap:8px;align-items:flex-start;",
                [
                  div(
                    style="display:flex;flex-direction:column;gap:4px;flex:1;max-width:300px;",
                    [
                      input(
                        type_="text",
                        id="compliance-restricted-new",
                        name="compliance-restricted-new",
                        placeholder="銘柄コード（例: AAPL）",
                        style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
                        on=events().input(handle_new_restricted_symbol_input),
                        attrs=[("aria-label", @element.AttrString("追加する制限銘柄コード"))],
                      ),
                      div(
                        attrs=[("role", @element.AttrString("alert"))],
                        dyn_style=fn() {
                          if error_restricted_symbols.get() == "" {
                            "display:none;"
                          } else {
                            "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
                          }
                        },
                        [text_of(error_restricted_symbols)],
                      ),
                    ],
                  ),
                  button(
                    style="background:rgba(99,102,241,0.2);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:8px 16px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;white-space:nowrap;",
                    on=events().click(handle_add_restricted_symbol),
                    [text("追加")],
                  ),
                ],
              ),
            ],
          ),
          // ブラックアウト期間リスト
          div(
            style="display:flex;flex-direction:column;gap:8px;",
            [
              p(
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;margin:0;",
                [text("ブラックアウト期間")],
              ),
              div(
                dyn_style=fn() {
                  if ffi_array_length_blackout(blackout_windows.get()) > 0 {
                    "display:flex;flex-direction:column;gap:6px;margin-bottom:8px;"
                  } else {
                    "display:none;"
                  }
                },
                ffi_map_blackout_windows(
                  blackout_windows.get(),
                  handle_remove_blackout_window,
                ),
              ),
              // Add blackout window form
              div(
                style="display:grid;grid-template-columns:1fr 1fr 1fr 1fr auto;gap:8px;align-items:flex-start;",
                [
                  input(
                    type_="text",
                    id="blackout-symbol",
                    name="blackout-symbol",
                    placeholder="銘柄コード",
                    style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.8125rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
                    on=events().input(handle_new_blackout_symbol_input),
                    attrs=[("aria-label", @element.AttrString("ブラックアウト銘柄コード"))],
                  ),
                  input(
                    type_="text",
                    id="blackout-start-at",
                    name="blackout-start-at",
                    placeholder="開始日時 (ISO8601)",
                    style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.8125rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
                    on=events().input(handle_new_blackout_start_input),
                    attrs=[("aria-label", @element.AttrString("ブラックアウト開始日時"))],
                  ),
                  input(
                    type_="text",
                    id="blackout-end-at",
                    name="blackout-end-at",
                    placeholder="終了日時 (ISO8601)",
                    style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.8125rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
                    on=events().input(handle_new_blackout_end_input),
                    attrs=[("aria-label", @element.AttrString("ブラックアウト終了日時"))],
                  ),
                  input(
                    type_="text",
                    id="blackout-reason",
                    name="blackout-reason",
                    placeholder="理由コード",
                    style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.8125rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
                    on=events().input(handle_new_blackout_reason_input),
                    attrs=[("value", @element.AttrString("MANUAL_OPERATION")), ("aria-label", @element.AttrString("ブラックアウト理由コード"))],
                  ),
                  button(
                    style="background:rgba(99,102,241,0.2);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:8px 14px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;white-space:nowrap;",
                    on=events().click(handle_add_blackout_window),
                    [text("追加")],
                  ),
                ],
              ),
              div(
                attrs=[("role", @element.AttrString("alert"))],
                dyn_style=fn() {
                  if error_blackout_window.get() == "" {
                    "display:none;"
                  } else {
                    "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
                  }
                },
                [text_of(error_blackout_window)],
              ),
            ],
          ),
          // Save compliance button
          button(
            dyn_style=fn() {
              let base = "background:rgba(234,179,8,0.15);color:#EAB308;border:1px solid rgba(234,179,8,0.35);border-radius:6px;padding:12px 28px;font-size:1rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;align-self:flex-start;"
              if is_saving.get() {
                base + "opacity:0.6;"
              } else {
                base
              }
            },
            on=events().click(handle_save_compliance),
            [
              text_dyn(
                @signal.computed(fn() {
                  if is_saving.get() {
                    "保存中..."
                  } else {
                    "コンプライアンス制御を保存"
                  }
                }),
              ),
            ],
          ),
        ],
      ),
      // ── Reset confirmation modal ──────────────────────────────────────────
      div(
        dyn_style=fn() {
          if show_reset_modal.get() {
            "position:fixed;inset:0;background:rgba(0,0,0,0.6);display:flex;align-items:center;justify-content:center;z-index:40;"
          } else {
            "display:none;"
          }
        },
        attrs=[
          ("role", @element.AttrString("dialog")),
          ("aria-modal", @element.AttrString("true")),
          ("aria-label", @element.AttrString("初期値への復元確認")),
        ],
        [
          div(
            style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.12);border-radius:12px;padding:32px;width:100%;max-width:400px;box-sizing:border-box;display:flex;flex-direction:column;gap:20px;",
            [
              p(
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.125rem;font-weight:700;margin:0;",
                [text("初期値に戻しますか？")],
              ),
              p(
                style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0;",
                [
                  text(
                    "現在の変更内容が失われます。ページ読み込み時の値に戻します。",
                  ),
                ],
              ),
              div(
                style="display:flex;gap:12px;justify-content:flex-end;",
                [
                  button(
                    style="background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.12);border-radius:6px;padding:10px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;",
                    on=events().click(handle_cancel_reset),
                    [text("キャンセル")],
                  ),
                  button(
                    style="background:#6366F1;color:#fff;border:none;border-radius:6px;padding:10px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
                    on=events().click(handle_confirm_reset),
                    [text("初期値に戻す")],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  )
}

///|
/// Render a labelled number input field with inline error.
fn render_number_input_field(
  field_id : String,
  label_text : String,
  placeholder_text : String,
  initial_value : String,
  on_input : @element.InputHandler,
  error_signal : @signal.Signal[String]
) -> DomNode {
  div(
    style="display:flex;flex-direction:column;gap:6px;",
    [
      label(
        for_=field_id,
        style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
        [text(label_text)],
      ),
      input(
        type_="text",
        id=field_id,
        name=field_id,
        placeholder=placeholder_text,
        style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;max-width:200px;box-sizing:border-box;",
        on=events().input(on_input),
        attrs=[("value", @element.AttrString(initial_value)), ("inputmode", @element.AttrString("decimal"))],
      ),
      div(
        attrs=[("role", @element.AttrString("alert"))],
        dyn_style=fn() {
          if error_signal.get() == "" {
            "display:none;"
          } else {
            "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
          }
        },
        [text_of(error_signal)],
      ),
    ],
  )
}

// ── FFI helpers ──────────────────────────────────────────────────────────────

///|
extern "js" fn ffi_clone_string_array(arr : Array[String]) -> Array[String] =
  #| (arr) => [...arr]

///|
extern "js" fn ffi_clone_blackout_array(
  arr : Array[BlackoutWindowProps]
) -> Array[BlackoutWindowProps] =
  #| (arr) => arr.map(w => ({ symbol: w.symbol, start_at: w.start_at, end_at: w.end_at, action_reason_code: w.action_reason_code }))

///|
extern "js" fn ffi_array_length(arr : Array[String]) -> Int =
  #| (arr) => arr.length

///|
extern "js" fn ffi_array_length_blackout(
  arr : Array[BlackoutWindowProps]
) -> Int =
  #| (arr) => arr.length

///|
extern "js" fn ffi_array_includes(arr : Array[String], value : String) -> Bool =
  #| (arr, value) => arr.includes(value)

///|
extern "js" fn ffi_array_append(
  arr : Array[String],
  value : String
) -> Array[String] =
  #| (arr, value) => [...arr, value]

///|
extern "js" fn ffi_array_append_blackout(
  arr : Array[BlackoutWindowProps],
  value : BlackoutWindowProps
) -> Array[BlackoutWindowProps] =
  #| (arr, value) => [...arr, value]

///|
extern "js" fn ffi_array_remove(
  arr : Array[String],
  value : String
) -> Array[String] =
  #| (arr, value) => arr.filter(s => s !== value)

///|
extern "js" fn ffi_array_remove_at(
  arr : Array[BlackoutWindowProps],
  index : Int
) -> Array[BlackoutWindowProps] =
  #| (arr, index) => arr.filter((_, i) => i !== index)

///|
extern "js" fn ffi_trim_string(value : String) -> String =
  #| (value) => value.trim()

///|
extern "js" fn ffi_parse_double(value : String) -> Double =
  #| (value) => parseFloat(value) || 0.0

///|
extern "js" fn ffi_parse_int(value : String) -> Int =
  #| (value) => parseInt(value, 10) || 0

///|
extern "js" fn ffi_double_to_string(value : Double) -> String =
  #| (value) => String(value)

///|
extern "js" fn ffi_int_to_string(value : Int) -> String =
  #| (value) => String(value)

///|
extern "js" fn ffi_date_is_before(a : String, b : String) -> Bool =
  #| (a, b) => new Date(a) < new Date(b)

///|
/// Render symbol chips with remove buttons via FFI (dynamic list rendering).
extern "js" fn ffi_render_symbol_chips(arr : Array[String]) -> String =
  #| (arr) => arr.join('、')

///|
/// Map symbol array to chip DomNodes.
extern "js" fn ffi_map_symbols_to_chips(
  arr : Array[String],
  on_remove : (String) -> @element.MouseHandler
) -> Array[DomNode] =
  #| (arr, on_remove) => []

///|
/// Map blackout window array to row DomNodes.
extern "js" fn ffi_map_blackout_windows(
  arr : Array[BlackoutWindowProps],
  on_remove : (Int) -> @element.MouseHandler
) -> Array[DomNode] =
  #| (arr, on_remove) => []

///|
/// PUT /settings/strategy to BFF.
extern "js" fn ffi_put_strategy_settings(
  base_url : String,
  market : String,
  rebalance_frequency : String,
  symbols : Array[String],
  daily_loss_limit : Double,
  position_concentration_limit : Double,
  daily_order_limit : Int,
  on_result : (Bool, String) -> Unit
) -> Unit =
  #| (base_url, market, rebalance_frequency, symbols, daily_loss_limit, position_concentration_limit, daily_order_limit, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   fetch(base_url + '/settings/strategy', {
  #|     method: 'PUT',
  #|     headers: {
  #|       'Content-Type': 'application/json',
  #|       ...(token ? { 'Authorization': 'Bearer ' + token } : {}),
  #|     },
  #|     body: JSON.stringify({
  #|       market,
  #|       rebalanceFrequency: rebalance_frequency,
  #|       symbols,
  #|       dailyLossLimit: daily_loss_limit,
  #|       positionConcentrationLimit: position_concentration_limit,
  #|       dailyOrderLimit: daily_order_limit,
  #|     }),
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data.success) {
  #|       on_result(true, '');
  #|     } else {
  #|       const msg = (data && data.detail) || '設定の保存に失敗しました。再試行してください。';
  #|       on_result(false, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, '設定の保存に失敗しました。再試行してください。'));
  #| }

///|
/// PUT /compliance/controls to BFF.
extern "js" fn ffi_put_compliance_controls(
  base_url : String,
  restricted_symbols : Array[String],
  blackout_windows : Array[BlackoutWindowProps],
  on_result : (Bool, String) -> Unit
) -> Unit =
  #| (base_url, restricted_symbols, blackout_windows, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const windows = blackout_windows.map(w => ({
  #|     symbol: w.symbol,
  #|     startAt: w.start_at,
  #|     endAt: w.end_at,
  #|     actionReasonCode: w.action_reason_code,
  #|   }));
  #|   fetch(base_url + '/compliance/controls', {
  #|     method: 'PUT',
  #|     headers: {
  #|       'Content-Type': 'application/json',
  #|       ...(token ? { 'Authorization': 'Bearer ' + token } : {}),
  #|     },
  #|     body: JSON.stringify({ restrictedSymbols: restricted_symbols, blackoutWindows: windows }),
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data.success) {
  #|       on_result(true, '');
  #|     } else {
  #|       const msg = (data && data.detail) || 'コンプライアンス設定の保存に失敗しました。再試行してください。';
  #|       on_result(false, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, 'コンプライアンス設定の保存に失敗しました。再試行してください。'));
  #| }
