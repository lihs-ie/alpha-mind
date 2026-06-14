///| FilterBar molecule (status / datetime list filters).

///|

///| A surface bar holding list filter controls — status chips and a date-range

///| input pair plus an apply button. Used above list tables (orders, audit log).

///| Composes `@atoms.status_badge_atom` for the status chips, `@atoms.input_atom`

///| for the date inputs and `@atoms.button_atom` for apply. Server component:

///| filter submission is wired by a client Island.

///|

///| Ref: documents/外部設計/screens/SCR-003_注文管理.md, SCR-004_監査ログ.md

///| Ref: documents/外部設計/screens/画面外部設計_共通.md §10 (一覧フィルタ操作)

///|
/// A single status filter chip option.
pub(all) struct StatusFilterOption {
  /// Domain status string (e.g. "PROPOSED"); rendered via the status badge atom.
  status : String
  /// Whether this chip is currently selected.
  selected : Bool
}

///|
/// Render a list filter bar.
///
/// - `field_id_prefix`: prefix for the input ids (e.g. "orders" → "orders-from").
/// - `status_options`: status chips to render (empty → no status row).
/// - `show_date_range`: render a from/to date input pair when true.
/// - `from_value` / `to_value`: optional initial date values.
/// - `extra_style`: caller-appended inline style on the bar.
pub fn filter_bar(
  field_id_prefix : String,
  status_options? : Array[StatusFilterOption] = [],
  show_date_range? : Bool = false,
  from_value? : String = "",
  to_value? : String = "",
  extra_style? : String = "",
) -> @luna.Node[Unit, String] {
  let rows : Array[@luna.Node[Unit, String]] = []
  if status_options.length() > 0 {
    let chips = status_options.map(fn(option) { status_chip(option) })
    rows.push(filter_group("状態", chips))
  }
  if show_date_range {
    let from_field = labelled_input(
      field_id_prefix + "-from",
      "開始日時",
      from_value,
    )
    let to_field = labelled_input(
      field_id_prefix + "-to",
      "終了日時",
      to_value,
    )
    rows.push(
      filter_group("期間", [
        from_field,
        span(
          style="color:" +
            color_text_muted +
            ";align-self:flex-end;padding-bottom:8px;",
          [text("〜")],
        ),
        to_field,
      ]),
    )
  }
  rows.push(
    div(style="display:flex;align-items:flex-end;", [
      @atoms.button_atom("フィルタ適用", variant=Secondary, size=Small),
    ]),
  )
  div(
    attrs=[
      ("role", @luna.attr_static("search")),
      ("aria-label", @luna.attr_static("一覧フィルタ")),
    ],
    style=surface_bg +
      radius_sm +
      "border:1px solid " +
      color_border +
      ";padding:var(--space-md,16px) var(--space-lg,24px);display:flex;flex-wrap:wrap;align-items:flex-end;gap:var(--space-lg,24px);box-sizing:border-box;" +
      extra_style,
    rows,
  )
}

///|
/// A labelled group (label above a row of controls).
fn filter_group(
  group_label : String,
  controls : Array[@luna.Node[Unit, String]],
) -> @luna.Node[Unit, String] {
  div(style="display:flex;flex-direction:column;gap:8px;", [
    span(
      style="color:" +
        color_text_muted +
        ";font-size:0.75rem;font-weight:600;letter-spacing:0.04em;text-transform:uppercase;" +
        font_ui,
      [text(group_label)],
    ),
    div(
      style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;",
      controls,
    ),
  ])
}

///|
/// A status chip: a status badge tinted by selection state.
fn status_chip(option : StatusFilterOption) -> @luna.Node[Unit, String] {
  let selected_style = if option.selected {
    "outline:2px solid " + color_cta + ";outline-offset:1px;"
  } else {
    "opacity:0.65;"
  }
  span(
    attrs=[
      ("role", @luna.attr_static("checkbox")),
      (
        "aria-checked",
        @luna.attr_static(if option.selected { "true" } else { "false" }),
      ),
      ("tabindex", @luna.attr_static("0")),
      ("data-status", @luna.attr_static(option.status)),
    ],
    style="display:inline-flex;cursor:pointer;border-radius:9999px;" +
      transition,
    [@atoms.status_badge_atom(option.status, extra_style=selected_style)],
  )
}

///|
/// A labelled date input field used inside a filter group.
fn labelled_input(
  input_id : String,
  field_label : String,
  value : String,
) -> @luna.Node[Unit, String] {
  let value_opt = if value == "" { None } else { Some(value) }
  div(style="display:flex;flex-direction:column;gap:4px;", [
    label(
      for_=input_id,
      style="color:" + color_text_muted + ";font-size:0.6875rem;" + font_ui,
      [text(field_label)],
    ),
    @atoms.input_atom(
      input_type=Text,
      id=input_id,
      name=input_id,
      value=match value_opt {
        Some(value) => value
        None => ""
      },
      placeholder="YYYY-MM-DD",
    ),
  ])
}
