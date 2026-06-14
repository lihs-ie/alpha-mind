///| Hypotheses Actions Island Component (SCR-007 仮説ラボ)
///|
///| Interactive hypothesis-lab panel: status filter, cursor-based "load more"
///| pagination, per-hypothesis detail (fetched on row select) with backtest /
///| demo metrics, and the state-machine-aware operator actions
///| 再検証 / 昇格申請 / 却下 / MNPI自己申告更新.
///| This is a client component: it runs in the browser after hydration.
///|
///| Operations (documents/外部設計/screens/SCR-007_仮説ラボ.md §4):
///|  - A-0071 再検証:  POST /hypotheses/{identifier}/retest                  (202 CommandAccepted, pre: status!=live)
///|  - A-0072 昇格申請: POST /hypotheses/{identifier}/promote                 (200 OperationResult, pre: status=demo)
///|  - A-0073 却下:    POST /hypotheses/{identifier}/reject                  (200 OperationResult, pre: reasonCode)
///|  - A-0074 MNPI:    PUT  /hypotheses/{identifier}/mnpi-self-declaration   (200 OperationResult, pre: status=demo)
///|  - 行選択 (R-02):  GET /hypotheses/{identifier} → 指標領域 (R-02) / 操作領域 (R-03)
///|  - フィルタ (R-01): status — ロード済み一覧へのクライアントサイド絞り込み
///|  - 追加取得:        GET /hypotheses?cursor=... (nextCursor)
///|
///| 状態遷移 (状態遷移設計 §6): draft → backtested → demo → live | rejected (live/rejected 終端)。
///| 昇格バリデーション (SCR-007 §5, 条件付き自動昇格設計 §5): demo期間1か月以上 /
///| requiresComplianceReview=false / mnpiSelfDeclared=true。
///|
///| Ref: documents/外部設計/screens/SCR-007_仮説ラボ.md
///| Ref: documents/外部設計/api/openapi.yaml (HypothesisSummary, HypothesisDetail,
///|      HypothesisDecisionRequest, HypothesisRejectRequest, HypothesisMnpiSelfDeclarationUpdate,
///|      OperationResult, CommandAccepted)

///|
/// A single hypothesis row passed from the server (SSR initial state) or fetched
/// from BFF GET /hypotheses. Mirrors the OpenAPI HypothesisSummary schema.
pub(all) struct HypothesisRowProps {
  identifier : String
  symbol : String
  instrument_type : String
  status : String
  title : String
  updated_at : String
} derive(ToJson, FromJson)

///|
/// Props passed from the server (SSR initial state).
pub(all) struct HypothesesActionsProps {
  bff_base_url : String
  initial_hypotheses : Array[HypothesisRowProps]
  initial_next_cursor : String
} derive(ToJson, FromJson)

// ── Pure logic (unit-tested) ─────────────────────────────────────────────────

///|
/// Whether a hypothesis row matches the active status filter.
/// Empty filter means "match all"; otherwise exact match on status.
pub fn hypothesis_matches_filter(
  status : String,
  status_filter : String
) -> Bool {
  status_filter == "" || status == status_filter
}

///|
/// Whether the 再検証 (retest) action is available for a hypothesis.
/// Pre-condition (SCR-007 A-0071): status != live (live は終端なので再検証不可)。
/// rejected も終端なので不可とする。
pub fn can_retest_hypothesis(status : String) -> Bool {
  status != "live" && status != "rejected"
}

///|
/// Whether the 昇格申請 (promote) action is available for a hypothesis.
/// Pre-condition (SCR-007 A-0072 / 状態遷移設計 §6): status == demo。
pub fn can_promote_hypothesis(status : String) -> Bool {
  status == "demo"
}

///|
/// Whether the MNPI自己申告更新 (A-0074) action is available for a hypothesis.
/// Pre-condition (SCR-007 A-0074): status == demo。
pub fn can_update_mnpi_hypothesis(status : String) -> Bool {
  status == "demo"
}

///|
/// Whether the 却下 (reject) action is available for a hypothesis.
/// Reject is allowed from any non-terminal status (live / rejected are terminal).
pub fn can_reject_hypothesis(status : String) -> Bool {
  status != "live" && status != "rejected"
}

///|
/// Validate a 昇格申請 (promote) submission. Returns an error message, or "" when valid.
/// Rules (SCR-007 §5, 条件付き自動昇格設計 §5):
///  - demo 期間 1 か月以上 (demo_period_days >= 30)。
///  - requiresComplianceReview=false。
///  - mnpiSelfDeclared=true。
///  - actionReasonCode 必須 (HypothesisDecisionRequest)。
pub fn validate_promote_hypothesis(
  reason_code : String,
  demo_period_days : Int,
  requires_compliance_review : Bool,
  mnpi_self_declared : Bool
) -> String {
  if demo_period_days < 30 {
    "デモ期間が不足しています"
  } else if requires_compliance_review {
    "コンプライアンスレビュー未完了です"
  } else if !mnpi_self_declared {
    "MNPI自己申告が未完了です"
  } else if reason_code == "" {
    "操作理由コードを選択してください"
  } else {
    ""
  }
}

///|
/// Validate a 却下 (reject) submission. Returns an error message, or "" when valid.
/// Rules (SCR-007 §5): 却下理由コード 必須 (HypothesisRejectRequest.actionReasonCode)。
pub fn validate_reject_hypothesis(reason_code : String) -> String {
  if reason_code == "" {
    "却下理由コードを選択してください"
  } else {
    ""
  }
}

///|
/// Validate a MNPI自己申告更新 (A-0074) submission. Returns an error message, or "" when valid.
/// Rules: actionReasonCode 必須 (HypothesisMnpiSelfDeclarationUpdate.actionReasonCode)。
pub fn validate_mnpi_hypothesis(reason_code : String) -> String {
  if reason_code == "" {
    "操作理由コードを選択してください"
  } else {
    ""
  }
}

///|
/// Parse a demoPeriod string ("45d", "2m", "6w", "1month", "") into a day count.
/// Used to evaluate the "demo 1 か月以上" promotion pre-condition.
pub fn parse_demo_period_days(demo_period : String) -> Int {
  hypotheses_ffi_parse_demo_days(demo_period)
}

///|
/// Format a metric value (costAdjustedReturn / dsr / pbo) for display.
pub fn format_metric(value : Double, fraction_digits : Int) -> String {
  hypotheses_ffi_format_number(value, fraction_digits)
}

// ── Island ───────────────────────────────────────────────────────────────────

///|
/// Hypotheses Actions Island component.
pub fn hypotheses_actions(props : HypothesesActionsProps) -> DomNode {
  let hypotheses = @signal.signal(
    ffi_clone_hypotheses(props.initial_hypotheses),
  )
  let next_cursor = @signal.signal(props.initial_next_cursor)
  let status_filter = @signal.signal("")
  let is_loading = @signal.signal(false)
  let status_message = @signal.signal("")
  let status_is_error = @signal.signal(false)

  // Detail (R-02 指標領域) state.
  let selected_identifier = @signal.signal("")
  let selected_status = @signal.signal("")
  let detail_loading = @signal.signal(false)
  let detail_error = @signal.signal("")
  let detail_instrument_type = @signal.signal("")
  let detail_insider_risk = @signal.signal("")
  let detail_demo_period = @signal.signal("")
  let detail_demo_period_days = @signal.signal(0)
  let detail_cost_adjusted_return = @signal.signal("")
  let detail_dsr = @signal.signal("")
  let detail_pbo = @signal.signal("")
  let detail_requires_compliance_review = @signal.signal(false)
  let detail_mnpi_self_declared = @signal.signal(false)
  let detail_auto_promotion_eligible = @signal.signal(false)
  let detail_promotion_mode = @signal.signal("")
  let detail_skill_version = @signal.signal("")
  let detail_instruction_profile_version = @signal.signal("")
  let detail_source_evidence = @signal.signal("")
  let detail_latest_failure_summary = @signal.signal("")

  // Operation modal (R-03 操作領域) state.
  // modal_action ∈ { "retest" | "promote" | "reject" | "mnpi" }.
  let show_modal = @signal.signal(false)
  let modal_action = @signal.signal("")
  let modal_target = @signal.signal("")
  let modal_reason_code = @signal.signal("")
  let modal_comment = @signal.signal("")
  let modal_mnpi_checked = @signal.signal(false)
  let modal_validation_error = @signal.signal("")

  // ── Filter handler (client-side over the loaded list) ────────────────────────
  // Status is selected via a segmented button group (the luna dom DSL has no
  // <select> factory). Each button sets the status filter signal.

  let handle_status_select : (String) -> @element.MouseHandler = fn(value) {
    fn(_e) { status_filter.set(value) }
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
    let status = status_filter.get()
    let rows = hypotheses
    let cur = next_cursor
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    ffi_fetch_hypotheses(
      base_url,
      status,
      cursor,
      fn(success, fetched, new_cursor, error_message) {
        loading.set(false)
        if success {
          rows.set(ffi_concat_hypotheses(rows.get(), fetched))
          cur.set(new_cursor)
          is_err.set(false)
          msg.set("")
        } else {
          is_err.set(true)
          msg.set("✗ " + error_message)
        }
      },
    )
  }

  // ── 行選択 (R-02 指標領域 詳細) ──────────────────────────────────────────────

  let handle_select : (HypothesisRowProps) -> @element.MouseHandler = fn(row) {
    fn(_e) {
      if detail_loading.get() {
        return
      }
      selected_identifier.set(row.identifier)
      selected_status.set(row.status)
      detail_loading.set(true)
      detail_error.set("")
      let base_url = props.bff_base_url
      let identifier = row.identifier
      let loading = detail_loading
      let err = detail_error
      let d_instrument = detail_instrument_type
      let d_insider = detail_insider_risk
      let d_demo = detail_demo_period
      let d_demo_days = detail_demo_period_days
      let d_car = detail_cost_adjusted_return
      let d_dsr = detail_dsr
      let d_pbo = detail_pbo
      let d_compliance = detail_requires_compliance_review
      let d_mnpi = detail_mnpi_self_declared
      let d_auto = detail_auto_promotion_eligible
      let d_mode = detail_promotion_mode
      let d_skill = detail_skill_version
      let d_profile = detail_instruction_profile_version
      let d_evidence = detail_source_evidence
      let d_failure = detail_latest_failure_summary
      ffi_fetch_hypothesis_detail(
        base_url,
        identifier,
        fn(success, detail, error_message) {
          loading.set(false)
          if success {
            d_instrument.set(detail.instrument_type)
            d_insider.set(detail.insider_risk)
            d_demo.set(detail.demo_period)
            d_demo_days.set(detail.demo_period_days)
            d_car.set(detail.cost_adjusted_return)
            d_dsr.set(detail.dsr)
            d_pbo.set(detail.pbo)
            d_compliance.set(detail.requires_compliance_review)
            d_mnpi.set(detail.mnpi_self_declared)
            d_auto.set(detail.auto_promotion_eligible)
            d_mode.set(detail.promotion_mode)
            d_skill.set(detail.skill_version)
            d_profile.set(detail.instruction_profile_version)
            d_evidence.set(detail.source_evidence)
            d_failure.set(detail.latest_failure_summary)
            err.set("")
          } else {
            err.set("✗ " + error_message)
          }
        },
      )
    }
  }

  // ── 操作モーダル (再検証 / 昇格申請 / 却下 / MNPI) ──────────────────────────

  let handle_open_modal : (String) -> @element.MouseHandler = fn(action) {
    fn(_e) {
      if is_loading.get() {
        return
      }
      modal_action.set(action)
      modal_target.set(selected_identifier.get())
      modal_reason_code.set("")
      modal_comment.set("")
      modal_mnpi_checked.set(detail_mnpi_self_declared.get())
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
  let handle_mnpi_toggle : @element.InputHandler = fn(e) {
    let target : @js_dom.HTMLInputElement = e.target() |> @js.identity
    modal_mnpi_checked.set(target.checked)
    modal_validation_error.set("")
  }
  let handle_modal_cancel : @element.MouseHandler = fn(_e) {
    show_modal.set(false)
  }

  // A11y §9: modal closable via Esc + focus trap baseline.
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
    let mnpi_checked = modal_mnpi_checked.get()
    // Re-validate against the selected hypothesis's detail.
    let validation = if action == "promote" {
      validate_promote_hypothesis(
        reason,
        detail_demo_period_days.get(),
        detail_requires_compliance_review.get(),
        mnpi_checked,
      )
    } else if action == "reject" {
      validate_reject_hypothesis(reason)
    } else if action == "mnpi" {
      validate_mnpi_hypothesis(reason)
    } else {
      // retest has no body; no validation.
      ""
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
    let success_text = match action {
      "retest" => "✓ 再検証を受け付けました。"
      "promote" => "✓ 昇格申請を完了しました。"
      "reject" => "✓ 仮説を却下しました。"
      _ => "✓ MNPI自己申告を更新しました。"
    }
    ffi_post_hypothesis_action(
      base_url,
      identifier,
      action,
      reason,
      comment,
      mnpi_checked,
      fn(success, error_message) {
        loading.set(false)
        if success {
          is_err.set(false)
          msg.set(success_text)
        } else {
          is_err.set(true)
          msg.set("✗ 仮説操作に失敗しました。 " + error_message)
        }
      },
    )
  }

  // ── Render ───────────────────────────────────────────────────────────────────

  div(style="display:flex;flex-direction:column;gap:24px;", [
    // Status message area (aria-live) — MSG-I-0071..0073 / MSG-E-0071.
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
    // ── R-01 フィルタ (status) ──────────────────────────────────────────────────
    div(
      style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:16px 24px;display:flex;flex-direction:column;gap:8px;",
      [
        span(
          style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
          [text("状態フィルタ")],
        ),
        render_status_filter(status_filter, handle_status_select),
      ],
    ),
    // ── R-01 仮説一覧 ────────────────────────────────────────────────────────────
    div(
      style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
      attrs=[
        ("role", @element.AttrString("table")),
        ("aria-label", @element.AttrString("仮説一覧")),
      ],
      [
        render_hypothesis_header(),
        // Empty state (§6 empty)
        div(
          attrs=[("role", @element.AttrString("status"))],
          dyn_style=fn() {
            let visible = ffi_filtered_hypotheses_length(
              hypotheses.get(),
              status_filter.get(),
            )
            if visible == 0 {
              "padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
            } else {
              "display:none;"
            }
          },
          [text("該当する仮説がありません。")],
        ),
        // Reactive rows — re-render when hypotheses / filter change.
        for_each(
          fn() {
            ffi_filter_hypotheses(hypotheses.get(), status_filter.get())
          },
          fn(hypothesis, _index) {
            render_hypothesis_row(
              hypothesis,
              handle_select(hypothesis),
              selected_identifier,
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
    // ── R-02 指標領域 + R-03 操作領域 (選択時) ──────────────────────────────────
    hypotheses_render_detail_panel(
      selected_identifier,
      selected_status,
      detail_loading,
      detail_error,
      detail_instrument_type,
      detail_insider_risk,
      detail_demo_period,
      detail_cost_adjusted_return,
      detail_dsr,
      detail_pbo,
      detail_requires_compliance_review,
      detail_mnpi_self_declared,
      detail_auto_promotion_eligible,
      detail_promotion_mode,
      detail_skill_version,
      detail_instruction_profile_version,
      detail_source_evidence,
      detail_latest_failure_summary,
      handle_open_modal("retest"),
      handle_open_modal("promote"),
      handle_open_modal("reject"),
      handle_open_modal("mnpi"),
    ),
    // ── 操作モーダル (再検証 / 昇格申請 / 却下 / MNPI) ──────────────────────────
    hypotheses_render_operation_modal(
      show_modal,
      modal_action,
      modal_mnpi_checked,
      modal_validation_error,
      handle_reason_input,
      handle_comment_input,
      handle_mnpi_toggle,
      handle_modal_cancel,
      handle_modal_confirm,
      handle_modal_keydown,
    ),
  ])
}

// ── R-01 filter rendering ─────────────────────────────────────────────────────

///|
/// Status filter as a segmented button group (draft/backtested/demo/live/rejected
/// + すべて). The luna dom DSL has no <select> factory, so a button group is used.
/// The active button is highlighted via the status_filter signal.
fn render_status_filter(
  status_filter : @signal.Signal[String],
  on_select : (String) -> @element.MouseHandler
) -> DomNode {
  div(
    style="display:flex;gap:8px;flex-wrap:wrap;",
    attrs=[
      ("role", @element.AttrString("group")),
      ("aria-label", @element.AttrString("状態フィルタ")),
    ],
    [
      status_filter_button(status_filter, on_select, "", "すべて"),
      status_filter_button(status_filter, on_select, "draft", "draft"),
      status_filter_button(
        status_filter, on_select, "backtested", "backtested",
      ),
      status_filter_button(status_filter, on_select, "demo", "demo"),
      status_filter_button(status_filter, on_select, "live", "live"),
      status_filter_button(status_filter, on_select, "rejected", "rejected"),
    ],
  )
}

///|
/// A single status filter button (highlighted when its value is active).
fn status_filter_button(
  status_filter : @signal.Signal[String],
  on_select : (String) -> @element.MouseHandler,
  value : String,
  label_text : String
) -> DomNode {
  button(
    dyn_style=fn() {
      let base = "border-radius:999px;padding:6px 14px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;"
      if status_filter.get() == value {
        base +
        "background:rgba(99,102,241,0.25);color:#818CF8;border:1px solid rgba(99,102,241,0.5);"
      } else {
        base +
        "background:rgba(15,23,42,0.6);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.12);"
      }
    },
    dyn_attrs=[
      (
        "aria-pressed",
        @element.Dynamic(fn() {
          if status_filter.get() == value {
            "true"
          } else {
            "false"
          }
        }),
      ),
    ],
    on=events().click(on_select(value)),
    [text(label_text)],
  )
}

// ── R-01 table rendering ──────────────────────────────────────────────────────

///|
/// Header row for the hypothesis list (A11y: columnheader cells).
fn render_hypothesis_header() -> DomNode {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style=hypothesis_grid_style() +
      "border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @element.AttrString("row"))],
    [
      hypothesis_header_cell(cell, "銘柄"),
      hypothesis_header_cell(cell, "仮説"),
      hypothesis_header_cell(cell, "種別"),
      hypothesis_header_cell(cell, "状態"),
      hypothesis_header_cell(cell, "最終更新"),
    ],
  )
}

///|
fn hypothesis_header_cell(style : String, label_text : String) -> DomNode {
  div(style=style, attrs=[("role", @element.AttrString("columnheader"))], [
    text(label_text),
  ])
}

///|
/// Shared CSS grid template for header and rows (column alignment).
fn hypothesis_grid_style() -> String {
  "display:grid;grid-template-columns:minmax(90px,0.8fr) minmax(260px,3fr) minmax(80px,0.6fr) minmax(120px,0.9fr) minmax(150px,1.1fr);align-items:center;"
}

///|
/// Background/foreground colours for a status badge.
pub fn hypothesis_status_badge_style(status : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = match status {
    "draft" =>
      "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
    "backtested" =>
      "background:rgba(99,102,241,0.18);color:#818CF8;border:1px solid rgba(99,102,241,0.35);"
    "demo" =>
      "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
    "live" =>
      "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
    "rejected" =>
      "background:rgba(248,113,113,0.12);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.35);"
    _ =>
      "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// Background/foreground colours for an instrumentType badge.
fn instrument_type_badge_style(instrument_type : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = match instrument_type {
    "ETF" =>
      "background:rgba(34,197,94,0.12);color:#22C55E;border:1px solid rgba(34,197,94,0.3);"
    "STOCK" =>
      "background:rgba(99,102,241,0.14);color:#818CF8;border:1px solid rgba(99,102,241,0.3);"
    _ =>
      "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// Render a single hypothesis row. Selecting a row loads its detail (R-02).
fn render_hypothesis_row(
  hypothesis : HypothesisRowProps,
  on_select : @element.MouseHandler,
  selected_identifier : @signal.Signal[String]
) -> DomNode {
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  let identifier = hypothesis.identifier
  div(
    dyn_style=fn() {
      let base = hypothesis_grid_style() +
        "border-bottom:1px solid rgba(248,250,252,0.06);cursor:pointer;"
      if selected_identifier.get() == identifier {
        base + "background:rgba(99,102,241,0.08);"
      } else {
        base
      }
    },
    attrs=[
      ("role", @element.AttrString("row")),
      ("tabindex", @element.AttrString("0")),
    ],
    on=events().click(on_select),
    [
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        text(hypothesis.symbol),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        text(hypothesis.title),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        span(style=instrument_type_badge_style(hypothesis.instrument_type), [
          text(hypothesis.instrument_type),
        ]),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        span(style=hypothesis_status_badge_style(hypothesis.status), [
          text(hypothesis.status),
        ]),
      ]),
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        text(hypothesis.updated_at),
      ]),
    ],
  )
}

// ── R-02 指標領域 + R-03 操作領域 detail panel ───────────────────────────────

///|
/// Render the detail panel (R-02 指標 + R-03 操作). Visible once a row is selected.
fn hypotheses_render_detail_panel(
  selected_identifier : @signal.Signal[String],
  selected_status : @signal.Signal[String],
  detail_loading : @signal.Signal[Bool],
  detail_error : @signal.Signal[String],
  detail_instrument_type : @signal.Signal[String],
  detail_insider_risk : @signal.Signal[String],
  detail_demo_period : @signal.Signal[String],
  detail_cost_adjusted_return : @signal.Signal[String],
  detail_dsr : @signal.Signal[String],
  detail_pbo : @signal.Signal[String],
  detail_requires_compliance_review : @signal.Signal[Bool],
  detail_mnpi_self_declared : @signal.Signal[Bool],
  detail_auto_promotion_eligible : @signal.Signal[Bool],
  detail_promotion_mode : @signal.Signal[String],
  detail_skill_version : @signal.Signal[String],
  detail_instruction_profile_version : @signal.Signal[String],
  detail_source_evidence : @signal.Signal[String],
  detail_latest_failure_summary : @signal.Signal[String],
  on_retest : @element.MouseHandler,
  on_promote : @element.MouseHandler,
  on_reject : @element.MouseHandler,
  on_mnpi : @element.MouseHandler
) -> DomNode {
  div(
    attrs=[
      ("role", @element.AttrString("region")),
      ("aria-label", @element.AttrString("仮説詳細")),
      ("aria-live", @element.AttrString("polite")),
      ("tabindex", @element.AttrString("-1")),
    ],
    dyn_style=fn() {
      if selected_identifier.get() == "" {
        "display:none;"
      } else {
        "background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:24px;display:flex;flex-direction:column;gap:20px;"
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
            "display:flex;flex-direction:column;gap:20px;"
          }
        },
        [
          // R-02 指標テーブル (見出し付き — A11y §9)
          hypotheses_render_metrics_table(
            detail_cost_adjusted_return,
            detail_dsr,
            detail_pbo,
            detail_demo_period,
            detail_instrument_type,
            detail_insider_risk,
          ),
          // promotion eligibility flags
          hypotheses_render_eligibility(
            detail_requires_compliance_review,
            detail_mnpi_self_declared,
            detail_auto_promotion_eligible,
            detail_promotion_mode,
          ),
          // provenance fields
          hypotheses_render_provenance(
            detail_skill_version,
            detail_instruction_profile_version,
            detail_source_evidence,
            detail_latest_failure_summary,
          ),
          // R-03 操作領域 (状態遷移に応じたボタン)
          hypotheses_render_operation_buttons(
            selected_status,
            on_retest,
            on_promote,
            on_reject,
            on_mnpi,
          ),
        ],
      ),
    ],
  )
}

///|
/// R-02 指標テーブル (costAdjustedReturn, dsr, pbo, demoPeriod, instrumentType, insiderRisk).
/// A11y §9: table with column headers.
fn hypotheses_render_metrics_table(
  cost_adjusted_return : @signal.Signal[String],
  dsr : @signal.Signal[String],
  pbo : @signal.Signal[String],
  demo_period : @signal.Signal[String],
  instrument_type : @signal.Signal[String],
  insider_risk : @signal.Signal[String]
) -> DomNode {
  div(
    style="display:grid;grid-template-columns:repeat(auto-fit,minmax(140px,1fr));gap:12px;",
    attrs=[
      ("role", @element.AttrString("table")),
      ("aria-label", @element.AttrString("仮説指標")),
    ],
    [
      metric_cell("コスト控除後リターン (%)", cost_adjusted_return),
      metric_cell("DSR", dsr),
      metric_cell("PBO", pbo),
      metric_cell("デモ期間", demo_period),
      metric_cell("種別", instrument_type),
      metric_cell("インサイダーリスク", insider_risk),
    ],
  )
}

///|
fn metric_cell(label_text : String, value : @signal.Signal[String]) -> DomNode {
  div(
    style="display:flex;flex-direction:column;gap:6px;background:rgba(15,23,42,0.5);border:1px solid rgba(248,250,252,0.06);border-radius:6px;padding:12px;",
    attrs=[("role", @element.AttrString("cell"))],
    [
      div(
        style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.6875rem;font-weight:600;letter-spacing:0.04em;text-transform:uppercase;",
        attrs=[("role", @element.AttrString("columnheader"))],
        [text(label_text)],
      ),
      div(
        style="color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:1rem;font-weight:600;",
        [
          text_dyn(
            @signal.computed(fn() {
              let v = value.get()
              if v == "" {
                "—"
              } else {
                v
              }
            }),
          ),
        ],
      ),
    ],
  )
}

///|
/// Promotion eligibility flags (R-02): requiresComplianceReview, mnpiSelfDeclared,
/// autoPromotionEligible, promotionMode.
fn hypotheses_render_eligibility(
  requires_compliance_review : @signal.Signal[Bool],
  mnpi_self_declared : @signal.Signal[Bool],
  auto_promotion_eligible : @signal.Signal[Bool],
  promotion_mode : @signal.Signal[String]
) -> DomNode {
  div(style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;", [
    flag_badge("コンプライアンスレビュー", requires_compliance_review, true),
    flag_badge("MNPI自己申告", mnpi_self_declared, false),
    flag_badge("自動昇格可能", auto_promotion_eligible, false),
    span(
      dyn_attrs=[
        ("style", @element.Dynamic(fn() { promotion_mode_badge_style() })),
      ],
      [
        text_dyn(
          @signal.computed(fn() {
            let m = promotion_mode.get()
            if m == "" {
              "昇格モード: —"
            } else {
              "昇格モード: " + m
            }
          }),
        ),
      ],
    ),
  ])
}

///|
/// A boolean flag chip. `invert_danger=true` colours `true` as a warning
/// (e.g. requiresComplianceReview=true is a blocker), otherwise `true` is positive.
fn flag_badge(
  label_text : String,
  value : @signal.Signal[Bool],
  invert_danger : Bool
) -> DomNode {
  span(
    dyn_attrs=[
      (
        "style",
        @element.Dynamic(fn() {
          let on = value.get()
          let danger = (invert_danger && on) || (!invert_danger && !on)
          flag_badge_style(danger)
        }),
      ),
    ],
    [
      text_dyn(
        @signal.computed(fn() {
          if value.get() {
            label_text + ": true"
          } else {
            label_text + ": false"
          }
        }),
      ),
    ],
  )
}

///|
fn flag_badge_style(danger : Bool) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;"
  if danger {
    base +
    "background:rgba(248,113,113,0.12);color:#F87171;border:1px solid rgba(248,113,113,0.35);"
  } else {
    base +
    "background:rgba(34,197,94,0.12);color:#22C55E;border:1px solid rgba(34,197,94,0.35);"
  }
}

///|
fn promotion_mode_badge_style() -> String {
  "display:inline-block;padding:2px 10px;border-radius:999px;background:rgba(99,102,241,0.12);color:#818CF8;border:1px solid rgba(99,102,241,0.3);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;"
}

///|
/// Provenance fields (skillVersion, instructionProfileVersion, sourceEvidence,
/// latestFailureSummary).
fn hypotheses_render_provenance(
  skill_version : @signal.Signal[String],
  instruction_profile_version : @signal.Signal[String],
  source_evidence : @signal.Signal[String],
  latest_failure_summary : @signal.Signal[String]
) -> DomNode {
  div(style="display:flex;flex-direction:column;gap:14px;", [
    provenance_field("収集Skill版 (skillVersion)", skill_version, true),
    provenance_field(
      "指示プロファイル版 (instructionProfileVersion)",
      instruction_profile_version,
      true,
    ),
    provenance_field("根拠インサイト (sourceEvidence)", source_evidence, true),
    // latestFailureSummary — only shown when present.
    div(
      dyn_style=fn() {
        if latest_failure_summary.get() == "" {
          "display:none;"
        } else {
          "display:flex;flex-direction:column;gap:6px;"
        }
      },
      [
        div(
          style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;",
          [text("直近の失敗要約 (latestFailureSummary)")],
        ),
        div(
          style="color:#F87171;font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;line-height:1.5;",
          [text_of(latest_failure_summary)],
        ),
      ],
    ),
  ])
}

///|
fn provenance_field(
  label_text : String,
  value : @signal.Signal[String],
  mono : Bool
) -> DomNode {
  let value_style = if mono {
    "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;word-break:break-all;"
  } else {
    "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;line-height:1.5;"
  }
  div(style="display:flex;flex-direction:column;gap:6px;", [
    div(
      style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;",
      [text(label_text)],
    ),
    div(style=value_style, [
      text_dyn(
        @signal.computed(fn() {
          let v = value.get()
          if v == "" {
            "—"
          } else {
            v
          }
        }),
      ),
    ]),
  ])
}

///|
/// R-03 操作領域: 状態遷移に応じた操作ボタン (再検証 / 昇格申請 / MNPI / 却下)。
/// 状態遷移設計 §6 に従いボタンの可視を制御する (M8)。
fn hypotheses_render_operation_buttons(
  selected_status : @signal.Signal[String],
  on_retest : @element.MouseHandler,
  on_promote : @element.MouseHandler,
  on_reject : @element.MouseHandler,
  on_mnpi : @element.MouseHandler
) -> DomNode {
  div(
    style="display:flex;gap:10px;align-items:center;flex-wrap:wrap;border-top:1px solid rgba(248,250,252,0.08);padding-top:16px;",
    attrs=[("aria-label", @element.AttrString("仮説操作"))],
    [
      // 再検証 — status != live && != rejected
      operation_button(
        "再検証",
        "background:rgba(99,102,241,0.18);color:#818CF8;border:1px solid rgba(99,102,241,0.4);",
        on_retest,
        fn() { can_retest_hypothesis(selected_status.get()) },
      ),
      // MNPI自己申告更新 — status == demo
      operation_button(
        "MNPI自己申告",
        "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.4);",
        on_mnpi,
        fn() { can_update_mnpi_hypothesis(selected_status.get()) },
      ),
      // 昇格申請 — status == demo
      operation_button(
        "昇格申請",
        "background:rgba(34,197,94,0.15);color:#22C55E;border:1px solid rgba(34,197,94,0.4);",
        on_promote,
        fn() { can_promote_hypothesis(selected_status.get()) },
      ),
      // 却下 — status != live && != rejected
      operation_button(
        "却下",
        "background:rgba(248,113,113,0.12);color:#F87171;border:1px solid rgba(248,113,113,0.4);",
        on_reject,
        fn() { can_reject_hypothesis(selected_status.get()) },
      ),
    ],
  )
}

///|
/// A single operation button; hidden when `is_visible` computes to false (M8).
fn operation_button(
  label_text : String,
  colors : String,
  on_click : @element.MouseHandler,
  is_visible : () -> Bool
) -> DomNode {
  button(
    dyn_style=fn() {
      let base = "border-radius:6px;padding:6px 16px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;"
      if is_visible() {
        base + colors
      } else {
        "display:none;"
      }
    },
    on=events().click(on_click),
    [text(label_text)],
  )
}

// ── R-03 operation modal ───────────────────────────────────────────────────────

///|
/// Render the operation confirmation modal (再検証 / 昇格申請 / 却下 / MNPI).
/// A11y §9: closable via Esc; focus trap baseline (aria-modal).
fn hypotheses_render_operation_modal(
  show_modal : @signal.Signal[Bool],
  modal_action : @signal.Signal[String],
  modal_mnpi_checked : @signal.Signal[Bool],
  modal_validation_error : @signal.Signal[String],
  on_reason_input : @element.InputHandler,
  on_comment_input : @element.InputHandler,
  on_mnpi_toggle : @element.InputHandler,
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
      ("aria-label", @element.AttrString("仮説操作確認")),
      ("tabindex", @element.AttrString("-1")),
    ],
    on=events().keydown(on_keydown),
    [
      div(
        style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.12);border-radius:12px;padding:32px;width:100%;max-width:480px;box-sizing:border-box;display:flex;flex-direction:column;gap:20px;",
        [
          p(
            style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1.125rem;font-weight:700;margin:0;",
            [
              text_dyn(
                @signal.computed(fn() {
                  match modal_action.get() {
                    "retest" => "この仮説を再検証しますか？"
                    "promote" => "この仮説の昇格を申請しますか？"
                    "reject" => "この仮説を却下しますか？"
                    _ => "MNPI自己申告を更新しますか？"
                  }
                }),
              ),
            ],
          ),
          p(
            style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0;",
            [
              text_dyn(
                @signal.computed(fn() {
                  match modal_action.get() {
                    "retest" => "再検証を受け付けます。理由コードは不要です。"
                    "promote" =>
                      "昇格は本番運用に直結します。デモ期間・コンプライアンス・MNPI自己申告の条件を確認してください。"
                    _ => "操作理由コードを入力し、確認後に実行してください。"
                  }
                }),
              ),
            ],
          ),
          // MNPI 自己申告チェック (promote / mnpi のとき表示)
          div(
            dyn_style=fn() {
              let a = modal_action.get()
              if a == "promote" || a == "mnpi" {
                "display:flex;align-items:flex-start;gap:10px;background:rgba(234,179,8,0.08);border:1px solid rgba(234,179,8,0.25);border-radius:6px;padding:12px;"
              } else {
                "display:none;"
              }
            },
            [
              input(
                type_="checkbox",
                id="hypothesis-mnpi-checkbox",
                name="hypothesis-mnpi-checkbox",
                style="margin-top:2px;width:16px;height:16px;cursor:pointer;",
                dyn_checked=fn() { modal_mnpi_checked.get() },
                on=events().input(on_mnpi_toggle),
              ),
              label(
                for_="hypothesis-mnpi-checkbox",
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;line-height:1.5;cursor:pointer;",
                [
                  text(
                    "私はこの仮説に関する未公表の重要事実 (MNPI) を保有していないことを自己申告します。",
                  ),
                ],
              ),
            ],
          ),
          // Reason code input (retest は不要)
          div(
            dyn_style=fn() {
              if modal_action.get() == "retest" {
                "display:none;"
              } else {
                "display:flex;flex-direction:column;gap:6px;"
              }
            },
            [
              label(
                for_="hypothesis-reason-code",
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                [text("操作理由コード *")],
              ),
              input(
                type_="text",
                id="hypothesis-reason-code",
                name="hypothesis-reason-code",
                placeholder="例: MODEL_REVIEW_DECISION",
                style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
                on=events().input(on_reason_input),
              ),
            ],
          ),
          // Comment input (optional)
          div(
            dyn_style=fn() {
              if modal_action.get() == "retest" {
                "display:none;"
              } else {
                "display:flex;flex-direction:column;gap:6px;"
              }
            },
            [
              label(
                for_="hypothesis-comment",
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
                [text("コメント（任意・120文字以内）")],
              ),
              input(
                type_="text",
                id="hypothesis-comment",
                name="hypothesis-comment",
                placeholder="操作理由を入力...",
                style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'IBM Plex Sans',sans-serif;width:100%;box-sizing:border-box;",
                on=events().input(on_comment_input),
              ),
            ],
          ),
          // Validation error
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
                  "retest" => base + "background:#818CF8;"
                  "promote" => base + "background:#22C55E;"
                  "reject" => base + "background:#F87171;"
                  _ => base + "background:#EAB308;"
                }
              },
              on=events().click(on_confirm),
              [
                text_dyn(
                  @signal.computed(fn() {
                    match modal_action.get() {
                      "retest" => "再検証する"
                      "promote" => "昇格申請する"
                      "reject" => "却下する"
                      _ => "申告を更新する"
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

// ── FFI: detail struct ────────────────────────────────────────────────────────

///|
/// HypothesisDetail decoded from BFF GET /hypotheses/{identifier}.
/// Mirrors the OpenAPI HypothesisDetail schema (numeric metrics pre-formatted to
/// strings on the JS side so the signals stay String-typed).
priv struct HypothesisDetailFfi {
  instrument_type : String
  insider_risk : String
  demo_period : String
  demo_period_days : Int
  cost_adjusted_return : String
  dsr : String
  pbo : String
  requires_compliance_review : Bool
  mnpi_self_declared : Bool
  auto_promotion_eligible : Bool
  promotion_mode : String
  skill_version : String
  instruction_profile_version : String
  source_evidence : String
  latest_failure_summary : String
}

// ── FFI helpers ──────────────────────────────────────────────────────────────

///|
extern "js" fn ffi_clone_hypotheses(
  arr : Array[HypothesisRowProps]
) -> Array[HypothesisRowProps] =
  #| (arr) => arr.map(o => ({ identifier: o.identifier, symbol: o.symbol, instrument_type: o.instrument_type, status: o.status, title: o.title, updated_at: o.updated_at }))

///|
/// Append `more` to `arr`, returning a new array (immutable update for the signal).
extern "js" fn ffi_concat_hypotheses(
  arr : Array[HypothesisRowProps],
  more : Array[HypothesisRowProps]
) -> Array[HypothesisRowProps] =
  #| (arr, more) => arr.concat(more)

///|
/// Filter the hypothesis list by status (exact; empty = all).
extern "js" fn ffi_filter_hypotheses(
  arr : Array[HypothesisRowProps],
  status_filter : String
) -> Array[HypothesisRowProps] =
  #| (arr, status_filter) => {
  #|   const s = String(status_filter);
  #|   return arr.filter(o => s === '' || o.status === s);
  #| }

///|
/// Count of hypotheses visible under the current filter (for empty-state).
extern "js" fn ffi_filtered_hypotheses_length(
  arr : Array[HypothesisRowProps],
  status_filter : String
) -> Int =
  #| (arr, status_filter) => {
  #|   const s = String(status_filter);
  #|   return arr.filter(o => s === '' || o.status === s).length;
  #| }

///|
/// Parse a demoPeriod string into a day count. Accepts "45d", "6w", "2m"/"2month",
/// "1y", or a bare integer (days). Returns 0 when unparseable.
extern "js" fn hypotheses_ffi_parse_demo_days(demo_period : String) -> Int =
  #| (demo_period) => {
  #|   const s = String(demo_period ?? '').trim().toLowerCase();
  #|   if (s === '') return 0;
  #|   const m = s.match(/^(\d+(?:\.\d+)?)\s*(d|day|days|w|week|weeks|m|mo|month|months|y|year|years)?$/);
  #|   if (!m) return 0;
  #|   const n = parseFloat(m[1]);
  #|   if (!isFinite(n)) return 0;
  #|   const unit = m[2] || 'd';
  #|   let days = n;
  #|   if (unit.startsWith('w')) days = n * 7;
  #|   else if (unit === 'm' || unit.startsWith('mo')) days = n * 30;
  #|   else if (unit.startsWith('y')) days = n * 365;
  #|   return Math.floor(days);
  #| }

///|
/// Format a numeric metric with the given fraction digits (toLocaleString).
extern "js" fn hypotheses_ffi_format_number(
  value : Double,
  fraction_digits : Int
) -> String =
  #| (value, fraction_digits) => {
  #|   try { return value.toLocaleString('en-US', { minimumFractionDigits: fraction_digits, maximumFractionDigits: fraction_digits }); }
  #|   catch { return String(value); }
  #| }

///|
/// Fetch the next page of hypotheses from BFF GET /hypotheses?status=&cursor=...
/// Maps the OpenAPI HypothesisListResponse into rows + nextCursor.
extern "js" fn ffi_fetch_hypotheses(
  base_url : String,
  status : String,
  cursor : String,
  on_result : (Bool, Array[HypothesisRowProps], String, String) -> Unit
) -> Unit =
  #| (base_url, status, cursor, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const url = new URL('/hypotheses', base_url);
  #|   if (status) url.searchParams.set('status', status);
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
  #|         symbol: o.symbol ?? '',
  #|         instrument_type: o.instrumentType ?? '',
  #|         status: o.status ?? '',
  #|         title: o.title ?? '',
  #|         updated_at: o.updatedAt ?? '',
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
/// Fetch a single hypothesis detail from BFF GET /hypotheses/{identifier}.
/// Maps the OpenAPI HypothesisDetail; numeric metrics are formatted to strings.
extern "js" fn ffi_fetch_hypothesis_detail(
  base_url : String,
  identifier : String,
  on_result : (Bool, HypothesisDetailFfi, String) -> Unit
) -> Unit =
  #| (base_url, identifier, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const empty = { instrument_type: '', insider_risk: '', demo_period: '', demo_period_days: 0, cost_adjusted_return: '', dsr: '', pbo: '', requires_compliance_review: false, mnpi_self_declared: false, auto_promotion_eligible: false, promotion_mode: '', skill_version: '', instruction_profile_version: '', source_evidence: '', latest_failure_summary: '' };
  #|   const fmt = (v, d) => (typeof v === 'number' ? v.toLocaleString('en-US', { minimumFractionDigits: d, maximumFractionDigits: d }) : '');
  #|   const parseDays = (s) => {
  #|     s = String(s ?? '').trim().toLowerCase();
  #|     if (s === '') return 0;
  #|     const m = s.match(/^(\d+(?:\.\d+)?)\s*(d|day|days|w|week|weeks|m|mo|month|months|y|year|years)?$/);
  #|     if (!m) return 0;
  #|     const n = parseFloat(m[1]);
  #|     if (!isFinite(n)) return 0;
  #|     const unit = m[2] || 'd';
  #|     let days = n;
  #|     if (unit.startsWith('w')) days = n * 7;
  #|     else if (unit === 'm' || unit.startsWith('mo')) days = n * 30;
  #|     else if (unit.startsWith('y')) days = n * 365;
  #|     return Math.floor(days);
  #|   };
  #|   fetch(base_url + '/hypotheses/' + encodeURIComponent(identifier), {
  #|     method: 'GET',
  #|     headers: { ...(token ? { 'Authorization': 'Bearer ' + token } : {}) },
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data && data.identifier) {
  #|       on_result(true, {
  #|         instrument_type: data.instrumentType ?? '',
  #|         insider_risk: data.insiderRisk ?? '',
  #|         demo_period: data.demoPeriod ?? '',
  #|         demo_period_days: parseDays(data.demoPeriod),
  #|         cost_adjusted_return: fmt(data.costAdjustedReturn, 2),
  #|         dsr: fmt(data.dsr, 2),
  #|         pbo: fmt(data.pbo, 2),
  #|         requires_compliance_review: data.requiresComplianceReview === true,
  #|         mnpi_self_declared: data.mnpiSelfDeclared === true,
  #|         auto_promotion_eligible: data.autoPromotionEligible === true,
  #|         promotion_mode: data.promotionMode ?? '',
  #|         skill_version: data.skillVersion ?? '',
  #|         instruction_profile_version: data.instructionProfileVersion ?? '',
  #|         source_evidence: Array.isArray(data.sourceEvidence) ? data.sourceEvidence.join(', ') : '',
  #|         latest_failure_summary: data.latestFailureSummary ?? '',
  #|       }, '');
  #|     } else {
  #|       const msg = (data && data.detail) || '仮説詳細の取得に失敗しました。';
  #|       on_result(false, empty, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, empty, '仮説詳細の取得に失敗しました。'));
  #| }

///|
/// POST/PUT a hypothesis operation to the BFF.
///  - retest:  POST /hypotheses/{id}/retest                  (no body) → 202 { accepted }
///  - promote: POST /hypotheses/{id}/promote                 { actionReasonCode, mnpiSelfDeclared, comment? } → 200 { success }
///  - reject:  POST /hypotheses/{id}/reject                  { actionReasonCode, comment? } → 200 { success }
///  - mnpi:    PUT  /hypotheses/{id}/mnpi-self-declaration   { mnpiSelfDeclared, actionReasonCode, comment? } → 200 { success }
extern "js" fn ffi_post_hypothesis_action(
  base_url : String,
  identifier : String,
  action : String,
  reason_code : String,
  comment : String,
  mnpi_self_declared : Bool,
  on_result : (Bool, String) -> Unit
) -> Unit =
  #| (base_url, identifier, action, reason_code, comment, mnpi_self_declared, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const enc = encodeURIComponent(identifier);
  #|   let method = 'POST';
  #|   let path = '';
  #|   let body = null;
  #|   if (action === 'retest') {
  #|     path = '/hypotheses/' + enc + '/retest';
  #|   } else if (action === 'promote') {
  #|     path = '/hypotheses/' + enc + '/promote';
  #|     body = { actionReasonCode: reason_code, mnpiSelfDeclared: mnpi_self_declared };
  #|     if (comment) body.comment = comment;
  #|   } else if (action === 'reject') {
  #|     path = '/hypotheses/' + enc + '/reject';
  #|     body = { actionReasonCode: reason_code };
  #|     if (comment) body.comment = comment;
  #|   } else {
  #|     method = 'PUT';
  #|     path = '/hypotheses/' + enc + '/mnpi-self-declaration';
  #|     body = { mnpiSelfDeclared: mnpi_self_declared, actionReasonCode: reason_code };
  #|     if (comment) body.comment = comment;
  #|   }
  #|   fetch(base_url + path, {
  #|     method,
  #|     headers: {
  #|       'Content-Type': 'application/json',
  #|       ...(token ? { 'Authorization': 'Bearer ' + token } : {}),
  #|     },
  #|     ...(body ? { body: JSON.stringify(body) } : {}),
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })).catch(() => ({ ok: res.ok, data: {} })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && (data.success === true || data.accepted === true)) {
  #|       on_result(true, '');
  #|     } else {
  #|       const msg = (data && data.detail) || '仮説操作に失敗しました。再試行してください。';
  #|       on_result(false, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, '仮説操作に失敗しました。再試行してください。'));
  #| }
