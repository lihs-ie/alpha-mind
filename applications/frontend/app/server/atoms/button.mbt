///| Button atom.
///|
///| A reusable SSR button primitive with variant / size / state props.
///| Server component: no event handlers (Islands attach behaviour). Styling is
///| inline, backed by design-system CSS variables. No Tailwind.
///|
///| Ref: design-system/alpha-mind/MASTER.md (Buttons), Issue #83 (Button Primary/Secondary)

///|
/// Visual variant of a button.
pub(all) enum ButtonVariant {
  /// CTA / accent filled button (primary action).
  Primary
  /// Outlined neutral button.
  Secondary
  /// Destructive action (delete / reject).
  Danger
  /// Minimal, borderless button.
  Ghost
}

///|
/// Button size.
pub(all) enum ButtonSize {
  Small
  Medium
  Large
}

///|
/// Render a button atom.
///
/// - `variant`: visual role (default `Primary`).
/// - `size`: spacing/typography scale (default `Medium`).
/// - `button_type`: HTML `type` attribute (`"button"` / `"submit"` / `"reset"`).
/// - `disabled`: disables and dims the button, sets `cursor:not-allowed`.
/// - `loading`: shows a spinner before the label and marks `aria-busy`.
/// - `full_width`: stretches to the container width.
/// - `extra_style`: caller-appended inline style (escape hatch).
pub fn button_atom(
  label_text : String,
  variant~ : ButtonVariant = Primary,
  size~ : ButtonSize = Medium,
  button_type~ : String = "button",
  disabled~ : Bool = false,
  loading~ : Bool = false,
  full_width~ : Bool = false,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let size_style = match size {
    Small => "padding:6px 12px;font-size:0.8125rem;"
    Medium => "padding:12px 24px;font-size:1rem;"
    Large => "padding:14px 28px;font-size:1.125rem;"
  }
  let variant_style = match variant {
    Primary => "background:" + color_cta + ";color:#fff;border:1px solid transparent;"
    Secondary =>
      "background:transparent;color:" +
      color_text +
      ";border:1px solid " +
      color_border +
      ";"
    Danger =>
      "background:" + color_danger + ";color:#0F172A;border:1px solid transparent;"
    Ghost =>
      "background:transparent;color:" +
      color_text +
      ";border:1px solid transparent;"
  }
  let cursor = if disabled {
    "cursor:not-allowed;opacity:0.5;"
  } else {
    "cursor:pointer;"
  }
  let width = if full_width { "width:100%;" } else { "" }
  let base = "border-radius:6px;font-weight:600;display:inline-flex;align-items:center;justify-content:center;gap:8px;line-height:1.2;" +
    font_ui +
    transition
  let style = base + size_style + variant_style + cursor + width + extra_style
  let mut children : Array[@luna.Node[Unit, String]] = []
  if loading {
    children = [spinner_atom(size=SpinnerSize::Small, label="読み込み中"), text(label_text)]
  } else {
    children = [text(label_text)]
  }
  let attrs : Array[(String, @luna.Attr[Unit, String])] = [
    ("type", @luna.attr_static(button_type)),
    ("aria-busy", @luna.attr_static(if loading { "true" } else { "false" })),
    ("style", @luna.attr_static(style)),
  ]
  button(disabled~, attrs~, children)
}
