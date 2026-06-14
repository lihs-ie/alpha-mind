///| Insights Actions Island Component (SCR-006)
///|
///| Interactive insight-management panel: theme/source client-side filter,
///| cursor-based "load more" pagination, per-insight detail (fetched on row
///| select), and hypothesize / adopt / reject (仮説化/採用/却下) operator actions
///| with a decision confirmation modal.
///| This is a client component: it runs in the browser after hydration.
///|
///| Operations (documents/外部設計/screens/SCR-006_インサイト管理.md §4):
///|  - A-0061 仮説化:  POST /insights/{identifier}/hypothesize  (202 CommandAccepted)
///|  - A-0062 採用:    POST /insights/{identifier}/adopt        (200 OperationResult, pre: sourceUrl 必須)
///|  - A-0063 却下:    POST /insights/{identifier}/reject       (200 OperationResult, pre: reasonCode 必須)
///|  - 行選択 (R-03):  GET /insights/{identifier} → 詳細パネル
///|  - フィルタ (R-01): theme / source — ロード済み一覧へのクライアントサイド絞り込み
///|  - 追加取得:        GET /insights?cursor=... (nextCursor)
///|
///| Ref: documents/外部設計/screens/SCR-006_インサイト管理.md
///| Ref: documents/外部設計/api/openapi.yaml (InsightSummary, InsightDetail, InsightDecisionRequest, CommandAccepted, OperationResult)

///|
/// A single insight row passed from the server (SSR initial state) or fetched
/// from BFF GET /insights. Mirrors the OpenAPI InsightSummary schema.
pub(all) struct InsightRowProps {
  identifier : String
  source_type : String
  summary : String
  source_url : String
  collected_at : String
  signal_class : String
  so_what_score : Double
} derive(ToJson, FromJson)

///|
/// Props passed from the server (SSR initial state).
pub(all) struct InsightsActionsProps {
  bff_base_url : String
  initial_insights : Array[InsightRowProps]
  initial_next_cursor : String
} derive(ToJson, FromJson)

// ── Pure logic (unit-tested) ─────────────────────────────────────────────────

///|
/// Whether an insight row matches the active theme/source filters.
/// theme is matched case-insensitively as a substring of the summary
/// (the /insights list has no per-row theme field), source as exact sourceType.
/// Empty filter means "match all".
pub fn insight_matches_filter(
  summary : String,
  source_type : String,
  theme_filter : String,
  source_filter : String
) -> Bool {
  let theme_ok = theme_filter == "" ||
    ffi_contains_ci(summary, theme_filter) ||
    ffi_contains_ci(source_type, theme_filter)
  let source_ok = source_filter == "" || source_type == source_filter
  theme_ok && source_ok
}

///|
/// Validate an adopt (採用) submission. Returns an error message, or "" when valid.
/// Rules (SCR-006 §5): sourceUrl 必須 (根拠リンク); actionReasonCode 必須.
pub fn validate_adopt_insight(
  reason_code : String,
  source_url : String
) -> String {
  if source_url == "" {
    "根拠リンクがないため採用できません"
  } else if reason_code == "" {
    "理由コードを選択してください"
  } else {
    ""
  }
}

///|
/// Validate a reject (却下) submission. Returns an error message, or "" when valid.
/// Rules (SCR-006 §5): 却下理由コード 必須.
pub fn validate_reject_insight(reason_code : String) -> String {
  if reason_code == "" {
    "却下理由コードを選択してください"
  } else {
    ""
  }
}

///|
/// Validate a hypothesize (仮説化) submission. Returns an error message, or "" when valid.
/// InsightDecisionRequest requires actionReasonCode.
pub fn validate_hypothesize_insight(reason_code : String) -> String {
  if reason_code == "" {
    "理由コードを選択してください"
  } else {
    ""
  }
}

///|
/// Format a soWhatScore (0..1) for display (JetBrains Mono, 2 fraction digits).
pub fn format_so_what_score(value : Double) -> String {
  insights_ffi_format_ratio(value)
}

// ── Island ───────────────────────────────────────────────────────────────────

///|
/// Insights Actions Island component.
pub fn insights_actions(props : InsightsActionsProps) -> DomNode {
  let insights = @signal.signal(ffi_clone_insights(props.initial_insights))
  let next_cursor = @signal.signal(props.initial_next_cursor)
  let theme_filter = @signal.signal("")
  let source_filter = @signal.signal("")
  let is_loading = @signal.signal(false)
  let status_message = @signal.signal("")
  let status_is_error = @signal.signal(false)

  // Detail (R-03) state.
  let selected_identifier = @signal.signal("")
  let detail_loading = @signal.signal(false)
  let detail_error = @signal.signal("")
  let detail_source_url = @signal.signal("")
  let detail_skill_version = @signal.signal("")
  let detail_theme = @signal.signal("")
  let detail_sentiment = @signal.signal("")
  let detail_evidence = @signal.signal("")

  // Decision modal (R-04) state, shared by 仮説化 / 採用 / 却下.
  let show_modal = @signal.signal(false)
  let modal_action = @signal.signal("") // "hypothesize" | "adopt" | "reject"
  let modal_target = @signal.signal("")
  let modal_reason_code = @signal.signal("")
  let modal_comment = @signal.signal("")
  let modal_validation_error = @signal.signal("")

  // ── Filter handlers (client-side over the loaded list) ───────────────────────

  let handle_theme_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    theme_filter.set(target.value)
  }
  let handle_source_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    source_filter.set(target.value)
  }

  // ── Pagination (server-side cursor) ──────────────────────────────────────────

  let handle_load_more : @element.MouseHandler = fn(_e) {
    if is_loading.get() || next_cursor.get() == "" {
      return
    }
    is_loading.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let cursor = next_cursor.get()
    let rows = insights
    let cur = next_cursor
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    ffi_fetch_insights(base_url, cursor, fn(success, fetched, new_cursor, error_message) {
      loading.set(false)
      if success {
        rows.set(ffi_concat_insights(rows.get(), fetched))
        cur.set(new_cursor)
        is_err.set(false)
        msg.set("")
      } else {
        is_err.set(true)
        msg.set("✗ " + error_message)
      }
    })
  }

  // ── 行選択 (R-03 詳細) ───────────────────────────────────────────────────────

  let handle_select : (String) -> @element.MouseHandler = fn(identifier) {
    fn(_e) {
      if detail_loading.get() {
        return
      }
      selected_identifier.set(identifier)
      detail_loading.set(true)
      detail_error.set("")
      let base_url = props.bff_base_url
      let loading = detail_loading
      let err = detail_error
      let d_url = detail_source_url
      let d_skill = detail_skill_version
      let d_theme = detail_theme
      let d_sentiment = detail_sentiment
      let d_evidence = detail_evidence
      ffi_fetch_insight_detail(
        base_url,
        identifier,
        fn(
          success,
          source_url,
          skill_version,
          theme,
          sentiment,
          evidence_snippet,
          error_message
        ) {
          loading.set(false)
          if success {
            d_url.set(source_url)
            d_skill.set(skill_version)
            d_theme.set(theme)
            d_sentiment.set(sentiment)
            d_evidence.set(evidence_snippet)
            err.set("")
          } else {
            err.set("✗ " + error_message)
          }
        },
      )
    }
  }

  // ── 操作モーダル (仮説化 / 採用 / 却下) ──────────────────────────────────────

  let handle_open_modal : (String, String) -> @element.MouseHandler = fn(
    action,
    identifier
  ) {
    fn(_e) {
      if is_loading.get() {
        return
      }
      modal_action.set(action)
      modal_target.set(identifier)
      modal_reason_code.set("")
      modal_comment.set("")
      modal_validation_error.set("")
      show_modal.set(true)
    }
  }
  let handle_reason_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    modal_reason_code.set(target.value)
    modal_validation_error.set("")
  }
  let handle_comment_input : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    modal_comment.set(target.value)
    modal_validation_error.set("")
  }
  let handle_modal_cancel : @element.MouseHandler = fn(_e) {
    show_modal.set(false)
  }

  // A11y §9: modal closable via Esc.
  let handle_modal_keydown : @element.KeyboardHandler = fn(e) {
    if e.key == "Escape" {
      show_modal.set(false)
    }
  }
  let handle_modal_confirm : @element.MouseHandler = fn(_e) {
    let action = modal_action.get()
    let identifier = modal_target.get()
    let reason = modal_reason_code.get()
    let comment = modal_comment.get()
    // Re-validate against the selected insight's detail (sourceUrl for adopt).
    let validation = if action == "adopt" {
      validate_adopt_insight(reason, detail_source_url.get())
    } else if action == "reject" {
      validate_reject_insight(reason)
    } else {
      validate_hypothesize_insight(reason)
    }
    if validation != "" {
      modal_validation_error.set(validation)
      return
    }
    show_modal.set(false)
    is_loading.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    let success_text = if action == "hypothesize" {
      "✓ 仮説候補を作成しました。"
    } else if action == "adopt" {
      "✓ インサイトを採用しました。"
    } else {
      "✓ インサイトを却下しました。"
    }
    ffi_post_insight_action(
      base_url,
      identifier,
      action,
      reason,
      comment,
      fn(success, error_message) {
        loading.set(false)
        if success {
          is_err.set(false)
          msg.set(success_text)
        } else {
          is_err.set(true)
          msg.set("✗ インサイト操作に失敗しました。 " + error_message)
        }
      },
    )
  }

  // ── Render ───────────────────────────────────────────────────────────────────

  div(style="display:flex;flex-direction:column;gap:24px;", [
    // Status message area (aria-live) — MSG-I-0061 / MSG-E-0061.
    div(
      attrs=[
        ("role", @element.AttrString("alert")),
        ("aria-live", @element.AttrString("polite")),
      ],
      dyn_style=fn() {
        let message = status_message.get()
        if message == "" {
          "display:none;"
        } else if status_is_error.get() {
          "padding:10px 16px;border-radius:6px;background:rgba(248,113,113,0.12);border:1px solid rgba(248,113,113,0.3);color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
        } else {
          "padding:10px 16px;border-radius:6px;background:rgba(34,197,94,0.12);border:1px solid rgba(34,197,94,0.3);color:#22C55E;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
        }
      },
      [text_of(status_message)],
    ),
    // ── R-01 フィルタ (theme / source) ──────────────────────────────────────────
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
            placeholder="例: ai-momentum（要約・ソースを部分一致）",
            style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;min-width:280px;box-sizing:border-box;",
            on=events().input(handle_theme_input),
            attrs=[("aria-label", @element.AttrString("テーマフィルタ"))],
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
            placeholder="例: x / youtube / paper / github（空=全件）",
            style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;min-width:240px;box-sizing:border-box;",
            on=events().input(handle_source_input),
            attrs=[("aria-label", @element.AttrString("ソースフィルタ"))],
          ),
        ]),
      ],
    ),
    // ── R-02 インサイト一覧 ──────────────────────────────────────────────────────
    div(
      style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
      attrs=[
        ("role", @element.AttrString("table")),
        ("aria-label", @element.AttrString("インサイト一覧")),
      ],
      [
        render_insight_header(),
        // Empty state (§6 empty)
        div(
          attrs=[("role", @element.AttrString("status"))],
          dyn_style=fn() {
            let visible = ffi_filtered_length(
              insights.get(),
              theme_filter.get(),
              source_filter.get(),
            )
            if visible == 0 {
              "padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
            } else {
              "display:none;"
            }
          },
          [text("該当インサイトがありません。")],
        ),
        // Reactive rows — re-render when insights / filters change.
        for_each(
          fn() {
            ffi_filter_insights(
              insights.get(),
              theme_filter.get(),
              source_filter.get(),
            )
          },
          fn(insight, _index) {
            render_insight_row(
              insight,
              handle_select(insight.identifier),
              handle_open_modal("hypothesize", insight.identifier),
              handle_open_modal("adopt", insight.identifier),
              handle_open_modal("reject", insight.identifier),
            )
          },
        ),
      ],
    ),
    // ── 追加取得 (nextCursor) ────────────────────────────────────────────────────
    div(
      dyn_style=fn() {
        if next_cursor.get() == "" {
          "display:none;"
        } else {
          "display:flex;justify-content:center;"
        }
      },
      [
        button(
          dyn_style=fn() {
            let base = "background:rgba(99,102,241,0.2);color:#818CF8;border:1px solid rgba(99,102,241,0.35);border-radius:6px;padding:8px 24px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;"
            if is_loading.get() {
              base + "opacity:0.6;cursor:not-allowed;"
            } else {
              base + "cursor:pointer;"
            }
          },
          on=events().click(handle_load_more),
          [
            text_dyn(
              @signal.computed(fn() {
                if is_loading.get() {
                  "読み込み中..."
                } else {
                  "さらに読み込む"
                }
              }),
            ),
          ],
        ),
      ],
    ),
    // ── R-03 詳細パネル (選択時) ────────────────────────────────────────────────
    insights_render_detail_panel(
      selected_identifier,
      detail_loading,
      detail_error,
      detail_source_url,
      detail_skill_version,
      detail_theme,
      detail_sentiment,
      detail_evidence,
    ),
    // ── R-04 操作モーダル (仮説化 / 採用 / 却下) ────────────────────────────────
    insights_render_decision_modal(
      show_modal,
      modal_action,
      modal_validation_error,
      handle_reason_input,
      handle_comment_input,
      handle_modal_cancel,
      handle_modal_confirm,
      handle_modal_keydown,
    ),
  ])
}

// ── R-02 table rendering ──────────────────────────────────────────────────────

///|
/// Header row for the insight list (A11y: columnheader cells).
fn render_insight_header() -> DomNode {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style=insight_grid_style() + "border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @element.AttrString("row"))],
    [
      insight_header_cell(cell, "ソース"),
      insight_header_cell(cell, "要約"),
      insight_header_cell(cell, "シグナル"),
      insight_header_cell(cell, "So What"),
      insight_header_cell(cell, "操作"),
    ],
  )
}

///|
fn insight_header_cell(style : String, label_text : String) -> DomNode {
  div(style=style, attrs=[("role", @element.AttrString("columnheader"))], [
    text(label_text),
  ])
}

///|
/// Shared CSS grid template for header and rows (column alignment).
fn insight_grid_style() -> String {
  "display:grid;grid-template-columns:minmax(110px,0.9fr) minmax(260px,3fr) minmax(150px,1.1fr) minmax(90px,0.7fr) minmax(220px,1.6fr);align-items:center;"
}

///|
/// Background/foreground colours for a source-type badge.
fn source_badge_style(source_type : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = match source_type {
    "x" =>
      "background:rgba(99,102,241,0.18);color:#818CF8;border:1px solid rgba(99,102,241,0.35);"
    "youtube" =>
      "background:rgba(248,113,113,0.14);color:#F87171;border:1px solid rgba(248,113,113,0.35);"
    "paper" =>
      "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
    "github" =>
      "background:rgba(248,250,252,0.1);color:rgba(248,250,252,0.85);border:1px solid rgba(248,250,252,0.2);"
    _ =>
      "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// Background/foreground colours for a signalClass badge.
fn signal_class_badge_style(signal_class : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = match signal_class {
    "structural_anomaly" =>
      "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
    _ =>
      "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// Render a single insight row with select + action buttons.
fn render_insight_row(
  insight : InsightRowProps,
  on_select : @element.MouseHandler,
  on_hypothesize : @element.MouseHandler,
  on_adopt : @element.MouseHandler,
  on_reject : @element.MouseHandler
) -> DomNode {
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  div(
    style=insight_grid_style() +
      "border-bottom:1px solid rgba(248,250,252,0.06);cursor:pointer;",
    attrs=[
      ("role", @element.AttrString("row")),
      ("tabindex", @element.AttrString("0")),
    ],
    on=events().click(on_select),
    [
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        span(style=source_badge_style(insight.source_type), [
          text(insight.source_type),
        ]),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        text(insight.summary),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        span(style=signal_class_badge_style(insight.signal_class), [
          text(insight.signal_class),
        ]),
      ]),
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        text(format_so_what_score(insight.so_what_score)),
      ]),
      // R-04 操作 — stopPropagation so the buttons don't trigger row select.
      div(
        style="padding:8px 12px;display:flex;gap:8px;align-items:center;flex-wrap:wrap;",
        attrs=[("role", @element.AttrString("cell"))],
        [render_insight_action_buttons(on_hypothesize, on_adopt, on_reject)],
      ),
    ],
  )
}

///|
/// Render the 仮説化 / 採用 / 却下 action buttons for an insight row.
fn render_insight_action_buttons(
  on_hypothesize : @element.MouseHandler,
  on_adopt : @element.MouseHandler,
  on_reject : @element.MouseHandler
) -> DomNode {
  fragment([
    button(
      style="background:rgba(99,102,241,0.18);color:#818CF8;border:1px solid rgba(99,102,241,0.4);border-radius:6px;padding:6px 12px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
      on=events().click(fn(e) {
        e.stopPropagation()
        on_hypothesize(e)
      }),
      [text("仮説化")],
    ),
    button(
      style="background:rgba(34,197,94,0.15);color:#22C55E;border:1px solid rgba(34,197,94,0.4);border-radius:6px;padding:6px 12px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
      on=events().click(fn(e) {
        e.stopPropagation()
        on_adopt(e)
      }),
      [text("採用")],
    ),
    button(
      style="background:rgba(248,113,113,0.12);color:#F87171;border:1px solid rgba(248,113,113,0.4);border-radius:6px;padding:6px 12px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
      on=events().click(fn(e) {
        e.stopPropagation()
        on_reject(e)
      }),
      [text("却下")],
    ),
  ])
}

// ── R-03 detail panel ─────────────────────────────────────────────────────────

///|
/// Render the detail panel (R-03). Visible once an insight row is selected.
fn insights_render_detail_panel(
  selected_identifier : @signal.Signal[String],
  detail_loading : @signal.Signal[Bool],
  detail_error : @signal.Signal[String],
  detail_source_url : @signal.Signal[String],
  detail_skill_version : @signal.Signal[String],
  detail_theme : @signal.Signal[String],
  detail_sentiment : @signal.Signal[String],
  detail_evidence : @signal.Signal[String]
) -> DomNode {
  div(
    attrs=[
      ("role", @element.AttrString("region")),
      ("aria-label", @element.AttrString("インサイト詳細")),
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
        style="display:flex;align-items:center;justify-content:space-between;gap:16px;flex-wrap:wrap;",
        [
          div(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;",
            [text("詳細")],
          ),
          code(
            style="color:rgba(248,250,252,0.7);font-family:'JetBrains Mono',monospace;font-size:0.8125rem;",
            [text_of(selected_identifier)],
          ),
        ],
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
            "display:flex;flex-direction:column;gap:14px;"
          }
        },
        [
          // theme + sentiment badges
          div(style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;", [
            span(
              dyn_attrs=[
                ("style", @element.Dynamic(fn() { detail_meta_badge_style() })),
              ],
              [
                text_dyn(
                  @signal.computed(fn() {
                    let t = detail_theme.get()
                    if t == "" {
                      "テーマ: —"
                    } else {
                      "テーマ: " + t
                    }
                  }),
                ),
              ],
            ),
            span(
              dyn_attrs=[
                (
                  "style",
                  @element.Dynamic(fn() {
                    sentiment_badge_style(detail_sentiment.get())
                  }),
                ),
              ],
              [
                text_dyn(
                  @signal.computed(fn() {
                    let s = detail_sentiment.get()
                    if s == "" {
                      "—"
                    } else {
                      s
                    }
                  }),
                ),
              ],
            ),
          ]),
          // evidenceSnippet (F: 根拠)
          detail_field("根拠 (evidenceSnippet)", detail_evidence, false),
          // skillVersion (F-0065)
          detail_field("収集Skill版 (skillVersion)", detail_skill_version, true),
          // sourceUrl (F-0064) — keyboard-openable link (§9)
          div(style="display:flex;flex-direction:column;gap:6px;", [
            div(
              style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;",
              [text("根拠リンク (sourceUrl)")],
            ),
            a(
              target="_blank",
              dyn_attrs=[
                ("href", @element.Dynamic(fn() { detail_source_url.get() })),
              ],
              style="color:#818CF8;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;text-decoration:underline;word-break:break-all;",
              attrs=[("rel", @element.AttrString("noopener noreferrer"))],
              [text_of(detail_source_url)],
            ),
          ]),
        ],
      ),
    ],
  )
}

///|
/// A single labelled detail field (value in mono when `mono` is true).
fn detail_field(
  label_text : String,
  value : @signal.Signal[String],
  mono : Bool
) -> DomNode {
  let value_style = if mono {
    "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;"
  } else {
    "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;line-height:1.5;"
  }
  div(style="display:flex;flex-direction:column;gap:6px;", [
    div(
      style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;",
      [text(label_text)],
    ),
    div(style=value_style, [text_of(value)]),
  ])
}

///|
/// Neutral badge style for the theme chip.
fn detail_meta_badge_style() -> String {
  "display:inline-block;padding:2px 10px;border-radius:999px;background:rgba(99,102,241,0.12);color:#818CF8;border:1px solid rgba(99,102,241,0.3);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;"
}

///|
/// Sentiment badge colours (positive→profit, negative→loss, neutral→neutral).
fn sentiment_badge_style(sentiment : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;"
  let colors = match sentiment {
    "positive" =>
      "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
    "negative" =>
      "background:rgba(248,113,113,0.12);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.35);"
    _ =>
      "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

// ── R-04 decision modal ───────────────────────────────────────────────────────

///|
/// Render the decision confirmation modal (仮説化 / 採用 / 却下).
/// A11y §9: closable via Esc (keydown handler on the dialog).
fn insights_render_decision_modal(
  show_modal : @signal.Signal[Bool],
  modal_action : @signal.Signal[String],
  modal_validation_error : @signal.Signal[String],
  on_reason_input : @element.InputHandler,
  on_comment_input : @element.InputHandler,
  on_cancel : @element.MouseHandler,
  on_confirm : @element.MouseHandler,
  on_keydown : @element.KeyboardHandler
) -> DomNode {
  div(
    dyn_style=fn() {
      if show_modal.get() {
        "position:fixed;inset:0;background:rgba(0,0,0,0.6);display:flex;align-items:center;justify-content:center;z-index:40;"
      } else {
        "display:none;"
      }
    },
    attrs=[
      ("role", @element.AttrString("dialog")),
      ("aria-modal", @element.AttrString("true")),
      ("aria-label", @element.AttrString("インサイト操作確認")),
      ("tabindex", @element.AttrString("-1")),
    ],
    on=events().keydown(on_keydown),
    [
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.12);border-radius:12px;padding:32px;width:100%;max-width:460px;box-sizing:border-box;display:flex;flex-direction:column;gap:20px;",
        [
          p(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.125rem;font-weight:700;margin:0;",
            [
              text_dyn(
                @signal.computed(fn() {
                  match modal_action.get() {
                    "hypothesize" => "このインサイトを仮説化しますか？"
                    "adopt" => "このインサイトを採用しますか？"
                    _ => "このインサイトを却下しますか？"
                  }
                }),
              ),
            ],
          ),
          p(
            style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0;",
            [text("操作理由コードを選択し、確認後に実行してください。")],
          ),
          // Reason code input (actionReasonCode required)
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(
              for_="insight-reason-code",
              style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
              [text("操作理由コード *")],
            ),
            input(
              type_="text",
              id="insight-reason-code",
              name="insight-reason-code",
              placeholder="例: MANUAL_OPERATION",
              style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
              on=events().input(on_reason_input),
            ),
          ]),
          // Comment input (optional)
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(
              for_="insight-comment",
              style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
              [text("コメント（任意）")],
            ),
            input(
              type_="text",
              id="insight-comment",
              name="insight-comment",
              placeholder="操作理由を入力...",
              style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;width:100%;box-sizing:border-box;",
              on=events().input(on_comment_input),
            ),
            div(
              attrs=[("role", @element.AttrString("alert"))],
              dyn_style=fn() {
                if modal_validation_error.get() == "" {
                  "display:none;"
                } else {
                  "color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
                }
              },
              [text_of(modal_validation_error)],
            ),
          ]),
          // Modal actions
          div(style="display:flex;gap:12px;justify-content:flex-end;", [
            button(
              style="background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.12);border-radius:6px;padding:10px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:500;cursor:pointer;",
              on=events().click(on_cancel),
              [text("キャンセル")],
            ),
            button(
              dyn_style=fn() {
                let base = "color:#fff;border:none;border-radius:6px;padding:10px 20px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;"
                match modal_action.get() {
                  "hypothesize" => base + "background:#818CF8;"
                  "adopt" => base + "background:#22C55E;"
                  _ => base + "background:#F87171;"
                }
              },
              on=events().click(on_confirm),
              [
                text_dyn(
                  @signal.computed(fn() {
                    match modal_action.get() {
                      "hypothesize" => "仮説化する"
                      "adopt" => "採用する"
                      _ => "却下する"
                    }
                  }),
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  )
}

// ── FFI helpers ──────────────────────────────────────────────────────────────

///|
extern "js" fn ffi_clone_insights(
  arr : Array[InsightRowProps]
) -> Array[InsightRowProps] =
  #| (arr) => arr.map(o => ({ identifier: o.identifier, source_type: o.source_type, summary: o.summary, source_url: o.source_url, collected_at: o.collected_at, signal_class: o.signal_class, so_what_score: o.so_what_score }))

///|
/// Append `more` to `arr`, returning a new array (immutable update for the signal).
extern "js" fn ffi_concat_insights(
  arr : Array[InsightRowProps],
  more : Array[InsightRowProps]
) -> Array[InsightRowProps] =
  #| (arr, more) => arr.concat(more)

///|
/// Case-insensitive substring containment (theme filter).
extern "js" fn ffi_contains_ci(haystack : String, needle : String) -> Bool =
  #| (haystack, needle) => String(haystack).toLowerCase().includes(String(needle).toLowerCase())

///|
/// Filter the insight list by theme (summary/source substring) + source (exact).
extern "js" fn ffi_filter_insights(
  arr : Array[InsightRowProps],
  theme_filter : String,
  source_filter : String
) -> Array[InsightRowProps] =
  #| (arr, theme_filter, source_filter) => {
  #|   const t = String(theme_filter).toLowerCase();
  #|   const s = String(source_filter);
  #|   return arr.filter(o => {
  #|     const themeOk = t === '' || String(o.summary).toLowerCase().includes(t) || String(o.source_type).toLowerCase().includes(t);
  #|     const sourceOk = s === '' || o.source_type === s;
  #|     return themeOk && sourceOk;
  #|   });
  #| }

///|
/// Count of insights visible under the current filter (for empty-state).
extern "js" fn ffi_filtered_length(
  arr : Array[InsightRowProps],
  theme_filter : String,
  source_filter : String
) -> Int =
  #| (arr, theme_filter, source_filter) => {
  #|   const t = String(theme_filter).toLowerCase();
  #|   const s = String(source_filter);
  #|   return arr.filter(o => {
  #|     const themeOk = t === '' || String(o.summary).toLowerCase().includes(t) || String(o.source_type).toLowerCase().includes(t);
  #|     const sourceOk = s === '' || o.source_type === s;
  #|     return themeOk && sourceOk;
  #|   }).length;
  #| }

///|
/// Format a ratio value (soWhatScore: `0.00`, 2 fraction digits).
extern "js" fn insights_ffi_format_ratio(value : Double) -> String =
  #| (value) => {
  #|   try { return value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
  #|   catch { return String(value); }
  #| }

///|
/// Fetch the next page of insights from BFF GET /insights?cursor=...
/// Maps the OpenAPI InsightListResponse into rows + nextCursor.
extern "js" fn ffi_fetch_insights(
  base_url : String,
  cursor : String,
  on_result : (Bool, Array[InsightRowProps], String, String) -> Unit
) -> Unit =
  #| (base_url, cursor, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const url = new URL('/insights', base_url);
  #|   if (cursor) url.searchParams.set('cursor', cursor);
  #|   fetch(url.toString(), {
  #|     method: 'GET',
  #|     headers: { ...(token ? { 'Authorization': 'Bearer ' + token } : {}) },
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data && Array.isArray(data.items)) {
  #|       const rows = data.items.map(o => ({
  #|         identifier: o.identifier ?? '',
  #|         source_type: o.sourceType ?? '',
  #|         summary: o.summary ?? '',
  #|         source_url: o.sourceUrl ?? '',
  #|         collected_at: o.collectedAt ?? '',
  #|         signal_class: o.signalClass ?? '',
  #|         so_what_score: typeof o.soWhatScore === 'number' ? o.soWhatScore : 0.0,
  #|       }));
  #|       on_result(true, rows, data.nextCursor ?? '', '');
  #|     } else {
  #|       const msg = (data && data.detail) || '一覧の取得に失敗しました。再試行してください。';
  #|       on_result(false, [], '', msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, [], '', '一覧の取得に失敗しました。再試行してください。'));
  #| }

///|
/// Fetch a single insight detail from BFF GET /insights/{identifier}.
/// Maps the OpenAPI InsightDetail (sourceUrl, skillVersion, theme, sentiment,
/// evidenceSnippet) for the detail panel.
extern "js" fn ffi_fetch_insight_detail(
  base_url : String,
  identifier : String,
  on_result : (Bool, String, String, String, String, String, String) -> Unit
) -> Unit =
  #| (base_url, identifier, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   fetch(base_url + '/insights/' + encodeURIComponent(identifier), {
  #|     method: 'GET',
  #|     headers: { ...(token ? { 'Authorization': 'Bearer ' + token } : {}) },
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data && data.identifier) {
  #|       on_result(
  #|         true,
  #|         data.sourceUrl ?? '',
  #|         data.skillVersion ?? '',
  #|         data.theme ?? '',
  #|         data.sentiment ?? '',
  #|         data.evidenceSnippet ?? '',
  #|         '',
  #|       );
  #|     } else {
  #|       const msg = (data && data.detail) || 'インサイト詳細の取得に失敗しました。';
  #|       on_result(false, '', '', '', '', '', msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, '', '', '', '', '', 'インサイト詳細の取得に失敗しました。'));
  #| }

///|
/// POST an insight operation (hypothesize | adopt | reject) to the BFF.
/// Sends an InsightDecisionRequest { actionReasonCode (required), comment? }.
/// hypothesize → 202 CommandAccepted { accepted }; adopt/reject → 200 OperationResult { success }.
extern "js" fn ffi_post_insight_action(
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
  #|   const body = { actionReasonCode: reason_code };
  #|   if (comment) body.comment = comment;
  #|   fetch(base_url + '/insights/' + encodeURIComponent(identifier) + '/' + action, {
  #|     method: 'POST',
  #|     headers: {
  #|       'Content-Type': 'application/json',
  #|       ...(token ? { 'Authorization': 'Bearer ' + token } : {}),
  #|     },
  #|     body: JSON.stringify(body),
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })).catch(() => ({ ok: res.ok, data: {} })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && (data.success === true || data.accepted === true)) {
  #|       on_result(true, '');
  #|     } else {
  #|       const msg = (data && data.detail) || 'インサイト操作に失敗しました。再試行してください。';
  #|       on_result(false, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, 'インサイト操作に失敗しました。再試行してください。'));
  #| }
