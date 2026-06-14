///| Icon atom.
///|
///| SVG icon primitive (no emoji — design-system anti-pattern). A small named
///| icon set covers the common UI needs (check / close / warning / arrow-right /
///| info). Icons are `role="img"` with an `aria-label` when meaningful, or
///| `aria-hidden` when purely decorative.
///|
///| Ref: design-system/alpha-mind/MASTER.md (no emoji as icons; SVG icons)

///|
/// Named icon from the built-in set.
pub(all) enum IconName {
  Check
  Close
  Warning
  ArrowRight
  Info
}

///|
/// Render an icon atom.
///
/// - `name`: which icon to render.
/// - `size`: pixel size (default "20").
/// - `color`: stroke colour (default current text colour).
/// - `label`: accessible label. Empty → icon is decorative (`aria-hidden`).
/// - `extra_style`: caller-appended inline style (escape hatch).
pub fn icon_atom(
  name : IconName,
  size~ : String = "20",
  color~ : String = color_text,
  label~ : String = "",
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let path_d = match name {
    Check => "M5 12l5 5L20 7"
    Close => "M6 6l12 12M18 6L6 18"
    Warning => "M12 3l9 16H3z M12 10v4 M12 17v0.5"
    ArrowRight => "M5 12h14 M13 6l6 6-6 6"
    Info => "M12 8v0.5 M12 11v5"
  }
  let glyph = svg_path(
    d=path_d,
    fill="none",
    stroke=color,
    stroke_width="2",
    stroke_linecap="round",
    stroke_linejoin="round",
  )
  let style = "display:inline-block;vertical-align:middle;" + transition + extra_style
  if label == "" {
    svg(
      width=size,
      height=size,
      viewBox="0 0 24 24",
      style=style,
      attrs=[("aria-hidden", @luna.attr_static("true"))],
      [glyph],
    )
  } else {
    svg(
      width=size,
      height=size,
      viewBox="0 0 24 24",
      role="img",
      aria_label=label,
      style=style,
      [glyph],
    )
  }
}
