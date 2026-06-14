///| FormSection organism (titled form with fields + submit).
///|
///| A complete form section built from `@molecules.form_field`s plus a submit /
///| cancel action row, wrapped in a `@molecules.card` surface with an optional
///| section title and a top error-summary region. Per the common-screen
///| validation policy (§7) errors are shown both as a summary at the top and
///| inline under each field; the summary here is a `role="alert"` region and each
///| field carries its own inline error. Used by the login form (SCR-000) and the
///| strategy settings form (SCR-002). Server component: submission is handled by a
///| Server Action / client Island; this organism renders the accessible structure.
///|
///| Ref: documents/外部設計/screens/画面外部設計_共通.md §7 (バリデーション: 要約 + 項目下),
///|      documents/外部設計/screens/SCR-000_認証.md, SCR-002_戦略設定.md

///|
/// A field specification for a FormSection.
pub(all) struct FormFieldSpec {
  /// Visible label.
  label : String
  /// Input id (also the default `name`).
  field_id : String
  /// Input type.
  input_type : @atoms.InputType
  /// Placeholder text.
  placeholder : String
  /// Initial value.
  value : String
  /// Whether the field is required.
  required : Bool
  /// Inline error message (empty → valid).
  error : String
  /// Help text shown when there is no error.
  help : String
}

///|
/// Build a default field spec, overriding only what is needed.
pub fn form_field_spec(
  label : String,
  field_id : String,
  input_type~ : @atoms.InputType = Text,
  placeholder~ : String = "",
  value~ : String = "",
  required~ : Bool = false,
  error~ : String = "",
  help~ : String = "",
) -> FormFieldSpec {
  {
    label,
    field_id,
    input_type,
    placeholder,
    value,
    required,
    error,
    help,
  }
}

///|
/// Render a titled form section with fields and a submit action.
///
/// - `fields`: the field specifications, in order.
/// - `submit_label`: the primary submit button label (default "保存").
/// - `title`: optional section title (empty → no header).
/// - `error_summary`: top-of-form error summary (empty → no summary region).
/// - `cancel_label`: optional secondary cancel button (empty → no cancel button).
/// - `submitting`: marks the submit button busy (spinner + aria-busy).
/// - `extra_style`: caller-appended inline style on the card surface.
pub fn form_section(
  fields : Array[FormFieldSpec],
  submit_label~ : String = "保存",
  title~ : String = "",
  error_summary~ : String = "",
  cancel_label~ : String = "",
  submitting~ : Bool = false,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let body : Array[@luna.Node[Unit, String]] = []
  if error_summary != "" {
    body.push(
      div(
        attrs=[("role", @luna.attr_static("alert"))],
        style="padding:12px 16px;border-radius:var(--radius-sm,6px);background:rgba(248,113,113,0.12);border:1px solid " +
          color_danger +
          ";color:" +
          color_danger +
          ";font-size:0.875rem;" +
          font_ui,
        [text(error_summary)],
      ),
    )
  }
  for spec in fields {
    body.push(
      @molecules.form_field(
        spec.label,
        spec.field_id,
        input_type=spec.input_type,
        placeholder=spec.placeholder,
        value=spec.value,
        required=spec.required,
        error=spec.error,
        help=spec.help,
      ),
    )
  }
  let actions : Array[@luna.Node[Unit, String]] = []
  if cancel_label != "" {
    actions.push(
      @atoms.button_atom(cancel_label, variant=Secondary, size=Medium),
    )
  }
  actions.push(
    @atoms.button_atom(
      submit_label,
      variant=Primary,
      size=Medium,
      button_type="submit",
      loading=submitting,
    ),
  )
  @molecules.card(
    body,
    title~,
    footer=[
      div(
        style="display:flex;justify-content:flex-end;gap:8px;width:100%;",
        actions,
      ),
    ],
    extra_style~,
  )
}
