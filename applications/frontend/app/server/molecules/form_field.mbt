///| FormField molecule (Label + Input + Error / Help).

///|

///| Composes a `<label>`, an `@atoms.input_atom` and an optional inline error /

///| help message into one labelled field unit. Per the common-screen spec,

///| validation errors are shown below the field ("項目下の個別表示") and conveyed

///| by text — not colour alone (§7, §9 a11y). When an error is present the input

///| is marked `invalid` (red border + `aria-invalid`) and `aria-describedby`

///| links the input to the error text.

///|

///| Ref: documents/外部設計/screens/画面外部設計_共通.md §7 (validation), §9 (a11y)

///| Ref: design-system/alpha-mind/MASTER.md (Inputs)

///|
/// Render a labelled form field.
///
/// - `field_label`: visible label text rendered above the input.
/// - `field_id`: id of the input; the `<label for>` and `aria-describedby` use it.
/// - `name`: input `name` attribute (defaults to `field_id`).
/// - `input_type`: input type (`Text` / `Password` / `Number`).
/// - `placeholder` / `value`: optional input content.
/// - `required`: marks the input required and shows a required marker on the label.
/// - `disabled`: disables the input.
/// - `error`: error message (empty → no error; field is valid).
/// - `help`: help text shown below the input when there is no error.
/// - `extra_style`: caller-appended inline style on the outer wrapper.
pub fn form_field(
  field_label : String,
  field_id : String,
  name? : String = "",
  input_type? : @atoms.InputType = Text,
  placeholder? : String = "",
  value? : String = "",
  required? : Bool = false,
  disabled? : Bool = false,
  error? : String = "",
  help? : String = "",
  extra_style? : String = "",
) -> @luna.Node[Unit, String] {
  let has_error = error != ""
  let input_name = if name == "" { field_id } else { name }
  let describe_id = field_id + "-desc"
  let required_marker = if required {
    span(
      style="color:" + color_danger + ";margin-left:4px;",
      attrs=[("aria-hidden", @luna.attr_static("true"))],
      [text("*")],
    )
  } else {
    span(style="display:none;", [])
  }
  let label_node = label(
    for_=field_id,
    style="display:flex;align-items:center;color:" +
      color_text +
      ";font-size:0.875rem;font-weight:500;margin-bottom:6px;" +
      font_ui,
    [text(field_label), required_marker],
  )
  let input_node = @atoms.input_atom(
    input_type~,
    id=field_id,
    name=input_name,
    placeholder~,
    value~,
    disabled~,
    invalid=has_error,
    required~,
  )
  // The error / help message lives in a region with a stable id so it can be
  // referenced as an accessible description and announced via role="alert".
  let message_node = if has_error {
    span(
      id=describe_id,
      attrs=[("role", @luna.attr_static("alert"))],
      style="display:block;color:" +
        color_danger +
        ";font-size:0.8125rem;margin-top:6px;" +
        font_ui,
      [text(error)],
    )
  } else if help != "" {
    span(
      id=describe_id,
      style="display:block;color:" +
        color_text_muted +
        ";font-size:0.8125rem;margin-top:6px;" +
        font_ui,
      [text(help)],
    )
  } else {
    span(style="display:none;", [])
  }
  div(style="display:flex;flex-direction:column;" + extra_style, [
    label_node, input_node, message_node,
  ])
}
