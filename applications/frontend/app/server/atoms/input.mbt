///| Text input atom.
///|
///| Reusable SSR `<input>` primitive. Server component (no event handlers; an
///| Island attaches `oninput` when interactive behaviour is needed). Styling is
///| inline, backed by design-system CSS variables. No Tailwind.
///|
///| Ref: design-system/alpha-mind/MASTER.md (Inputs), Issue #83 (Text/Password/Number)

///|
/// Input type.
pub(all) enum InputType {
  Text
  Password
  Number
}

///|
/// Render a text input atom.
///
/// - `input_type`: HTML input type (`Text` / `Password` / `Number`).
/// - `id` / `name`: element identifiers (default empty → omitted).
/// - `placeholder` / `value`: optional initial content.
/// - `disabled`: dims and disables, `cursor:not-allowed`.
/// - `invalid`: applies the error border colour and sets `aria-invalid`.
/// - `required`: sets the `required` attribute.
/// - `extra_style`: caller-appended inline style (escape hatch).
pub fn input_atom(
  input_type~ : InputType = Text,
  id~ : String = "",
  name~ : String = "",
  placeholder~ : String = "",
  value~ : String = "",
  disabled~ : Bool = false,
  invalid~ : Bool = false,
  required~ : Bool = false,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let type_str = match input_type {
    Text => "text"
    Password => "password"
    Number => "number"
  }
  let border_color = if invalid { color_danger } else { color_border }
  let cursor = if disabled {
    "cursor:not-allowed;opacity:0.6;"
  } else {
    ""
  }
  let style = "background:var(--color-primary,#0F172A);color:" +
    color_text +
    ";border:1px solid " +
    border_color +
    ";border-radius:6px;padding:8px 16px;font-size:1rem;width:100%;box-sizing:border-box;" +
    font_ui +
    transition +
    cursor +
    extra_style
  let attrs : Array[(String, @luna.Attr[Unit, String])] = [
    ("aria-invalid", @luna.attr_static(if invalid { "true" } else { "false" })),
    ("style", @luna.attr_static(style)),
  ]
  let id_opt = if id == "" { None } else { Some(id) }
  let name_opt = if name == "" { None } else { Some(name) }
  let placeholder_opt = if placeholder == "" { None } else { Some(placeholder) }
  let value_opt = if value == "" { None } else { Some(value) }
  input(
    type_=type_str,
    id?=id_opt,
    name?=name_opt,
    placeholder?=placeholder_opt,
    value?=value_opt,
    disabled~,
    required~,
    attrs~,
  )
}
