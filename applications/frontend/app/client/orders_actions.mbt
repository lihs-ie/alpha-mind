///| Orders Actions Island Component (SCR-003)
///|
///| Interactive order management panel: status filter, per-order approve/reject/retry
///| actions gated by the Orders state machine, and a reject confirmation modal.
///| This is a client component: it runs in the browser after hydration.
///|
///| Orders state machine (documents/外部設計/state/状態遷移設計.md §3):
///|   PROPOSED --approve--> APPROVED
///|   PROPOSED --reject--> REJECTED (terminal)
///|   APPROVED --execution--> EXECUTED (terminal) | FAILED
///|   FAILED --retry--> PROPOSED
///|   EXECUTED / REJECTED are terminal (no mutating action).
///|
///| Operations:
///|  - A-0031 承認: POST /orders/{identifier}/approve   (pre: status=PROPOSED, kill switch disabled)
///|  - A-0032 却下: POST /orders/{identifier}/reject    (pre: status=PROPOSED, actionReasonCode required)
///|  - A-0033 再送: POST /orders/{identifier}/retry     (pre: status=FAILED)
///|  - A-0034 フィルタ適用: re-fetch GET /orders?status=...
///|
///| Ref: documents/外部設計/screens/SCR-003_注文管理.md
///| Ref: documents/外部設計/api/openapi.yaml
///| Ref: documents/外部設計/state/状態遷移設計.md

///|
/// A single order row passed from the server (SSR initial state).
pub(all) struct OrderRowProps {
  identifier : String
  symbol : String
  side : String
  qty : Double
  status : String
  created_at : String
} derive(ToJson, FromJson)

///|
/// Props passed from the server (SSR initial state).
pub(all) struct OrdersActionsProps {
  bff_base_url : String
  initial_orders : Array[OrderRowProps]
  initial_kill_switch_enabled : Bool
} derive(ToJson, FromJson)

// ── Pure state-machine logic (unit-tested) ───────────────────────────────────

///|
/// Whether the 承認 (approve) action is permitted for a status, given kill switch.
/// approve is only valid from PROPOSED, and is blocked while kill switch is enabled.
pub fn can_approve(status : String, kill_switch_enabled : Bool) -> Bool {
  status == "PROPOSED" && not(kill_switch_enabled)
}

///|
/// Whether the 却下 (reject) action is permitted for a status.
/// reject is only valid from PROPOSED.
pub fn can_reject(status : String) -> Bool {
  status == "PROPOSED"
}

///|
/// Whether the 再送 (retry) action is permitted for a status.
/// retry is only valid from FAILED.
pub fn can_retry(status : String) -> Bool {
  status == "FAILED"
}

///|
/// Validate a reject submission. Returns an error message, or "" when valid.
/// Rules (SCR-003 §5): actionReasonCode required; comment <= 120 chars.
pub fn validate_reject(reason_code : String, comment : String) -> String {
  if reason_code == "" {
    "却下理由コードを選択してください"
  } else if ffi_string_length(comment) > 120 {
    "コメントは120文字以内で入力してください"
  } else {
    ""
  }
}

// ── Island ───────────────────────────────────────────────────────────────────

///|
/// Orders Actions Island component.
pub fn orders_actions(props : OrdersActionsProps) -> DomNode {
  let orders = @signal.signal(ffi_clone_orders(props.initial_orders))
  let kill_switch_enabled = @signal.signal(props.initial_kill_switch_enabled)
  let status_filter = @signal.signal("")
  let is_loading = @signal.signal(false)
  let status_message = @signal.signal("")
  let status_is_error = @signal.signal(false)

  // Reject modal state
  let show_reject_modal = @signal.signal(false)
  let reject_target = @signal.signal("")
  let reject_reason_code = @signal.signal("")
  let reject_comment = @signal.signal("")
  let reject_validation_error = @signal.signal("")

  // ── Filter handlers ─────────────────────────────────────────────────────────

  let handle_status_filter_change : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    status_filter.set(target.value)
  }

  let handle_apply_filter : @element.MouseHandler = fn(_e) {
    if is_loading.get() {
      return
    }
    is_loading.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let status = status_filter.get()
    let rows = orders
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    ffi_fetch_orders(
      base_url,
      status,
      fn(success, fetched, error_message) {
        loading.set(false)
        if success {
          rows.set(fetched)
          is_err.set(false)
          msg.set("")
        } else {
          is_err.set(true)
          msg.set("✗ " + error_message)
        }
      },
    )
  }

  // ── Approve handler ─────────────────────────────────────────────────────────

  let handle_approve : (String) -> @element.MouseHandler = fn(identifier) {
    fn(_e) {
      if is_loading.get() {
        return
      }
      if kill_switch_enabled.get() {
        status_is_error.set(true)
        status_message.set("⚠ kill switch有効中のため承認できません。")
        return
      }
      is_loading.set(true)
      status_message.set("")
      let base_url = props.bff_base_url
      let rows = orders
      let loading = is_loading
      let msg = status_message
      let is_err = status_is_error
      ffi_post_order_action(
        base_url,
        identifier,
        "approve",
        "",
        "",
        fn(success, error_message) {
          loading.set(false)
          if success {
            rows.set(ffi_set_order_status(rows.get(), identifier, "APPROVED"))
            is_err.set(false)
            msg.set("✓ 注文を承認しました。")
          } else {
            is_err.set(true)
            msg.set("✗ 注文更新に失敗しました。 " + error_message)
          }
        },
      )
    }
  }

  // ── Reject handlers (modal) ─────────────────────────────────────────────────

  let handle_open_reject_modal : (String) -> @element.MouseHandler = fn(
    identifier
  ) {
    fn(_e) {
      if is_loading.get() {
        return
      }
      reject_target.set(identifier)
      reject_reason_code.set("")
      reject_comment.set("")
      reject_validation_error.set("")
      show_reject_modal.set(true)
    }
  }

  let handle_reject_reason_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    reject_reason_code.set(target.value)
    reject_validation_error.set("")
  }

  let handle_reject_comment_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    reject_comment.set(target.value)
    reject_validation_error.set("")
  }

  let handle_reject_cancel : @element.MouseHandler = fn(_e) {
    show_reject_modal.set(false)
  }

  let handle_reject_confirm : @element.MouseHandler = fn(_e) {
    let reason = reject_reason_code.get()
    let comment = reject_comment.get()
    let validation = validate_reject(reason, comment)
    if validation != "" {
      reject_validation_error.set(validation)
      return
    }
    let identifier = reject_target.get()
    show_reject_modal.set(false)
    is_loading.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let rows = orders
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    ffi_post_order_action(
      base_url,
      identifier,
      "reject",
      reason,
      comment,
      fn(success, error_message) {
        loading.set(false)
        if success {
          rows.set(ffi_set_order_status(rows.get(), identifier, "REJECTED"))
          is_err.set(false)
          msg.set("✓ 注文を却下しました。")
        } else {
          is_err.set(true)
          msg.set("✗ 注文更新に失敗しました。 " + error_message)
        }
      },
    )
  }

  // ── Retry handler ───────────────────────────────────────────────────────────

  let handle_retry : (String) -> @element.MouseHandler = fn(identifier) {
    fn(_e) {
      if is_loading.get() {
        return
      }
      is_loading.set(true)
      status_message.set("")
      let base_url = props.bff_base_url
      let rows = orders
      let loading = is_loading
      let msg = status_message
      let is_err = status_is_error
      ffi_post_order_action(
        base_url,
        identifier,
        "retry",
        "",
        "",
        fn(success, error_message) {
          loading.set(false)
          if success {
            rows.set(ffi_set_order_status(rows.get(), identifier, "PROPOSED"))
            is_err.set(false)
            msg.set("✓ 再送を受け付けました。")
          } else {
            is_err.set(true)
            msg.set("✗ 注文更新に失敗しました。 " + error_message)
          }
        },
      )
    }
  }

  // ── Render ───────────────────────────────────────────────────────────────────

  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      // Status message area (aria-live for a11y)
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
      // Kill switch warning (R-06 disabled state)
      div(
        dyn_style=fn() {
          if kill_switch_enabled.get() {
            "padding:10px 16px;border-radius:6px;background:rgba(234,179,8,0.12);border:1px solid rgba(234,179,8,0.35);color:#EAB308;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
          } else {
            "display:none;"
          }
        },
        attrs=[("role", @element.AttrString("status"))],
        [text("⚠ kill switch有効中のため承認できません。")],
      ),
      // ── R-01 フィルタ領域 ──────────────────────────────────────────────────
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
                style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;min-width:280px;box-sizing:border-box;",
                on=events().input(handle_status_filter_change),
                attrs=[
                  ("aria-label", @element.AttrString("注文状態フィルタ")),
                ],
              ),
            ],
          ),
          button(
            dyn_style=fn() {
              let base = "background:rgba(99,102,241,0.2);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:8px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;white-space:nowrap;"
              if is_loading.get() {
                base + "opacity:0.6;cursor:not-allowed;"
              } else {
                base + "cursor:pointer;"
              }
            },
            on=events().click(handle_apply_filter),
            [
              text_dyn(
                @signal.computed(fn() {
                  if is_loading.get() {
                    "適用中..."
                  } else {
                    "フィルタ適用"
                  }
                }),
              ),
            ],
          ),
        ],
      ),
      // ── R-02 注文一覧 + R-04 操作領域 ──────────────────────────────────────
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
        attrs=[
          ("role", @element.AttrString("table")),
          ("aria-label", @element.AttrString("注文一覧")),
        ],
        [
          // Header row (column headers — A11y: header cells defined)
          render_order_header(),
          // Empty state message (R-06 empty)
          div(
            attrs=[("role", @element.AttrString("status"))],
            dyn_style=fn() {
              if ffi_orders_length(orders.get()) == 0 {
                "padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
              } else {
                "display:none;"
              }
            },
            [text("該当する注文がありません。")],
          ),
          // Order rows — reactive list. `for_each` re-renders when the `orders`
          // (or `kill_switch_enabled`) signal changes (filter apply / action result).
          for_each(fn() { orders.get() }, fn(order, _index) {
            render_order_row(
              order,
              kill_switch_enabled.get(),
              handle_approve(order.identifier),
              handle_open_reject_modal(order.identifier),
              handle_retry(order.identifier),
            )
          }),
        ],
      ),
      // ── 却下確認モーダル ──────────────────────────────────────────────────
      div(
        dyn_style=fn() {
          if show_reject_modal.get() {
            "position:fixed;inset:0;background:rgba(0,0,0,0.6);display:flex;align-items:center;justify-content:center;z-index:40;"
          } else {
            "display:none;"
          }
        },
        attrs=[
          ("role", @element.AttrString("dialog")),
          ("aria-modal", @element.AttrString("true")),
          ("aria-label", @element.AttrString("注文却下確認")),
        ],
        [
          div(
            style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.12);border-radius:12px;padding:32px;width:100%;max-width:440px;box-sizing:border-box;display:flex;flex-direction:column;gap:20px;",
            [
              p(
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.125rem;font-weight:700;margin:0;",
                [text("注文を却下しますか？")],
              ),
              p(
                style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0;",
                [text("却下理由コードを選択し、確認後に実行してください。")],
              ),
              // Reason code input
              div(
                style="display:flex;flex-direction:column;gap:6px;",
                [
                  label(
                    for_="reject-reason-code",
                    style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                    [text("却下理由コード *")],
                  ),
                  input(
                    type_="text",
                    id="reject-reason-code",
                    name="reject-reason-code",
                    placeholder="例: MANUAL_OPERATION / RISK_REJECTION",
                    style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
                    on=events().input(handle_reject_reason_input),
                  ),
                ],
              ),
              // Comment input
              div(
                style="display:flex;flex-direction:column;gap:6px;",
                [
                  label(
                    for_="reject-comment",
                    style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                    [text("コメント（任意、120文字以内）")],
                  ),
                  input(
                    type_="text",
                    id="reject-comment",
                    name="reject-comment",
                    placeholder="却下理由を入力...",
                    style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;width:100%;box-sizing:border-box;",
                    on=events().input(handle_reject_comment_input),
                  ),
                  div(
                    attrs=[("role", @element.AttrString("alert"))],
                    dyn_style=fn() {
                      if reject_validation_error.get() == "" {
                        "display:none;"
                      } else {
                        "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
                      }
                    },
                    [text_of(reject_validation_error)],
                  ),
                ],
              ),
              // Modal actions
              div(
                style="display:flex;gap:12px;justify-content:flex-end;",
                [
                  button(
                    style="background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.12);border-radius:6px;padding:10px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;",
                    on=events().click(handle_reject_cancel),
                    [text("キャンセル")],
                  ),
                  button(
                    style="background:#F87171;color:#fff;border:none;border-radius:6px;padding:10px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
                    on=events().click(handle_reject_confirm),
                    [text("却下する")],
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

// ── FFI helpers ──────────────────────────────────────────────────────────────
// Note: ffi_string_length (dashboard_operations.mbt) and ffi_int_to_string
// (strategy_form.mbt) are already defined at package scope and reused here.

///|
extern "js" fn ffi_clone_orders(
  arr : Array[OrderRowProps]
) -> Array[OrderRowProps] =
  #| (arr) => arr.map(o => ({ identifier: o.identifier, symbol: o.symbol, side: o.side, qty: o.qty, status: o.status, created_at: o.created_at }))

///|
extern "js" fn ffi_orders_length(arr : Array[OrderRowProps]) -> Int =
  #| (arr) => arr.length

///|
/// Immutably set the status of the order with the given identifier.
extern "js" fn ffi_set_order_status(
  arr : Array[OrderRowProps],
  identifier : String,
  status : String
) -> Array[OrderRowProps] =
  #| (arr, identifier, status) => arr.map(o => o.identifier === identifier ? ({ ...o, status }) : o)

///|
/// Format an order quantity as a grouped integer/decimal (`#,##0`).
extern "js" fn ffi_format_qty(value : Double) -> String =
  #| (value) => value.toLocaleString('ja-JP', { maximumFractionDigits: 4 })

// ── Row rendering (real DomNodes, state-gated buttons) ────────────────────────

///|
/// Background/foreground colours for a status badge.
/// EXECUTED uses profit semantics; REJECTED/FAILED use loss semantics.
fn status_badge_style(status : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = match status {
    "EXECUTED" =>
      "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
    "APPROVED" =>
      "background:rgba(99,102,241,0.15);color:#818CF8;border:1px solid rgba(99,102,241,0.35);"
    "PROPOSED" =>
      "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
    "REJECTED" =>
      "background:rgba(248,113,113,0.12);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.35);"
    "FAILED" =>
      "background:rgba(248,113,113,0.18);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.5);"
    _ =>
      "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// Header row for the orders list (A11y: columnheader cells).
fn render_order_header() -> DomNode {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style="display:grid;grid-template-columns:minmax(220px,2fr) 1fr 0.7fr 1fr 1fr 1.6fr minmax(220px,1.6fr);align-items:center;border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @element.AttrString("row"))],
    [
      div(style=cell, attrs=[("role", @element.AttrString("columnheader"))], [
        text("注文ID"),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("columnheader"))], [
        text("銘柄"),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("columnheader"))], [
        text("売買"),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("columnheader"))], [
        text("数量"),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("columnheader"))], [
        text("状態"),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("columnheader"))], [
        text("作成日時"),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("columnheader"))], [
        text("操作"),
      ]),
    ],
  )
}

///|
/// Render a single order row, with state-gated action buttons.
fn render_order_row(
  order : OrderRowProps,
  kill_switch_enabled : Bool,
  on_approve : @element.MouseHandler,
  on_reject : @element.MouseHandler,
  on_retry : @element.MouseHandler
) -> DomNode {
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  let mono_num = mono + "text-align:right;"
  let side_color = if order.side == "BUY" {
    "color:var(--color-profit,#22C55E);"
  } else {
    "color:var(--color-loss,#F87171);"
  }
  div(
    style="display:grid;grid-template-columns:minmax(220px,2fr) 1fr 0.7fr 1fr 1fr 1.6fr minmax(220px,1.6fr);align-items:center;border-bottom:1px solid rgba(248,250,252,0.06);",
    attrs=[("role", @element.AttrString("row"))],
    [
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        code(style="font-family:'JetBrains Mono',monospace;", [
          text(order.identifier),
        ]),
      ]),
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        text(order.symbol),
      ]),
      div(
        style=mono + side_color + "font-weight:600;",
        attrs=[("role", @element.AttrString("cell"))],
        [text(order.side)],
      ),
      div(style=mono_num, attrs=[("role", @element.AttrString("cell"))], [
        text(ffi_format_qty(order.qty)),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        span(style=status_badge_style(order.status), [text(order.status)]),
      ]),
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        text(order.created_at),
      ]),
      // R-04 操作領域 — state-gated action buttons.
      div(
        style="padding:8px 12px;display:flex;gap:8px;align-items:center;",
        attrs=[("role", @element.AttrString("cell"))],
        [
          render_action_buttons(
            order.status,
            kill_switch_enabled,
            on_approve,
            on_reject,
            on_retry,
          ),
        ],
      ),
    ],
  )
}

///|
/// Render the action buttons applicable to an order's status (state machine).
/// PROPOSED → approve (kill-switch-gated) + reject; FAILED → retry;
/// APPROVED/EXECUTED/REJECTED → no mutating action ("—").
fn render_action_buttons(
  status : String,
  kill_switch_enabled : Bool,
  on_approve : @element.MouseHandler,
  on_reject : @element.MouseHandler,
  on_retry : @element.MouseHandler
) -> DomNode {
  let approve_allowed = can_approve(status, kill_switch_enabled)
  let reject_allowed = can_reject(status)
  let retry_allowed = can_retry(status)
  if not(reject_allowed) && not(retry_allowed) {
    // No mutating action for APPROVED / EXECUTED / REJECTED (terminal/in-flight).
    span(
      style="color:rgba(248,250,252,0.35);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
      [text("—")],
    )
  } else {
    let children : Array[DomNode] = []
    if reject_allowed {
      // approve button: disabled (aria-disabled) when kill switch blocks it.
      children.push(
        button(
          disabled=not(approve_allowed),
          style=if approve_allowed {
            "background:rgba(34,197,94,0.15);color:#22C55E;border:1px solid rgba(34,197,94,0.4);border-radius:6px;padding:6px 14px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;"
          } else {
            "background:rgba(248,250,252,0.05);color:rgba(248,250,252,0.35);border:1px solid rgba(248,250,252,0.1);border-radius:6px;padding:6px 14px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:not-allowed;"
          },
          attrs=[
            (
              "aria-disabled",
              @element.AttrString(if approve_allowed { "false" } else { "true" }),
            ),
          ],
          on=if approve_allowed { events().click(on_approve) } else { events() },
          [text("承認")],
        ),
      )
      children.push(
        button(
          style="background:rgba(248,113,113,0.12);color:#F87171;border:1px solid rgba(248,113,113,0.4);border-radius:6px;padding:6px 14px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
          on=events().click(on_reject),
          [text("却下")],
        ),
      )
    }
    if retry_allowed {
      children.push(
        button(
          style="background:rgba(99,102,241,0.15);color:#818CF8;border:1px solid rgba(99,102,241,0.4);border-radius:6px;padding:6px 14px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
          on=events().click(on_retry),
          [text("再送")],
        ),
      )
    }
    fragment(children)
  }
}

///|
/// Fetch the order list from BFF GET /orders (optionally filtered by status).
/// Maps the OpenAPI OrderListResponse into OrderRowProps[].
extern "js" fn ffi_fetch_orders(
  base_url : String,
  status : String,
  on_result : (Bool, Array[OrderRowProps], String) -> Unit
) -> Unit =
  #| (base_url, status, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const url = new URL('/orders', base_url);
  #|   if (status) url.searchParams.set('status', status);
  #|   fetch(url.toString(), {
  #|     method: 'GET',
  #|     headers: { ...(token ? { 'Authorization': 'Bearer ' + token } : {}) },
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data && Array.isArray(data.items)) {
  #|       const rows = data.items.map(o => ({
  #|         identifier: o.identifier ?? '',
  #|         symbol: o.symbol ?? '',
  #|         side: o.side ?? '',
  #|         qty: o.qty ?? 0.0,
  #|         status: o.status ?? '',
  #|         created_at: o.createdAt ?? '',
  #|       }));
  #|       on_result(true, rows, '');
  #|     } else {
  #|       const msg = (data && data.detail) || '一覧の取得に失敗しました。再試行してください。';
  #|       on_result(false, [], msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, [], '一覧の取得に失敗しました。再試行してください。'));
  #| }

///|
/// POST an order action (approve | reject | retry) to the BFF.
/// reject sends actionReasonCode (required) + optional comment.
extern "js" fn ffi_post_order_action(
  base_url : String,
  identifier : String,
  action : String,
  reason_code : String,
  comment : String,
  on_result : (Bool, String) -> Unit
) -> Unit =
  #| (base_url, identifier, action, reason_code, comment, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const body = {};
  #|   if (action === 'reject') {
  #|     if (reason_code) body.actionReasonCode = reason_code;
  #|     if (comment) body.comment = comment;
  #|   }
  #|   fetch(base_url + '/orders/' + encodeURIComponent(identifier) + '/' + action, {
  #|     method: 'POST',
  #|     headers: {
  #|       'Content-Type': 'application/json',
  #|       ...(token ? { 'Authorization': 'Bearer ' + token } : {}),
  #|     },
  #|     body: JSON.stringify(body),
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })).catch(() => ({ ok: res.ok, data: {} })))
  #|   .then(({ ok, data }) => {
  #|     // approve/reject return OperationResult{success}; retry returns CommandAccepted{accepted}.
  #|     const accepted = ok && (data.success === true || data.accepted === true || (action === 'retry' && ok));
  #|     if (accepted) {
  #|       on_result(true, '');
  #|     } else {
  #|       const msg = (data && data.detail) || '注文更新に失敗しました。再試行してください。';
  #|       on_result(false, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, '注文更新に失敗しました。再試行してください。'));
  #| }
