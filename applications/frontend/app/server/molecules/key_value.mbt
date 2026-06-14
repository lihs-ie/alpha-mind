///| KeyValue / DataRow molecules.

///|

///| `key_value` renders a single label→value pair (definition-style row) used in

///| detail panels. `key_value_list` renders many of them as a stacked, separated

///| list. Values can be rendered in the monospace numeric face for identifiers /

///| numbers. These compose the `@atoms` typography styling language.

///|

///| Ref: design-system/alpha-mind/MASTER.md (Typography)

///| Ref: documents/外部設計/screens/SCR-003_注文管理.md, SCR-004_監査ログ.md

///|
/// Render a single key→value row.
///
/// - `key_text`: the label (muted, left).
/// - `value`: the value text (right / below).
/// - `mono`: render the value in the monospace numeric face (identifiers/numbers).
/// - `extra_style`: caller-appended inline style on the row.
pub fn key_value(
  key_text : String,
  value : String,
  mono? : Bool = false,
  extra_style? : String = "",
) -> @luna.Node[Unit, String] {
  let value_font = if mono { font_mono } else { font_ui }
  div(
    style="display:flex;align-items:baseline;justify-content:space-between;gap:var(--space-md,16px);padding:8px 0;" +
      extra_style,
    [
      span(
        style="color:" +
          color_text_muted +
          ";font-size:0.8125rem;flex:0 0 auto;" +
          font_ui,
        [text(key_text)],
      ),
      span(
        style="color:" +
          color_text +
          ";font-size:0.875rem;font-weight:500;text-align:right;word-break:break-all;" +
          value_font,
        [text(value)],
      ),
    ],
  )
}

///|
/// Render a stacked list of key→value rows with separators.
///
/// - `rows`: array of `(key, value)` pairs.
/// - `mono`: render every value in the monospace face.
/// - `extra_style`: caller-appended inline style on the list wrapper.
pub fn key_value_list(
  rows : Array[(String, String)],
  mono? : Bool = false,
  extra_style? : String = "",
) -> @luna.Node[Unit, String] {
  let children = rows.mapi(fn(index, pair) {
    let (key_text, value) = pair
    let separator = if index == 0 {
      ""
    } else {
      "border-top:1px solid " + color_border + ";"
    }
    key_value(key_text, value, mono~, extra_style=separator)
  })
  div(
    attrs=[("role", @luna.attr_static("list"))],
    style="display:flex;flex-direction:column;" + extra_style,
    children,
  )
}
