///| StatusPanel organism (operations: runtime status + kill switch).
///|
///| The SCR-001 operations panel: a `@molecules.card` surface showing the live
///| runtime status and kill-switch state as `@atoms.status_badge_atom`s, with the
///| primary controls — a runtime start/stop button (`@atoms.button_atom`) and a
///| kill-switch `@atoms.toggle_atom` — plus a conditional warning banner when the
///| kill switch is enabled (CLAUDE.md: kill switch 有効時は承認/執行系を停止).
///| Server component: the actual POST /operations/* calls are wired by the
///| DashboardOperations client Island via the rendered `data-action` attributes;
///| this organism renders the accessible structure and the SSR snapshot.
///|
///| Ref: documents/外部設計/screens/SCR-001_ダッシュボード.md (R-03 操作パネル),
///|      documents/外部設計/state/状態遷移設計.md (Runtime, Kill Switch),
///|      CLAUDE.md (kill switch)

///|
/// Render the operations status panel.
///
/// - `runtime_state`: "RUNNING" / "STOPPED" — drives the badge and button label.
/// - `kill_switch_enabled`: drives the kill-switch badge, toggle and warning.
/// - `title`: panel title (default "緊急操作パネル").
/// - `extra_style`: caller-appended inline style on the card surface.
pub fn status_panel(
  runtime_state~ : String,
  kill_switch_enabled~ : Bool,
  title~ : String = "緊急操作パネル",
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let running = runtime_state == "RUNNING"
  let status_row = div(
    style="display:flex;align-items:center;gap:var(--space-lg,24px);flex-wrap:wrap;",
    [
      status_pair("運用状態", @atoms.status_badge_atom(runtime_state)),
      status_pair(
        "Kill Switch",
        @atoms.status_badge_atom(
          if kill_switch_enabled { "ENABLED" } else { "DISABLED" },
        ),
      ),
    ],
  )
  let warning : @luna.Node[Unit, String] = if kill_switch_enabled {
    div(
      attrs=[("role", @luna.attr_static("alert"))],
      style="display:flex;align-items:center;gap:8px;padding:10px 16px;border-radius:var(--radius-sm,6px);background:rgba(234,179,8,0.12);border:1px solid " +
        color_warning +
        ";color:" +
        color_warning +
        ";font-size:0.875rem;" +
        font_ui,
      [
        @atoms.icon_atom(Warning, size="18", color=color_warning),
        span([text("kill switch が有効です。承認・執行系の操作は停止中です。")]),
      ],
    )
  } else {
    span(style="display:none;", [])
  }
  let runtime_button_label = if running { "運用停止" } else { "運用開始" }
  let runtime_variant : @atoms.ButtonVariant = if running {
    Danger
  } else {
    Primary
  }
  let controls = div(
    style="display:flex;align-items:center;gap:var(--space-md,16px);flex-wrap:wrap;",
    [
      span(
        attrs=[("data-action", @luna.attr_static("toggle-runtime"))],
        style="display:inline-flex;",
        [@atoms.button_atom(runtime_button_label, variant=runtime_variant, size=Medium)],
      ),
      span(
        attrs=[("data-action", @luna.attr_static("toggle-kill-switch"))],
        style="display:inline-flex;",
        [
          @atoms.toggle_atom(
            on=kill_switch_enabled,
            label="Kill Switch",
            aria_label="Kill Switch 切り替え",
          ),
        ],
      ),
    ],
  )
  @molecules.card([status_row, warning, controls], title~, extra_style~)
}

///|
/// A label above a status badge.
fn status_pair(
  label : String,
  badge : @luna.Node[Unit, String],
) -> @luna.Node[Unit, String] {
  div(
    style="display:flex;flex-direction:column;gap:6px;",
    [
      span(
        style="color:" +
          color_text_muted +
          ";font-size:0.75rem;font-weight:600;letter-spacing:0.04em;text-transform:uppercase;" +
          font_ui,
        [text(label)],
      ),
      badge,
    ],
  )
}
