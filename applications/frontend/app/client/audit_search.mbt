///| Audit Search Island Component (SCR-004)
///|
///| Interactive audit-log panel: search filter (期間 From/To · eventType · trace),
///| reactive log table, per-row detail expansion (GET /audit/{identifier}), and a
///| trace-copy action with an aria-live notification.
///| This is a client component: it runs in the browser after hydration.
///|
///| Operations (documents/外部設計/screens/SCR-004_監査ログ.md §4):
///|  - A-0041 検索:        re-fetch GET /audit?trace=&eventType=&from=&to=&limit=
///|  - A-0042 traceコピー: copy trace to clipboard → MSG-I-0041 (aria-live)
///|  - 行選択 (R-03):      GET /audit/{identifier} → payload要約 + reason 表示
///|
///| Screen states (§6): initial / loading (skeleton) / empty / error.
///|
///| Ref: documents/外部設計/screens/SCR-004_監査ログ.md
///| Ref: documents/外部設計/api/openapi.yaml (/audit, /audit/{identifier})

///|
/// A single audit-log row passed from the server (SSR initial state) or fetched
/// from BFF GET /audit. Mirrors the OpenAPI AuditSummary schema.
pub(all) struct AuditRowProps {
  identifier : String
  occurred_at : String
  event_type : String
  service : String
  result : String
  trace : String
} derive(ToJson, FromJson)

///|
/// Props passed from the server (SSR initial state).
pub(all) struct AuditSearchProps {
  bff_base_url : String
  initial_logs : Array[AuditRowProps]
} derive(ToJson, FromJson)

// ── Pure logic (unit-tested) ─────────────────────────────────────────────────

///|
/// Validate the search conditions (SCR-004 §5).
/// Returns an error message, or "" when valid.
/// Rules:
///   - 期間 From/To: From <= To  (empty endpoints are treated as unbounded → valid)
///   - trace: ULID 形式 (`^[0-9A-HJKMNP-TV-Z]{26}$`); empty = 未指定 (valid)
pub fn validate_audit_search(
  from : String,
  to : String,
  trace : String
) -> String {
  if from != "" && to != "" && from > to {
    "期間の指定が不正です"
  } else if trace != "" && not(is_valid_ulid(trace)) {
    "trace形式が不正です"
  } else {
    ""
  }
}

///|
/// Whether a string is a valid Crockford-base32 ULID (26 chars, no I/L/O/U).
pub fn is_valid_ulid(value : String) -> Bool {
  ffi_is_valid_ulid(value)
}

///|
extern "js" fn ffi_is_valid_ulid(value : String) -> Bool =
  #| (value) => /^[0-9A-HJKMNP-TV-Z]{26}$/.test(value)

// ── Island ───────────────────────────────────────────────────────────────────

///|
/// Audit Search Island component.
pub fn audit_search(props : AuditSearchProps) -> DomNode {
  let logs = @signal.signal(ffi_clone_audit_logs(props.initial_logs))
  let from_value = @signal.signal("")
  let to_value = @signal.signal("")
  let event_type_value = @signal.signal("")
  let trace_value = @signal.signal("")
  let is_loading = @signal.signal(false)
  let validation_error = @signal.signal("")
  let status_message = @signal.signal("")
  let status_is_error = @signal.signal(false)
  let copy_message = @signal.signal("")

  // Detail (R-03) state.
  let selected_identifier = @signal.signal("")
  let detail_loading = @signal.signal(false)
  let detail_event_type = @signal.signal("")
  let detail_reason = @signal.signal("")
  let detail_payload = @signal.signal("")
  let detail_error = @signal.signal("")

  // ── Input handlers ────────────────────────────────────────────────────────

  let handle_from_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    from_value.set(target.value)
    validation_error.set("")
  }
  let handle_to_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    to_value.set(target.value)
    validation_error.set("")
  }
  let handle_event_type_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    event_type_value.set(target.value)
  }
  let handle_trace_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    trace_value.set(target.value)
    validation_error.set("")
  }

  // ── A-0041 検索 ───────────────────────────────────────────────────────────

  let handle_search : @element.MouseHandler = fn(_e) {
    if is_loading.get() {
      return
    }
    let from = from_value.get()
    let to = to_value.get()
    let event_type = event_type_value.get()
    let trace = trace_value.get()
    let validation = validate_audit_search(from, to, trace)
    if validation != "" {
      validation_error.set(validation)
      return
    }
    validation_error.set("")
    is_loading.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let rows = logs
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    ffi_fetch_audit(
      base_url,
      trace,
      event_type,
      from,
      to,
      50,
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

  // ── 行選択 (R-03 詳細) ─────────────────────────────────────────────────────

  let handle_select : (String) -> @element.MouseHandler = fn(identifier) {
    fn(_e) {
      if detail_loading.get() {
        return
      }
      selected_identifier.set(identifier)
      detail_loading.set(true)
      detail_error.set("")
      detail_event_type.set("")
      detail_reason.set("")
      detail_payload.set("")
      let base_url = props.bff_base_url
      let loading = detail_loading
      let ev = detail_event_type
      let reason = detail_reason
      let payload = detail_payload
      let err = detail_error
      ffi_fetch_audit_detail(
        base_url,
        identifier,
        fn(success, event_type, reason_value, payload_summary, error_message) {
          loading.set(false)
          if success {
            ev.set(event_type)
            reason.set(reason_value)
            payload.set(payload_summary)
            err.set("")
          } else {
            err.set("✗ " + error_message)
          }
        },
      )
    }
  }

  // ── A-0042 traceコピー ─────────────────────────────────────────────────────

  let handle_copy_trace : (String) -> @element.MouseHandler = fn(trace) {
    fn(_e) {
      let notify = copy_message
      ffi_copy_to_clipboard(trace, fn(success) {
        if success {
          notify.set("traceをコピーしました。")
        } else {
          notify.set("traceのコピーに失敗しました。")
        }
      })
    }
  }

  // ── Render ─────────────────────────────────────────────────────────────────

  div(
    style="display:flex;flex-direction:column;gap:24px;",
    [
      // Copy notification (aria-live) — MSG-I-0041
      div(
        attrs=[
          ("role", @element.AttrString("status")),
          ("aria-live", @element.AttrString("polite")),
        ],
        dyn_style=fn() {
          if copy_message.get() == "" {
            "display:none;"
          } else {
            "padding:8px 14px;border-radius:6px;background:rgba(99,102,241,0.12);border:1px solid rgba(99,102,241,0.3);color:#818CF8;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
          }
        },
        [text_of(copy_message)],
      ),
      // Fetch status / error (aria-live) — MSG-E-0041
      div(
        attrs=[
          ("role", @element.AttrString("alert")),
          ("aria-live", @element.AttrString("polite")),
        ],
        dyn_style=fn() {
          if status_message.get() == "" {
            "display:none;"
          } else if status_is_error.get() {
            "padding:10px 16px;border-radius:6px;background:rgba(248,113,113,0.12);border:1px solid rgba(248,113,113,0.3);color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
          } else {
            "padding:10px 16px;border-radius:6px;background:rgba(34,197,94,0.12);border:1px solid rgba(34,197,94,0.3);color:#22C55E;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
          }
        },
        [text_of(status_message)],
      ),
      // ── R-01 検索条件 ───────────────────────────────────────────────────────
      render_search_form(
        from_value,
        to_value,
        event_type_value,
        trace_value,
        validation_error,
        is_loading,
        handle_from_input,
        handle_to_input,
        handle_event_type_input,
        handle_trace_input,
        handle_search,
      ),
      // ── R-02 ログ一覧 ───────────────────────────────────────────────────────
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
        attrs=[
          ("role", @element.AttrString("table")),
          ("aria-label", @element.AttrString("監査ログ一覧")),
        ],
        [
          render_audit_header(),
          // Loading skeleton (§6 loading)
          div(
            attrs=[("role", @element.AttrString("status"))],
            dyn_style=fn() {
              if is_loading.get() {
                "padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
              } else {
                "display:none;"
              }
            },
            [text("読み込み中...")],
          ),
          // Empty state (§6 empty)
          div(
            attrs=[("role", @element.AttrString("status"))],
            dyn_style=fn() {
              if not(is_loading.get()) && ffi_audit_length(logs.get()) == 0 {
                "padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
              } else {
                "display:none;"
              }
            },
            [text("該当するログがありません。")],
          ),
          // Reactive rows — re-render when `logs` signal changes (search apply).
          for_each(fn() { logs.get() }, fn(row, _index) {
            render_audit_row(
              row,
              handle_select(row.identifier),
              handle_copy_trace(row.trace),
            )
          }),
        ],
      ),
      // ── R-03 ログ詳細 (選択時) ──────────────────────────────────────────────
      render_detail_panel(
        selected_identifier,
        detail_loading,
        detail_event_type,
        detail_reason,
        detail_payload,
        detail_error,
      ),
    ],
  )
}

// ── R-01 search form ──────────────────────────────────────────────────────────

///|
fn render_search_form(
  from_value : @signal.Signal[String],
  to_value : @signal.Signal[String],
  event_type_value : @signal.Signal[String],
  trace_value : @signal.Signal[String],
  validation_error : @signal.Signal[String],
  is_loading : @signal.Signal[Bool],
  on_from : @element.InputHandler,
  on_to : @element.InputHandler,
  on_event_type : @element.InputHandler,
  on_trace : @element.InputHandler,
  on_search : @element.MouseHandler
) -> DomNode {
  let field_label = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;"
  let field_input = "background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;"
  ignore(on_from)
  ignore(on_to)
  div(
    style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:16px 24px;display:flex;flex-direction:column;gap:16px;",
    [
      div(
        style="display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:16px;align-items:end;",
        [
          // 期間 From
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(for_="audit-from", style=field_label, [text("期間 From")]),
            input(
              type_="datetime-local",
              id="audit-from",
              name="audit-from",
              style=field_input,
              on=events().input(on_from),
              attrs=[("aria-label", @element.AttrString("検索期間 From"))],
            ),
          ]),
          // 期間 To
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(for_="audit-to", style=field_label, [text("期間 To")]),
            input(
              type_="datetime-local",
              id="audit-to",
              name="audit-to",
              style=field_input,
              on=events().input(on_to),
              attrs=[("aria-label", @element.AttrString("検索期間 To"))],
            ),
          ]),
          // eventType
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(for_="audit-event-type", style=field_label, [
              text("イベント種別"),
            ]),
            input(
              type_="text",
              id="audit-event-type",
              name="audit-event-type",
              placeholder="例: order.approved（空=全件）",
              style=field_input,
              on=events().input(on_event_type),
              attrs=[("aria-label", @element.AttrString("イベント種別フィルタ"))],
            ),
          ]),
          // trace
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(for_="audit-trace", style=field_label, [text("trace")]),
            input(
              type_="text",
              id="audit-trace",
              name="audit-trace",
              placeholder="ULID（空=全件）",
              style=field_input,
              on=events().input(on_trace),
              attrs=[("aria-label", @element.AttrString("traceフィルタ"))],
            ),
          ]),
        ],
      ),
      // Validation error (item-level, §5)
      div(
        attrs=[("role", @element.AttrString("alert"))],
        dyn_style=fn() {
          if validation_error.get() == "" {
            "display:none;"
          } else {
            "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
          }
        },
        [text_of(validation_error)],
      ),
      // 検索 button (A-0041)
      div(style="display:flex;justify-content:flex-end;", [
        button(
          dyn_style=fn() {
            let base = "background:rgba(99,102,241,0.2);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:8px 24px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;white-space:nowrap;"
            if is_loading.get() {
              base + "opacity:0.6;cursor:not-allowed;"
            } else {
              base + "cursor:pointer;"
            }
          },
          on=events().click(on_search),
          [
            text_dyn(
              @signal.computed(fn() {
                if is_loading.get() {
                  "検索中..."
                } else {
                  "検索"
                }
              }),
            ),
          ],
        ),
      ]),
    ],
  )
}

// ── R-02 table rendering ──────────────────────────────────────────────────────

///|
/// Header row for the audit list (A11y: columnheader cells).
fn render_audit_header() -> DomNode {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style=audit_grid_style() +
      "border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @element.AttrString("row"))],
    [
      header_cell(cell, "発生時刻"),
      header_cell(cell, "イベント種別"),
      header_cell(cell, "サービス"),
      header_cell(cell, "result"),
      header_cell(cell, "trace"),
      header_cell(cell, "操作"),
    ],
  )
}

///|
fn header_cell(style : String, label_text : String) -> DomNode {
  div(style=style, attrs=[("role", @element.AttrString("columnheader"))], [
    text(label_text),
  ])
}

///|
/// Shared CSS grid template for header and rows (column alignment).
fn audit_grid_style() -> String {
  "display:grid;grid-template-columns:1.4fr 1.4fr 1fr 0.8fr minmax(220px,1.6fr) minmax(160px,1fr);align-items:center;"
}

///|
/// Background/foreground colours for a result badge (success=profit, failed=loss).
fn result_badge_style(result : String) -> String {
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
/// Render a single audit-log row. Row is selectable (R-03) and exposes a
/// trace-copy action (A-0042).
fn render_audit_row(
  row : AuditRowProps,
  on_select : @element.MouseHandler,
  on_copy_trace : @element.MouseHandler
) -> DomNode {
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  div(
    style=audit_grid_style() +
      "border-bottom:1px solid rgba(248,250,252,0.06);cursor:pointer;",
    attrs=[
      ("role", @element.AttrString("row")),
      ("tabindex", @element.AttrString("0")),
    ],
    on=events().click(on_select),
    [
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        text(ffi_format_datetime(row.occurred_at)),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        text(row.event_type),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        text(row.service),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        span(style=result_badge_style(row.result), [text(row.result)]),
      ]),
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        code(style="font-family:'JetBrains Mono',monospace;", [
          text(row.trace),
        ]),
      ]),
      // 操作: traceコピー (A-0042) — stopPropagation so it doesn't trigger row select.
      div(
        style="padding:8px 12px;",
        attrs=[("role", @element.AttrString("cell"))],
        [
          button(
            style="background:rgba(99,102,241,0.12);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:6px 12px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;",
            on=events().click(fn(e) {
              e.stopPropagation()
              on_copy_trace(e)
            }),
            attrs=[("aria-label", @element.AttrString("traceをコピー"))],
            [text("traceコピー")],
          ),
        ],
      ),
    ],
  )
}

// ── R-03 detail panel ─────────────────────────────────────────────────────────

///|
/// Render the detail panel (R-03). Visible once a row is selected.
/// A11y: aria-live region so the detail content is announced on update.
fn render_detail_panel(
  selected_identifier : @signal.Signal[String],
  detail_loading : @signal.Signal[Bool],
  detail_event_type : @signal.Signal[String],
  detail_reason : @signal.Signal[String],
  detail_payload : @signal.Signal[String],
  detail_error : @signal.Signal[String]
) -> DomNode {
  let label_style = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;"
  let value_style = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
  let mono_style = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;word-break:break-all;"
  div(
    attrs=[
      ("role", @element.AttrString("region")),
      ("aria-label", @element.AttrString("ログ詳細")),
      ("aria-live", @element.AttrString("polite")),
      ("tabindex", @element.AttrString("-1")),
    ],
    dyn_style=fn() {
      if selected_identifier.get() == "" {
        "display:none;"
      } else {
        "background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:24px;display:flex;flex-direction:column;gap:16px;"
      }
    },
    [
      div(
        style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;",
        [text("ログ詳細")],
      ),
      // Detail loading
      div(
        dyn_style=fn() {
          if detail_loading.get() {
            "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
          } else {
            "display:none;"
          }
        },
        [text("読み込み中...")],
      ),
      // Detail error
      div(
        attrs=[("role", @element.AttrString("alert"))],
        dyn_style=fn() {
          if detail_error.get() == "" {
            "display:none;"
          } else {
            "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
          }
        },
        [text_of(detail_error)],
      ),
      // Detail body
      div(
        dyn_style=fn() {
          if detail_loading.get() || detail_error.get() != "" {
            "display:none;"
          } else {
            "display:flex;flex-direction:column;gap:16px;"
          }
        },
        [
          div(style="display:flex;flex-direction:column;gap:4px;", [
            div(style=label_style, [text("identifier")]),
            div(style=mono_style, [text_of(selected_identifier)]),
          ]),
          div(style="display:flex;flex-direction:column;gap:4px;", [
            div(style=label_style, [text("eventType")]),
            div(style=value_style, [text_of(detail_event_type)]),
          ]),
          div(style="display:flex;flex-direction:column;gap:4px;", [
            div(style=label_style, [text("reason")]),
            div(style=value_style, [text_of(detail_reason)]),
          ]),
          div(style="display:flex;flex-direction:column;gap:4px;", [
            div(style=label_style, [text("payload 要約")]),
            pre(
              style="margin:0;padding:12px;background:rgba(15,23,42,0.6);border:1px solid rgba(248,250,252,0.08);border-radius:6px;color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;white-space:pre-wrap;word-break:break-all;",
              [text_of(detail_payload)],
            ),
          ]),
        ],
      ),
    ],
  )
}

// ── FFI helpers ────────────────────────────────────────────────────────────────

///|
extern "js" fn ffi_clone_audit_logs(
  arr : Array[AuditRowProps]
) -> Array[AuditRowProps] =
  #| (arr) => arr.map(o => ({ identifier: o.identifier, occurred_at: o.occurred_at, event_type: o.event_type, service: o.service, result: o.result, trace: o.trace }))

///|
extern "js" fn ffi_audit_length(arr : Array[AuditRowProps]) -> Int =
  #| (arr) => arr.length

///|
/// Format an ISO8601 datetime to local time (F-0041: ISO8601 local).
extern "js" fn ffi_format_datetime(value : String) -> String =
  #| (value) => {
  #|   try {
  #|     const d = new Date(value);
  #|     if (isNaN(d.getTime())) return value;
  #|     return d.toLocaleString('ja-JP', { hour12: false });
  #|   } catch { return value; }
  #| }

///|
/// Copy text to the clipboard (A-0042). Calls back with success.
extern "js" fn ffi_copy_to_clipboard(
  text : String,
  on_result : (Bool) -> Unit
) -> Unit =
  #| (text, on_result) => {
  #|   try {
  #|     if (navigator.clipboard && navigator.clipboard.writeText) {
  #|       navigator.clipboard.writeText(text)
  #|         .then(() => on_result(true))
  #|         .catch(() => on_result(false));
  #|     } else {
  #|       on_result(false);
  #|     }
  #|   } catch { on_result(false); }
  #| }

///|
/// Fetch the audit-log list from BFF GET /audit (filtered by the search conditions).
/// Maps the OpenAPI AuditListResponse into AuditRowProps[].
extern "js" fn ffi_fetch_audit(
  base_url : String,
  trace : String,
  event_type : String,
  from : String,
  to : String,
  limit : Int,
  on_result : (Bool, Array[AuditRowProps], String) -> Unit
) -> Unit =
  #| (base_url, trace, event_type, from, to, limit, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const url = new URL('/audit', base_url);
  #|   if (trace) url.searchParams.set('trace', trace);
  #|   if (event_type) url.searchParams.set('eventType', event_type);
  #|   if (from) url.searchParams.set('from', new Date(from).toISOString());
  #|   if (to) url.searchParams.set('to', new Date(to).toISOString());
  #|   if (limit) url.searchParams.set('limit', String(limit));
  #|   fetch(url.toString(), {
  #|     method: 'GET',
  #|     headers: { ...(token ? { 'Authorization': 'Bearer ' + token } : {}) },
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data && Array.isArray(data.items)) {
  #|       const rows = data.items.map(o => ({
  #|         identifier: o.identifier ?? '',
  #|         occurred_at: o.occurredAt ?? '',
  #|         event_type: o.eventType ?? '',
  #|         service: o.service ?? '',
  #|         result: o.result ?? '',
  #|         trace: o.trace ?? '',
  #|       }));
  #|       on_result(true, rows, '');
  #|     } else {
  #|       const msg = (data && data.detail) || '監査ログの取得に失敗しました。';
  #|       on_result(false, [], msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, [], '監査ログの取得に失敗しました。'));
  #| }

///|
/// Fetch a single audit-log detail from BFF GET /audit/{identifier}.
/// Maps the OpenAPI AuditDetail (eventType, reason, payload) for the detail panel.
extern "js" fn ffi_fetch_audit_detail(
  base_url : String,
  identifier : String,
  on_result : (Bool, String, String, String, String) -> Unit
) -> Unit =
  #| (base_url, identifier, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   fetch(base_url + '/audit/' + encodeURIComponent(identifier), {
  #|     method: 'GET',
  #|     headers: { ...(token ? { 'Authorization': 'Bearer ' + token } : {}) },
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data) {
  #|       let payloadSummary = '';
  #|       try { payloadSummary = data.payload ? JSON.stringify(data.payload, null, 2) : '(なし)'; } catch { payloadSummary = '(表示できません)'; }
  #|       on_result(true, data.eventType ?? '', data.reason ?? '(なし)', payloadSummary, '');
  #|     } else {
  #|       const msg = (data && data.detail) || '監査ログの取得に失敗しました。';
  #|       on_result(false, '', '', '', msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, '', '', '', '監査ログの取得に失敗しました。'));
  #| }
