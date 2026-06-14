///| OrderTable organism (order-candidate list section).
///|
///| The SCR-003 order-management list: a div-based ARIA table (the static DSL has
///| no `<table>`) whose status column renders `@atoms.status_badge_atom` and whose
///| action column renders the state-appropriate `@atoms.button_atom`s. The action
///| set follows the order state machine: `PROPOSED` → 承認 / 却下, `APPROVED` →
///| 執行待ち (no action), `FAILED` → 再送, terminal states → none. When the kill
///| switch is enabled, approval is disabled (CLAUDE.md: kill switch 有効時は承認/
///| 執行系を停止). Identifiers / quantities use the monospace numeric face.
///| Server component: the actions are wired by the OrdersActions client Island via
///| the rendered `data-order-id` / `data-action` attributes.
///|
///| Ref: documents/外部設計/screens/SCR-003_注文管理.md,
///|      documents/外部設計/state/状態遷移設計.md (Orders 状態遷移),
///|      CLAUDE.md (kill switch)

///|
/// A single order row for the OrderTable.
pub(all) struct OrderRow {
  /// Order identifier (ULID); shown in the monospace face.
  identifier : String
  /// Stock symbol / code.
  symbol : String
  /// Side ("BUY" / "SELL").
  side : String
  /// Quantity.
  qty : String
  /// Domain status (PROPOSED/APPROVED/EXECUTED/REJECTED/FAILED).
  status : String
  /// Creation timestamp (ISO8601).
  created_at : String
}

///|
/// Render the order-candidate table.
///
/// - `orders`: the order rows.
/// - `kill_switch_enabled`: disables approval actions when true.
/// - `empty_message`: text shown when there are no orders.
/// - `extra_style`: caller-appended inline style on the table wrapper.
pub fn order_table(
  orders : Array[OrderRow],
  kill_switch_enabled~ : Bool = false,
  empty_message~ : String = "該当する注文がありません。",
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let grid_template = "grid-template-columns:1.6fr 1fr 0.8fr 0.8fr 1fr 1.4fr;"
  let header = order_header_row(grid_template)
  let body : @luna.Node[Unit, String] = if orders.length() == 0 {
    div(
      attrs=[("role", @luna.attr_static("status"))],
      style="padding:var(--space-2xl,48px) var(--space-lg,24px);text-align:center;color:" +
        color_text_muted +
        ";font-size:0.875rem;" +
        font_ui,
      [text(empty_message)],
    )
  } else {
    let rows = orders.map(fn(order) {
      order_body_row(order, kill_switch_enabled, grid_template)
    })
    div([..rows])
  }
  div(
    attrs=[
      ("role", @luna.attr_static("table")),
      ("aria-label", @luna.attr_static("注文候補一覧")),
    ],
    style=surface_bg +
      radius_md +
      shadow_md +
      "border:1px solid " +
      color_border +
      ";overflow:hidden;box-sizing:border-box;width:100%;" +
      transition +
      extra_style,
    [header, body],
  )
}

///|
/// Header row labels for the order table.
fn order_header_row(grid_template : String) -> @luna.Node[Unit, String] {
  let labels = ["注文ID", "銘柄", "売買", "数量", "状態", "操作"]
  let cells = labels.map(fn(label) {
    div(
      attrs=[("role", @luna.attr_static("columnheader"))],
      style="color:" +
        color_text_muted +
        ";font-size:0.6875rem;font-weight:600;letter-spacing:0.04em;text-transform:uppercase;padding:12px 16px;" +
        font_ui,
      [text(label)],
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
/// One order row: id / symbol / side / qty / status badge / actions.
fn order_body_row(
  order : OrderRow,
  kill_switch_enabled : Bool,
  grid_template : String,
) -> @luna.Node[Unit, String] {
  let id_cell = text_cell(order.identifier, mono=true)
  let symbol_cell = text_cell(order.symbol, mono=false)
  let side_cell = text_cell(order.side, mono=false)
  let qty_cell = text_cell(order.qty, mono=true)
  let status_cell = div(
    attrs=[("role", @luna.attr_static("cell"))],
    style="padding:12px 16px;",
    [@atoms.status_badge_atom(order.status)],
  )
  let actions_cell = div(
    attrs=[
      ("role", @luna.attr_static("cell")),
      ("data-order-id", @luna.attr_static(order.identifier)),
    ],
    style="padding:12px 16px;display:flex;align-items:center;gap:8px;flex-wrap:wrap;",
    order_actions(order.status, kill_switch_enabled),
  )
  div(
    attrs=[
      ("role", @luna.attr_static("row")),
      ("data-order-id", @luna.attr_static(order.identifier)),
    ],
    style="display:grid;align-items:center;" +
      grid_template +
      "border-bottom:1px solid " +
      color_border +
      ";" +
      transition,
    [id_cell, symbol_cell, side_cell, qty_cell, status_cell, actions_cell],
  )
}

///|
/// State-appropriate action buttons for an order row.
/// PROPOSED → 承認 (disabled by kill switch) / 却下; FAILED → 再送;
/// other states → none.
fn order_actions(
  status : String,
  kill_switch_enabled : Bool,
) -> Array[@luna.Node[Unit, String]] {
  match status {
    "PROPOSED" => [
      action_button("承認", "approve", variant=Primary, disabled=kill_switch_enabled),
      action_button("却下", "reject", variant=Danger, disabled=false),
    ]
    "FAILED" => [
      action_button("再送", "retry", variant=Secondary, disabled=kill_switch_enabled),
    ]
    _ => [
      span(
        style="color:" + color_text_muted + ";font-size:0.8125rem;" + font_ui,
        [text("—")],
      ),
    ]
  }
}

///|
/// A row action button carrying its action name as a data attribute for the
/// client Island to dispatch.
fn action_button(
  label : String,
  action : String,
  variant~ : @atoms.ButtonVariant,
  disabled~ : Bool,
) -> @luna.Node[Unit, String] {
  span(
    attrs=[("data-action", @luna.attr_static(action))],
    style="display:inline-flex;",
    [@atoms.button_atom(label, variant~, size=Small, disabled~)],
  )
}

///|
/// A plain text table cell.
fn text_cell(value : String, mono~ : Bool) -> @luna.Node[Unit, String] {
  let value_font = if mono { font_mono } else { font_ui }
  div(
    attrs=[("role", @luna.attr_static("cell"))],
    style="color:" +
      color_text +
      ";font-size:0.875rem;padding:12px 16px;word-break:break-all;" +
      value_font,
    [text(value)],
  )
}
