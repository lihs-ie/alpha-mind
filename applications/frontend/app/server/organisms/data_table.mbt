///| DataTable organism (generic columnar list section).
///|
///| A reusable, accessible tabular section for list screens. Because the static
///| element DSL does not expose `<table>` elements, the table is built from
///| `div`s carrying the ARIA grid roles (`role="table"` / `"row"` /
///| `"columnheader"` / `"cell"`) — the same div-based list pattern the molecule
///| layer already uses (`@molecules.key_value_list`). It renders a header row of
///| column titles, the data rows, an accessible `empty`-state message when there
///| are no rows, and an optional pagination footer composed from
///| `@molecules.pagination`. Cells are plain text; richer cells (badges, buttons)
///| are provided by the specialised tables (OrderTable / AuditLogTable). Server
///| component: sorting / cursor navigation are wired by a client Island via the
///| rendered `data-*` attributes.
///|
///| Ref: documents/外部設計/screens/SCR-003_注文管理.md, SCR-004_監査ログ.md,
///|      documents/外部設計/api/openapi.yaml (cursor pagination),
///|      design-system/alpha-mind/MASTER.md

///|
/// A column definition for the DataTable.
pub(all) struct TableColumn {
  /// Visible column header label.
  label : String
  /// `grid-template-columns` track for this column (e.g. "1fr" / "120px").
  width : String
  /// Render numeric cells in this column in the monospace face.
  mono : Bool
}

///|
/// Cursor-based pagination state for a DataTable footer.
pub(all) struct TablePagination {
  /// Range / count summary (e.g. "1–20 件").
  summary : String
  /// Whether a previous page exists.
  has_prev : Bool
  /// Whether a next page exists.
  has_next : Bool
  /// Opaque previous cursor.
  prev_cursor : String
  /// Opaque next cursor.
  next_cursor : String
}

///|
/// Render a generic data table.
///
/// - `columns`: the column definitions (order = visual order).
/// - `rows`: each row is an array of cell strings; cells past the column count
///   are ignored, missing trailing cells render empty.
/// - `caption`: accessible table caption (`aria-label`); empty → "データ一覧".
/// - `empty_message`: text shown when `rows` is empty (default per common spec).
/// - `pagination`: optional cursor pagination footer (`None` → no footer).
/// - `extra_style`: caller-appended inline style on the table wrapper.
pub fn data_table(
  columns : Array[TableColumn],
  rows : Array[Array[String]],
  caption~ : String = "データ一覧",
  empty_message~ : String = "該当するデータがありません。",
  pagination~ : TablePagination? = None,
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let grid_template = grid_template_columns(columns)
  let header_row = table_header_row(columns, grid_template)
  let body : @luna.Node[Unit, String] = if rows.length() == 0 {
    div(
      attrs=[("role", @luna.attr_static("status"))],
      style="padding:var(--space-2xl,48px) var(--space-lg,24px);text-align:center;color:" +
        color_text_muted +
        ";font-size:0.875rem;" +
        font_ui,
      [text(empty_message)],
    )
  } else {
    let body_rows = rows.map(fn(cells) {
      table_body_row(columns, cells, grid_template)
    })
    div([..body_rows])
  }
  let children : Array[@luna.Node[Unit, String]] = [
    div(
      attrs=[
        ("role", @luna.attr_static("table")),
        ("aria-label", @luna.attr_static(caption)),
      ],
      style=surface_bg +
        radius_md +
        shadow_md +
        "border:1px solid " +
        color_border +
        ";overflow:hidden;box-sizing:border-box;width:100%;" +
        transition,
      [header_row, body],
    ),
  ]
  match pagination {
    Some(paging) =>
      children.push(
        @molecules.pagination(
          summary=paging.summary,
          has_prev=paging.has_prev,
          has_next=paging.has_next,
          prev_cursor=paging.prev_cursor,
          next_cursor=paging.next_cursor,
          extra_style="margin-top:var(--space-md,16px);",
        ),
      )
    None => ()
  }
  div(style="display:flex;flex-direction:column;" + extra_style, children)
}

///|
/// Build the `grid-template-columns` value from the column widths.
fn grid_template_columns(columns : Array[TableColumn]) -> String {
  let tracks = columns.map(fn(column) { column.width })
  "grid-template-columns:" + tracks.join(" ") + ";"
}

///|
/// Render the column-header row.
fn table_header_row(
  columns : Array[TableColumn],
  grid_template : String,
) -> @luna.Node[Unit, String] {
  let cells = columns.map(fn(column) {
    div(
      attrs=[("role", @luna.attr_static("columnheader"))],
      style="color:" +
        color_text_muted +
        ";font-size:0.6875rem;font-weight:600;letter-spacing:0.04em;text-transform:uppercase;padding:12px 16px;" +
        font_ui,
      [text(column.label)],
    )
  })
  div(
    attrs=[("role", @luna.attr_static("row"))],
    style="display:grid;align-items:center;" +
      grid_template +
      "border-bottom:1px solid " +
      color_border +
      ";background:rgba(248,250,252,0.03);",
    cells,
  )
}

///|
/// Render a single data row.
fn table_body_row(
  columns : Array[TableColumn],
  cells : Array[String],
  grid_template : String,
) -> @luna.Node[Unit, String] {
  let cell_nodes = columns.mapi(fn(index, column) {
    let value = if index < cells.length() { cells[index] } else { "" }
    let value_font = if column.mono { font_mono } else { font_ui }
    div(
      attrs=[("role", @luna.attr_static("cell"))],
      style="color:" +
        color_text +
        ";font-size:0.875rem;padding:12px 16px;word-break:break-all;" +
        value_font,
      [text(value)],
    )
  })
  div(
    attrs=[("role", @luna.attr_static("row"))],
    style="display:grid;align-items:center;" +
      grid_template +
      "border-bottom:1px solid " +
      color_border +
      ";" +
      transition,
    cell_nodes,
  )
}
