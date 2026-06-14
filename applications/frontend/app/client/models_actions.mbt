///| Model Validation Actions Island Component (SCR-005)
///|
///| Interactive model-validation panel: status filter, per-model detail metrics
///| (fetched on row select), and promote/reject (昇格/差し戻し) actions gated by the
///| Model Status state machine, with a decision confirmation modal.
///| This is a client component: it runs in the browser after hydration.
///|
///| Model Status state machine (documents/外部設計/state/状態遷移設計.md):
///|   candidate --promote(approve)--> approved (terminal)
///|   candidate --reject--> rejected (terminal)
///|   approved / rejected are terminal — no mutating action.
///|
///| Operations (documents/外部設計/screens/SCR-005_モデル検証.md §4):
///|  - A-0051 昇格:   POST /models/validation/{modelVersion}/approve
///|                   (pre: status=candidate, reasonCode required, flag!=block, no compliance hold)
///|  - A-0052 差し戻し: POST /models/validation/{modelVersion}/reject
///|                   (pre: status=candidate, reasonCode required)
///|  - 行選択 (R-02):  GET /models/validation/{modelVersion} → metrics panel
///|  - 状態フィルタ:    re-fetch GET /models/validation?status=...
///|
///| Ref: documents/外部設計/screens/SCR-005_モデル検証.md
///| Ref: documents/外部設計/api/openapi.yaml (ModelDecisionRequest, ModelMetrics, OperationResult)
///| Ref: documents/外部設計/state/状態遷移設計.md

///|
/// A single model-validation row passed from the server (SSR initial state) or
/// fetched from BFF GET /models/validation. Mirrors the OpenAPI
/// ModelValidationSummary schema.
pub(all) struct ModelValidationRowProps {
  model_version : String
  status : String
  degradation_flag : String
  created_at : String
} derive(ToJson, FromJson)

///|
/// Props passed from the server (SSR initial state).
pub(all) struct ModelsActionsProps {
  bff_base_url : String
  initial_models : Array[ModelValidationRowProps]
} derive(ToJson, FromJson)

// ── Pure state-machine logic (unit-tested) ───────────────────────────────────

///|
/// Whether the 昇格 (promote/approve) action is permitted for a model status.
/// promote is only valid from `candidate` (approved/rejected are terminal).
pub fn can_promote_model(status : String) -> Bool {
  status == "candidate"
}

///|
/// Whether the 差し戻し (reject) action is permitted for a model status.
/// reject is only valid from `candidate`.
pub fn can_reject_model(status : String) -> Bool {
  status == "candidate"
}

///|
/// Validate a promotion (approve) submission. Returns an error message, or "" when valid.
/// Rules (SCR-005 §5):
///   - actionReasonCode required
///   - comment <= 120 chars
///   - degradationFlag must not be "block" (直近性能劣化)
///   - requiresComplianceReview must be false (コンプライアンスレビュー)
pub fn validate_promote_model(
  reason_code : String,
  comment : String,
  degradation_flag : String,
  requires_compliance_review : Bool
) -> String {
  if reason_code == "" {
    "昇格理由コードを選択してください"
  } else if ffi_string_length(comment) > 120 {
    "コメントは120文字以内で入力してください"
  } else if degradation_flag == "block" {
    "直近性能劣化のため昇格できません"
  } else if requires_compliance_review {
    "コンプライアンスレビュー完了後に実行してください"
  } else {
    ""
  }
}

///|
/// Validate a reject (差し戻し) submission. Returns an error message, or "" when valid.
/// Rules (SCR-005 §5): actionReasonCode required; comment <= 120 chars.
pub fn validate_reject_model(reason_code : String, comment : String) -> String {
  if reason_code == "" {
    "差し戻し理由コードを選択してください"
  } else if ffi_string_length(comment) > 120 {
    "コメントは120文字以内で入力してください"
  } else {
    ""
  }
}

///|
/// Format a percentage metric value (F-0053/55/56/57/59 are `%`).
pub fn format_percent_metric(value : Double) -> String {
  ffi_format_percent(value)
}

///|
/// Format a ratio metric value (F-0054/58/60 are `0.00`).
pub fn format_ratio_metric(value : Double) -> String {
  ffi_format_ratio(value)
}

// ── Island ───────────────────────────────────────────────────────────────────

///|
/// Model Validation Actions Island component.
pub fn models_actions(props : ModelsActionsProps) -> DomNode {
  let models = @signal.signal(ffi_clone_models(props.initial_models))
  let status_filter = @signal.signal("")
  let is_loading = @signal.signal(false)
  let status_message = @signal.signal("")
  let status_is_error = @signal.signal(false)

  // Detail (R-02 metrics panel) state.
  let selected_version = @signal.signal("")
  let detail_loading = @signal.signal(false)
  let detail_error = @signal.signal("")
  let detail_status = @signal.signal("")
  let detail_flag = @signal.signal("")
  let detail_requires_review = @signal.signal(false)
  // Metrics, formatted to display strings.
  let metric_oos_return = @signal.signal("")
  let metric_sharpe = @signal.signal("")
  let metric_max_drawdown = @signal.signal("")
  let metric_turnover = @signal.signal("")
  let metric_pbo = @signal.signal("")
  let metric_dsr = @signal.signal("")
  let metric_cost_adjusted = @signal.signal("")
  let metric_slippage_sharpe = @signal.signal("")

  // Decision modal state (shared by 昇格 / 差し戻し).
  let show_modal = @signal.signal(false)
  let modal_action = @signal.signal("") // "approve" | "reject"
  let modal_target = @signal.signal("")
  let modal_reason_code = @signal.signal("")
  let modal_comment = @signal.signal("")
  let modal_validation_error = @signal.signal("")

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
    let rows = models
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    ffi_fetch_models(base_url, status, fn(success, fetched, error_message) {
      loading.set(false)
      if success {
        rows.set(fetched)
        is_err.set(false)
        msg.set("")
      } else {
        is_err.set(true)
        msg.set("✗ " + error_message)
      }
    })
  }

  // ── 行選択 (R-02 詳細メトリクス) ────────────────────────────────────────────

  let handle_select : (String) -> @element.MouseHandler = fn(model_version) {
    fn(_e) {
      if detail_loading.get() {
        return
      }
      selected_version.set(model_version)
      detail_loading.set(true)
      detail_error.set("")
      let base_url = props.bff_base_url
      let loading = detail_loading
      let err = detail_error
      let d_status = detail_status
      let d_flag = detail_flag
      let d_review = detail_requires_review
      let m_oos = metric_oos_return
      let m_sharpe = metric_sharpe
      let m_dd = metric_max_drawdown
      let m_turn = metric_turnover
      let m_pbo = metric_pbo
      let m_dsr = metric_dsr
      let m_cost = metric_cost_adjusted
      let m_slip = metric_slippage_sharpe
      ffi_fetch_model_detail(
        base_url,
        model_version,
        fn(
          success,
          status,
          flag,
          requires_review,
          oos_return,
          sharpe,
          max_drawdown,
          turnover,
          pbo,
          dsr,
          cost_adjusted,
          slippage_sharpe,
          error_message
        ) {
          loading.set(false)
          if success {
            d_status.set(status)
            d_flag.set(flag)
            d_review.set(requires_review)
            m_oos.set(format_percent_metric(oos_return))
            m_sharpe.set(format_ratio_metric(sharpe))
            m_dd.set(format_percent_metric(max_drawdown))
            m_turn.set(format_percent_metric(turnover))
            m_pbo.set(format_percent_metric(pbo))
            m_dsr.set(format_ratio_metric(dsr))
            m_cost.set(format_percent_metric(cost_adjusted))
            m_slip.set(format_ratio_metric(slippage_sharpe))
            err.set("")
          } else {
            err.set("✗ " + error_message)
          }
        },
      )
    }
  }

  // ── 判定モーダル (昇格 / 差し戻し) ──────────────────────────────────────────

  let handle_open_modal : (String, String) -> @element.MouseHandler = fn(
    action,
    model_version
  ) {
    fn(_e) {
      if is_loading.get() {
        return
      }
      modal_action.set(action)
      modal_target.set(model_version)
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
    let model_version = modal_target.get()
    let reason = modal_reason_code.get()
    let comment = modal_comment.get()
    // Re-validate against the selected model's detail (flag / compliance review).
    let validation = if action == "approve" {
      validate_promote_model(
        reason,
        comment,
        detail_flag.get(),
        detail_requires_review.get(),
      )
    } else {
      validate_reject_model(reason, comment)
    }
    if validation != "" {
      modal_validation_error.set(validation)
      return
    }
    show_modal.set(false)
    is_loading.set(true)
    status_message.set("")
    let base_url = props.bff_base_url
    let rows = models
    let loading = is_loading
    let msg = status_message
    let is_err = status_is_error
    let new_status = if action == "approve" { "approved" } else { "rejected" }
    let success_text = if action == "approve" {
      "✓ モデルを昇格しました。"
    } else {
      "✓ モデルを差し戻しました。"
    }
    let d_status = detail_status
    ffi_post_model_action(
      base_url,
      model_version,
      action,
      reason,
      comment,
      fn(success, error_message) {
        loading.set(false)
        if success {
          rows.set(ffi_set_model_status(rows.get(), model_version, new_status))
          if selected_version.get() == model_version {
            d_status.set(new_status)
          }
          is_err.set(false)
          msg.set(success_text)
        } else {
          is_err.set(true)
          msg.set("✗ モデル状態の更新に失敗しました。 " + error_message)
        }
      },
    )
  }

  // ── Render ───────────────────────────────────────────────────────────────────

  div(style="display:flex;flex-direction:column;gap:24px;", [
    // Status message area (aria-live for a11y) — MSG-I-0051 / MSG-I-0052 / MSG-E-0051.
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
    // ── R-01 状態フィルタ ──────────────────────────────────────────────────────
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
            placeholder="例: candidate / approved / rejected（空=全件）",
            style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;min-width:280px;box-sizing:border-box;",
            on=events().input(handle_status_filter_change),
            attrs=[("aria-label", @element.AttrString("モデル状態フィルタ"))],
          ),
        ]),
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
    // ── R-01 モデル一覧 ────────────────────────────────────────────────────────
    div(
      style="background:var(--color-surface,#1E293B);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:8px;overflow-x:auto;",
      attrs=[
        ("role", @element.AttrString("table")),
        ("aria-label", @element.AttrString("モデル検証一覧")),
      ],
      [
        render_model_header(),
        // Empty state (§6 empty)
        div(
          attrs=[("role", @element.AttrString("status"))],
          dyn_style=fn() {
            if ffi_models_length(models.get()) == 0 {
              "padding:32px;text-align:center;color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;"
            } else {
              "display:none;"
            }
          },
          [text("候補モデルがありません。")],
        ),
        // Reactive rows — re-render when `models` signal changes (filter / action).
        for_each(fn() { models.get() }, fn(model, _index) {
          render_model_row(
            model,
            handle_select(model.model_version),
            handle_open_modal("approve", model.model_version),
            handle_open_modal("reject", model.model_version),
          )
        }),
      ],
    ),
    // ── R-02 指標パネル (選択時) ───────────────────────────────────────────────
    render_metrics_panel(
      selected_version,
      detail_loading,
      detail_error,
      detail_status,
      detail_flag,
      detail_requires_review,
      metric_oos_return,
      metric_sharpe,
      metric_max_drawdown,
      metric_turnover,
      metric_pbo,
      metric_dsr,
      metric_cost_adjusted,
      metric_slippage_sharpe,
    ),
    // ── R-03 判定モーダル (昇格 / 差し戻し) ────────────────────────────────────
    render_decision_modal(
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

// ── R-01 table rendering ──────────────────────────────────────────────────────

///|
/// Header row for the model list (A11y: columnheader cells).
fn render_model_header() -> DomNode {
  let cell = "color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;padding:8px 12px;"
  div(
    style=model_grid_style() + "border-bottom:1px solid rgba(248,250,252,0.12);",
    attrs=[("role", @element.AttrString("row"))],
    [
      model_header_cell(cell, "モデル版"),
      model_header_cell(cell, "状態"),
      model_header_cell(cell, "劣化フラグ"),
      model_header_cell(cell, "作成日時"),
      model_header_cell(cell, "操作"),
    ],
  )
}

///|
fn model_header_cell(style : String, label_text : String) -> DomNode {
  div(style=style, attrs=[("role", @element.AttrString("columnheader"))], [
    text(label_text),
  ])
}

///|
/// Shared CSS grid template for header and rows (column alignment).
fn model_grid_style() -> String {
  "display:grid;grid-template-columns:minmax(200px,2fr) 1fr 1fr 1.6fr minmax(200px,1.4fr);align-items:center;"
}

///|
/// Background/foreground colours for a model status badge.
/// approved → accent; rejected → loss; candidate → warning/neutral.
fn model_status_badge_style(status : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = match status {
    "approved" =>
      "background:rgba(34,197,94,0.15);color:var(--color-profit,#22C55E);border:1px solid rgba(34,197,94,0.35);"
    "candidate" =>
      "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
    "rejected" =>
      "background:rgba(248,113,113,0.12);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.35);"
    _ =>
      "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// Background/foreground colours for a degradation flag badge.
/// normal → neutral; warn → amber; block → loss.
fn degradation_flag_badge_style(flag : String) -> String {
  let base = "display:inline-block;padding:2px 10px;border-radius:999px;font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;"
  let colors = match flag {
    "warn" =>
      "background:rgba(234,179,8,0.12);color:#EAB308;border:1px solid rgba(234,179,8,0.35);"
    "block" =>
      "background:rgba(248,113,113,0.18);color:var(--color-loss,#F87171);border:1px solid rgba(248,113,113,0.5);"
    _ =>
      "background:rgba(248,250,252,0.08);color:rgba(248,250,252,0.7);border:1px solid rgba(248,250,252,0.15);"
  }
  base + colors
}

///|
/// Render a single model row, with state-gated promote/reject buttons.
fn render_model_row(
  model : ModelValidationRowProps,
  on_select : @element.MouseHandler,
  on_promote : @element.MouseHandler,
  on_reject : @element.MouseHandler
) -> DomNode {
  let mono = "color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:0.8125rem;padding:10px 12px;"
  let cell = "color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;padding:10px 12px;"
  div(
    style=model_grid_style() +
      "border-bottom:1px solid rgba(248,250,252,0.06);cursor:pointer;",
    attrs=[
      ("role", @element.AttrString("row")),
      ("tabindex", @element.AttrString("0")),
    ],
    on=events().click(on_select),
    [
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        code(style="font-family:'JetBrains Mono',monospace;", [
          text(model.model_version),
        ]),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        span(style=model_status_badge_style(model.status), [text(model.status)]),
      ]),
      div(style=cell, attrs=[("role", @element.AttrString("cell"))], [
        span(style=degradation_flag_badge_style(model.degradation_flag), [
          text(model.degradation_flag),
        ]),
      ]),
      div(style=mono, attrs=[("role", @element.AttrString("cell"))], [
        text(model.created_at),
      ]),
      // R-03 操作 — state-gated decision buttons (stopPropagation so they don't select).
      div(
        style="padding:8px 12px;display:flex;gap:8px;align-items:center;",
        attrs=[("role", @element.AttrString("cell"))],
        [render_model_action_buttons(model.status, on_promote, on_reject)],
      ),
    ],
  )
}

///|
/// Render the decision buttons applicable to a model's status (state machine).
/// candidate → 昇格 + 差し戻し; approved/rejected → terminal ("—").
fn render_model_action_buttons(
  status : String,
  on_promote : @element.MouseHandler,
  on_reject : @element.MouseHandler
) -> DomNode {
  if not(can_promote_model(status)) && not(can_reject_model(status)) {
    span(
      style="color:rgba(248,250,252,0.35);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;",
      [text("—")],
    )
  } else {
    fragment([
      button(
        style="background:rgba(34,197,94,0.15);color:#22C55E;border:1px solid rgba(34,197,94,0.4);border-radius:6px;padding:6px 14px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
        on=events().click(fn(e) {
          e.stopPropagation()
          on_promote(e)
        }),
        [text("昇格")],
      ),
      button(
        style="background:rgba(248,113,113,0.12);color:#F87171;border:1px solid rgba(248,113,113,0.4);border-radius:6px;padding:6px 14px;font-size:0.8125rem;font-family:'IBM Plex Sans',sans-serif;font-weight:600;cursor:pointer;",
        on=events().click(fn(e) {
          e.stopPropagation()
          on_reject(e)
        }),
        [text("差し戻し")],
      ),
    ])
  }
}

// ── R-02 metrics panel ────────────────────────────────────────────────────────

///|
/// Render the metrics panel (R-02). Visible once a model row is selected.
/// All metric VALUES are rendered in JetBrains Mono (F-0053..F-0060).
fn render_metrics_panel(
  selected_version : @signal.Signal[String],
  detail_loading : @signal.Signal[Bool],
  detail_error : @signal.Signal[String],
  detail_status : @signal.Signal[String],
  detail_flag : @signal.Signal[String],
  detail_requires_review : @signal.Signal[Bool],
  metric_oos_return : @signal.Signal[String],
  metric_sharpe : @signal.Signal[String],
  metric_max_drawdown : @signal.Signal[String],
  metric_turnover : @signal.Signal[String],
  metric_pbo : @signal.Signal[String],
  metric_dsr : @signal.Signal[String],
  metric_cost_adjusted : @signal.Signal[String],
  metric_slippage_sharpe : @signal.Signal[String]
) -> DomNode {
  div(
    attrs=[
      ("role", @element.AttrString("region")),
      ("aria-label", @element.AttrString("モデル指標")),
      ("aria-live", @element.AttrString("polite")),
      ("tabindex", @element.AttrString("-1")),
    ],
    dyn_style=fn() {
      if selected_version.get() == "" {
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
            style="display:flex;align-items:center;gap:12px;flex-wrap:wrap;",
            [
              div(
                style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:1rem;font-weight:600;",
                [text("指標パネル")],
              ),
              // Selected model status badge (updates after 昇格/差し戻し).
              span(
                dyn_attrs=[
                  (
                    "style",
                    @element.Dynamic(fn() {
                      model_status_badge_style(detail_status.get())
                    }),
                  ),
                ],
                [text_of(detail_status)],
              ),
            ],
          ),
          code(
            style="color:rgba(248,250,252,0.7);font-family:'JetBrains Mono',monospace;font-size:0.8125rem;",
            [text_of(selected_version)],
          ),
        ],
      ),
      // MSG-W-0051 degradation warning (warn) banner.
      div(
        attrs=[("role", @element.AttrString("status"))],
        dyn_style=fn() {
          if detail_flag.get() == "warn" {
            "padding:8px 14px;border-radius:6px;background:rgba(234,179,8,0.12);border:1px solid rgba(234,179,8,0.35);color:#EAB308;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
          } else {
            "display:none;"
          }
        },
        [text("⚠ 直近期間で性能劣化を検知しました。")],
      ),
      // Compliance-review notice.
      div(
        attrs=[("role", @element.AttrString("status"))],
        dyn_style=fn() {
          if detail_requires_review.get() {
            "padding:8px 14px;border-radius:6px;background:rgba(99,102,241,0.12);border:1px solid rgba(99,102,241,0.3);color:#818CF8;font-family:'IBM Plex Sans',sans-serif;font-size:0.8125rem;"
          } else {
            "display:none;"
          }
        },
        [text("コンプライアンスレビュー完了後に昇格できます。")],
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
      // Metrics table — header roles for A11y (§9).
      div(
        dyn_style=fn() {
          if detail_loading.get() || detail_error.get() != "" {
            "display:none;"
          } else {
            "display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;"
          }
        },
        attrs=[
          ("role", @element.AttrString("table")),
          ("aria-label", @element.AttrString("モデル評価指標")),
        ],
        [
          metric_card("OOSリターン", metric_oos_return),
          metric_card("Sharpe", metric_sharpe),
          metric_card("最大DD", metric_max_drawdown),
          metric_card("回転率", metric_turnover),
          metric_card("PBO", metric_pbo),
          metric_card("DSR", metric_dsr),
          metric_card("コスト控除後リターン", metric_cost_adjusted),
          metric_card("スリッページ控除後Sharpe", metric_slippage_sharpe),
        ],
      ),
    ],
  )
}

///|
/// A single metric card. Label in UI font, VALUE in JetBrains Mono (F-format).
fn metric_card(
  label_text : String,
  value : @signal.Signal[String]
) -> DomNode {
  div(
    style="display:flex;flex-direction:column;gap:6px;background:rgba(15,23,42,0.5);border:1px solid rgba(248,250,252,0.08);border-radius:8px;padding:14px 16px;",
    attrs=[("role", @element.AttrString("row"))],
    [
      div(
        style="color:rgba(248,250,252,0.5);font-family:'IBM Plex Sans',sans-serif;font-size:0.75rem;font-weight:600;letter-spacing:0.04em;",
        attrs=[("role", @element.AttrString("rowheader"))],
        [text(label_text)],
      ),
      div(
        style="color:var(--color-text,#F8FAFC);font-family:'JetBrains Mono','IBM Plex Sans',monospace;font-size:1.25rem;font-weight:600;",
        attrs=[("role", @element.AttrString("cell"))],
        [text_of(value)],
      ),
    ],
  )
}

// ── R-03 decision modal ───────────────────────────────────────────────────────

///|
/// Render the decision confirmation modal (昇格 / 差し戻し).
/// A11y §9: closable via Esc (keydown handler on the dialog).
fn render_decision_modal(
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
      ("aria-label", @element.AttrString("モデル判定確認")),
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
                  if modal_action.get() == "approve" {
                    "モデルを昇格しますか？"
                  } else {
                    "モデルを差し戻しますか？"
                  }
                }),
              ),
            ],
          ),
          p(
            style="color:rgba(248,250,252,0.6);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;margin:0;",
            [text("判定理由コードを選択し、確認後に実行してください。")],
          ),
          // Reason code input (F-0063)
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(
              for_="model-reason-code",
              style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
              [text("判定理由コード *")],
            ),
            input(
              type_="text",
              id="model-reason-code",
              name="model-reason-code",
              placeholder="例: MANUAL_OPERATION / MODEL_REVIEW_DECISION",
              style="background:rgba(15,23,42,0.8);color:var(--color-text,#F8FAFC);border:1px solid rgba(248,250,252,0.15);border-radius:6px;padding:8px 12px;font-size:0.875rem;font-family:'JetBrains Mono','IBM Plex Sans',monospace;width:100%;box-sizing:border-box;",
              on=events().input(on_reason_input),
            ),
          ]),
          // Comment input (F-0064)
          div(style="display:flex;flex-direction:column;gap:6px;", [
            label(
              for_="model-comment",
              style="color:var(--color-text,#F8FAFC);font-family:'IBM Plex Sans',sans-serif;font-size:0.875rem;font-weight:500;",
              [text("判定コメント（任意、120文字以内）")],
            ),
            input(
              type_="text",
              id="model-comment",
              name="model-comment",
              placeholder="判定理由を入力...",
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
                if modal_action.get() == "approve" {
                  base + "background:#22C55E;"
                } else {
                  base + "background:#F87171;"
                }
              },
              on=events().click(on_confirm),
              [
                text_dyn(
                  @signal.computed(fn() {
                    if modal_action.get() == "approve" {
                      "昇格する"
                    } else {
                      "差し戻す"
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
// Note: ffi_string_length (dashboard_operations.mbt) is already defined at
// package scope and reused here for comment-length validation.

///|
extern "js" fn ffi_clone_models(
  arr : Array[ModelValidationRowProps]
) -> Array[ModelValidationRowProps] =
  #| (arr) => arr.map(o => ({ model_version: o.model_version, status: o.status, degradation_flag: o.degradation_flag, created_at: o.created_at }))

///|
extern "js" fn ffi_models_length(arr : Array[ModelValidationRowProps]) -> Int =
  #| (arr) => arr.length

///|
/// Immutably set the status of the model with the given modelVersion.
extern "js" fn ffi_set_model_status(
  arr : Array[ModelValidationRowProps],
  model_version : String,
  status : String
) -> Array[ModelValidationRowProps] =
  #| (arr, model_version, status) => arr.map(o => o.model_version === model_version ? ({ ...o, status }) : o)

///|
/// Format a percentage value (F-0053/55/56/57/59: `%`, 2 fraction digits).
extern "js" fn ffi_format_percent(value : Double) -> String =
  #| (value) => {
  #|   try { return value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + '%'; }
  #|   catch { return String(value) + '%'; }
  #| }

///|
/// Format a ratio value (F-0054/58/60: `0.00`, 2 fraction digits).
extern "js" fn ffi_format_ratio(value : Double) -> String =
  #| (value) => {
  #|   try { return value.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
  #|   catch { return String(value); }
  #| }

///|
/// Fetch the model-validation list from BFF GET /models/validation (optionally
/// filtered by status). Maps the OpenAPI ModelValidationListResponse into rows.
extern "js" fn ffi_fetch_models(
  base_url : String,
  status : String,
  on_result : (Bool, Array[ModelValidationRowProps], String) -> Unit
) -> Unit =
  #| (base_url, status, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const url = new URL('/models/validation', base_url);
  #|   if (status) url.searchParams.set('status', status);
  #|   fetch(url.toString(), {
  #|     method: 'GET',
  #|     headers: { ...(token ? { 'Authorization': 'Bearer ' + token } : {}) },
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data && Array.isArray(data.items)) {
  #|       const rows = data.items.map(o => ({
  #|         model_version: o.modelVersion ?? '',
  #|         status: o.status ?? '',
  #|         degradation_flag: o.degradationFlag ?? '',
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
/// Fetch a single model-validation detail from BFF GET /models/validation/{modelVersion}.
/// Maps the OpenAPI ModelValidationDetail (status, degradationFlag, metrics,
/// requiresComplianceReview) for the metrics panel.
extern "js" fn ffi_fetch_model_detail(
  base_url : String,
  model_version : String,
  on_result : (
    Bool,
    String,
    String,
    Bool,
    Double,
    Double,
    Double,
    Double,
    Double,
    Double,
    Double,
    Double,
    String,
  ) -> Unit
) -> Unit =
  #| (base_url, model_version, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   fetch(base_url + '/models/validation/' + encodeURIComponent(model_version), {
  #|     method: 'GET',
  #|     headers: { ...(token ? { 'Authorization': 'Bearer ' + token } : {}) },
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data && data.metrics) {
  #|       const m = data.metrics;
  #|       on_result(
  #|         true,
  #|         data.status ?? '',
  #|         data.degradationFlag ?? '',
  #|         data.requiresComplianceReview === true,
  #|         m.oosReturn ?? 0.0,
  #|         m.sharpe ?? 0.0,
  #|         m.maxDrawdown ?? 0.0,
  #|         m.turnover ?? 0.0,
  #|         m.pbo ?? 0.0,
  #|         m.dsr ?? 0.0,
  #|         m.costAdjustedReturn ?? 0.0,
  #|         m.slippageAdjustedSharpe ?? 0.0,
  #|         '',
  #|       );
  #|     } else {
  #|       const msg = (data && data.detail) || 'モデル指標の取得に失敗しました。';
  #|       on_result(false, '', '', false, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, '', '', false, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 'モデル指標の取得に失敗しました。'));
  #| }

///|
/// POST a model decision (approve | reject) to the BFF.
/// Sends a ModelDecisionRequest { actionReasonCode (required), comment? }.
/// approve/reject return OperationResult { success }.
extern "js" fn ffi_post_model_action(
  base_url : String,
  model_version : String,
  action : String,
  reason_code : String,
  comment : String,
  on_result : (Bool, String) -> Unit
) -> Unit =
  #| (base_url, model_version, action, reason_code, comment, on_result) => {
  #|   let token = '';
  #|   try { token = sessionStorage.getItem('__alpha_mind_token__') ?? ''; } catch {}
  #|   const body = { actionReasonCode: reason_code };
  #|   if (comment) body.comment = comment;
  #|   fetch(base_url + '/models/validation/' + encodeURIComponent(model_version) + '/' + action, {
  #|     method: 'POST',
  #|     headers: {
  #|       'Content-Type': 'application/json',
  #|       ...(token ? { 'Authorization': 'Bearer ' + token } : {}),
  #|     },
  #|     body: JSON.stringify(body),
  #|   })
  #|   .then(res => res.json().then(data => ({ ok: res.ok, data })).catch(() => ({ ok: res.ok, data: {} })))
  #|   .then(({ ok, data }) => {
  #|     if (ok && data.success === true) {
  #|       on_result(true, '');
  #|     } else {
  #|       const msg = (data && data.detail) || 'モデル状態の更新に失敗しました。再試行してください。';
  #|       on_result(false, msg);
  #|     }
  #|   })
  #|   .catch(() => on_result(false, 'モデル状態の更新に失敗しました。再試行してください。'));
  #| }
