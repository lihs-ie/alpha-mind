///| Typography atoms.
///|
///| `heading_atom` renders an `<h1>/<h2>/<h3>` with the design-system heading
///| scale. `body_text_atom` renders body copy. `mono_text_atom` renders numeric
///| / code text in the monospace face (CLAUDE.md: 数値=JetBrains Mono).
///|
///| Ref: design-system/alpha-mind/MASTER.md (Typography), CLAUDE.md (fonts)

///|
/// Heading level.
pub(all) enum HeadingLevel {
  H1
  H2
  H3
}

///|
/// Render a heading atom.
///
/// - `level`: semantic + visual heading level (default `H1`).
/// - `extra_style`: caller-appended inline style (escape hatch).
pub fn heading_atom(
  text_content : String,
  level~ : HeadingLevel = H1,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let size_style = match level {
    H1 => "font-size:1.5rem;font-weight:700;"
    H2 => "font-size:1rem;font-weight:600;letter-spacing:0.05em;text-transform:uppercase;"
    H3 => "font-size:0.9375rem;font-weight:600;"
  }
  let style = "color:" + color_text + ";margin:0;" + font_ui + size_style + extra_style
  match level {
    H1 => h1(style=style, [text(text_content)])
    H2 => h2(style=style, [text(text_content)])
    H3 => h3(style=style, [text(text_content)])
  }
}

///|
/// Render body text.
///
/// - `muted`: renders in the secondary/muted colour.
/// - `extra_style`: caller-appended inline style (escape hatch).
pub fn body_text_atom(
  text_content : String,
  muted~ : Bool = false,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let color = if muted { color_text_muted } else { color_text }
  let style = "color:" +
    color +
    ";font-size:0.875rem;margin:0;line-height:1.5;" +
    font_ui +
    extra_style
  p(style=style, [text(text_content)])
}

///|
/// Render monospace text (numeric / code display).
///
/// - `extra_style`: caller-appended inline style (escape hatch).
pub fn mono_text_atom(
  text_content : String,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let style = "color:" +
    color_text +
    ";font-size:0.875rem;" +
    font_mono +
    extra_style
  span(style=style, [text(text_content)])
}
