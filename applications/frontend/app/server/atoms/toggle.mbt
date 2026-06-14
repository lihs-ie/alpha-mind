///| Toggle / switch atom.
///|
///| SSR switch primitive. Renders an optional text label plus a track/thumb.
///| Server component (no event handler; an Island toggles state). Exposes
///| `role="switch"` + `aria-checked` for assistive tech, and conveys on/off via
///| the thumb position *and* an accessible label — not colour alone.
///|
///| Ref: design-system/alpha-mind/MASTER.md, 画面外部設計_共通.md §9 (a11y)

///|
/// Render a toggle atom.
///
/// - `on`: whether the switch is in the "on" position.
/// - `label`: visible text label rendered before the switch (empty → omitted).
/// - `disabled`: dims and disables, `cursor:not-allowed`.
/// - `aria_label`: accessible name for the switch when there is no visible label.
/// - `extra_style`: caller-appended inline style on the outer wrapper.
pub fn toggle_atom(
  on~ : Bool = false,
  label~ : String = "",
  disabled~ : Bool = false,
  aria_label~ : String = "切り替え",
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let track_bg = if on { color_cta } else { "rgba(248,250,252,0.2)" }
  let thumb_x = if on { "translateX(18px)" } else { "translateX(0)" }
  let cursor = if disabled {
    "cursor:not-allowed;opacity:0.5;"
  } else {
    "cursor:pointer;"
  }
  let thumb = span(
    style="position:absolute;top:2px;left:2px;width:16px;height:16px;border-radius:9999px;background:#fff;transform:" +
      thumb_x +
      ";" +
      transition,
    [],
  )
  let track = span(
    attrs=[
      ("role", @luna.attr_static("switch")),
      ("aria-checked", @luna.attr_static(if on { "true" } else { "false" })),
      ("aria-label", @luna.attr_static(aria_label)),
      ("tabindex", @luna.attr_static(if disabled { "-1" } else { "0" })),
      (
        "style",
        @luna.attr_static(
          "position:relative;display:inline-block;width:40px;height:20px;border-radius:9999px;background:" +
          track_bg +
          ";" +
          cursor +
          transition,
        ),
      ),
    ],
    [thumb],
  )
  let wrapper_style = "display:inline-flex;align-items:center;gap:8px;" +
    font_ui +
    extra_style
  if label == "" {
    span(style=wrapper_style, [track])
  } else {
    let label_node = span(
      style="color:" + color_text + ";font-size:0.875rem;",
      [text(label)],
    )
    span(style=wrapper_style, [label_node, track])
  }
}
