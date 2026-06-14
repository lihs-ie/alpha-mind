///| Spinner / loading atom.
///|
///| SVG-based spinner (no emoji per design-system anti-pattern). Announces its
///| busy state to assistive tech via `role="status"` + `aria-label`. The spin
///| animation is expressed via an inline `<style>`-free CSS variable transform;
///| since inline styles cannot host `@keyframes`, the rotation is driven by a
///| CSS animation name (`alpha-spin`) that globals.css/loader provides, with a
///| static SVG arc as the progressive-enhancement fallback.
///|
///| Ref: design-system/alpha-mind/MASTER.md (no emoji as icons; visible state)

///|
/// Spinner size.
pub(all) enum SpinnerSize {
  Small
  Medium
  Large
}

///|
/// Render a spinner atom.
///
/// - `size`: pixel size of the spinner (default `Medium`).
/// - `label`: accessible label announced via `aria-label` (default "読み込み中").
/// - `color`: stroke colour (default CTA accent).
pub fn spinner_atom(
  size~ : SpinnerSize = Medium,
  label~ : String = "読み込み中",
  color~ : String = color_cta,
) -> @luna.Node[Unit, String] {
  let px = match size {
    Small => "16"
    Medium => "24"
    Large => "40"
  }
  // Inline spin animation: `animation` shorthand references `alpha-spin`
  // keyframes (defined in globals.css when present). transition kept for
  // the no-instant-state-change rule.
  let svg_style = "animation:alpha-spin 0.8s linear infinite;" + transition
  let arc = svg_circle(
    cx="12",
    cy="12",
    r="10",
    fill="none",
    stroke=color,
    stroke_width="3",
    attrs=[
      ("stroke-dasharray", @luna.attr_static("47")),
      ("stroke-dashoffset", @luna.attr_static("16")),
      ("stroke-linecap", @luna.attr_static("round")),
    ],
  )
  svg(
    width=px,
    height=px,
    viewBox="0 0 24 24",
    role="status",
    aria_label=label,
    style=svg_style,
    [arc],
  )
}
