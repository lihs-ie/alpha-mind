///| Pagination molecule (cursor-based).

///|

///| Cursor-based pagination control: previous / next buttons plus an optional

///| range summary (e.g. "1–20 件"). Matches the BFF list contract which returns

///| `nextCursor` / `prevCursor` rather than page numbers. Composes

///| `@atoms.button_atom` for the controls. Server component: the actual cursor

///| navigation is wired by a client Island via the rendered `data-*` cursors.

///|

///| Ref: documents/外部設計/api/openapi.yaml (cursor pagination)

///| Ref: design-system/alpha-mind/MASTER.md

///|
/// Render a cursor-based pagination control.
///
/// - `summary`: optional range / count summary shown between the buttons.
/// - `has_prev`: whether a previous page exists (disables the prev button if not).
/// - `has_next`: whether a next page exists (disables the next button if not).
/// - `prev_cursor`: opaque previous cursor, surfaced as `data-prev-cursor`.
/// - `next_cursor`: opaque next cursor, surfaced as `data-next-cursor`.
/// - `extra_style`: caller-appended inline style on the nav wrapper.
pub fn pagination(
  summary? : String = "",
  has_prev? : Bool = false,
  has_next? : Bool = false,
  prev_cursor? : String = "",
  next_cursor? : String = "",
  extra_style? : String = "",
) -> @luna.Node[Unit, String] {
  let prev_button = button_with_cursor(
    "前へ",
    enabled=has_prev,
    cursor_attr="data-prev-cursor",
    cursor=prev_cursor,
  )
  let next_button = button_with_cursor(
    "次へ",
    enabled=has_next,
    cursor_attr="data-next-cursor",
    cursor=next_cursor,
  )
  let summary_node = if summary != "" {
    span(
      style="color:" + color_text_muted + ";font-size:0.8125rem;" + font_ui,
      [text(summary)],
    )
  } else {
    span(style="display:none;", [])
  }
  nav(
    attrs=[("aria-label", @luna.attr_static("ページ送り"))],
    style="display:flex;align-items:center;justify-content:space-between;gap:var(--space-md,16px);" +
      extra_style,
    [prev_button, summary_node, next_button],
  )
}

///|
/// Wrap an atom button in a span carrying the opaque cursor as a data attribute,
/// so a client Island can read it to perform the actual navigation.
fn button_with_cursor(
  label_text : String,
  enabled~ : Bool,
  cursor_attr~ : String,
  cursor~ : String,
) -> @luna.Node[Unit, String] {
  let button_node = @atoms.button_atom(
    label_text,
    variant=Secondary,
    size=Small,
    disabled=!enabled,
  )
  span(
    attrs=[(cursor_attr, @luna.attr_static(cursor))],
    style="display:inline-flex;",
    [button_node],
  )
}
