///| Badge and StatusBadge atoms.
///|
///| `badge_atom` renders a small pill-shaped label in a semantic colour.
///| `status_badge_atom` maps a domain status string (order / model / runtime /
///| kill-switch) to a badge variant + human label. Status is always conveyed by
///| text (not colour alone) per accessibility requirement §9.
///|
///| Ref: documents/外部設計/state/状態遷移設計.md (status enums),
///|      documents/外部設計/screens/画面外部設計_共通.md §9 (a11y)

///|
/// Semantic badge variant.
pub(all) enum BadgeVariant {
  Neutral
  Success
  Warning
  Danger
  Info
}

///|
/// Render a badge atom (pill label).
///
/// - `variant`: semantic colour (default `Neutral`).
/// - `extra_style`: caller-appended inline style (escape hatch).
pub fn badge_atom(
  label_text : String,
  variant~ : BadgeVariant = Neutral,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let (fg, bg, border) = match variant {
    Neutral =>
      (color_text_muted, "rgba(248,250,252,0.08)", "rgba(248,250,252,0.15)")
    Success => (color_cta, "rgba(34,197,94,0.12)", "rgba(34,197,94,0.35)")
    Warning => (color_warning, "rgba(234,179,8,0.12)", "rgba(234,179,8,0.35)")
    Danger => (color_danger, "rgba(248,113,113,0.12)", "rgba(248,113,113,0.35)")
    Info => (color_info, "rgba(99,102,241,0.15)", "rgba(99,102,241,0.3)")
  }
  let style = "display:inline-flex;align-items:center;gap:4px;padding:2px 10px;border-radius:9999px;font-size:0.75rem;font-weight:600;letter-spacing:0.02em;color:" +
    fg +
    ";background:" +
    bg +
    ";border:1px solid " +
    border +
    ";" +
    font_ui +
    transition +
    extra_style
  span(style=style, [text(label_text)])
}

///|
/// Render a status badge for a domain status string.
///
/// Recognises order statuses (PROPOSED/APPROVED/EXECUTED/REJECTED/FAILED),
/// model statuses (candidate/approved/rejected), runtime (RUNNING/STOPPED) and
/// kill switch (ENABLED/DISABLED). Unknown statuses render Neutral with the raw
/// label so nothing is silently dropped.
pub fn status_badge_atom(
  status : String,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let (variant, display) = status_badge_meta(status)
  badge_atom(display, variant~, extra_style~)
}

///|
/// Map a status string to its badge variant and display label.
/// Pure helper, separated so unit tests can assert the mapping directly.
pub fn status_badge_meta(status : String) -> (BadgeVariant, String) {
  match status {
    // Order lifecycle
    "PROPOSED" => (Info, "提案中")
    "APPROVED" => (Success, "承認済み")
    "EXECUTED" => (Success, "執行済み")
    "REJECTED" => (Danger, "却下")
    "FAILED" => (Danger, "失敗")
    // Model lifecycle (lowercase per spec)
    "candidate" => (Info, "候補")
    "approved" => (Success, "承認")
    "rejected" => (Danger, "却下")
    // Runtime
    "RUNNING" => (Success, "稼働中")
    "STOPPED" => (Neutral, "停止中")
    // Kill switch
    "ENABLED" => (Warning, "有効")
    "DISABLED" => (Neutral, "無効")
    other => (Neutral, other)
  }
}
