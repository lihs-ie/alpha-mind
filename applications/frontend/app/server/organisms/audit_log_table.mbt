///| AuditLogTable organism (time-ordered audit-log list section).
///|
///| The SCR-004 audit-log list: a div-based ARIA table (the static DSL has no
///| `<table>`) showing each record's timestamp, event type, service, result and
///| trace. The result column renders `@atoms.status_badge_atom`; the trace column
///| renders a copyable trace chip (the common-screen spec §8 requires the
///| displayed `trace` to be copyable — the actual clipboard write is wired by the
///| AuditSearch client Island via the rendered `data-trace` / `data-copy`
///| attributes). Timestamps and trace ids use the monospace face.
///|
///| Ref: documents/外部設計/screens/SCR-004_監査ログ.md,
///|      documents/外部設計/screens/画面外部設計_共通.md §8 (trace コピー可能)

///|
/// A single audit-log row for the AuditLogTable.
pub(all) struct AuditRow {
  /// Audit record identifier.
  identifier : String
  /// Occurrence timestamp (ISO8601 UTC); monospace.
  occurred_at : String
  /// Event type (e.g. "order.approved").
  event_type : String
  /// Originating service (e.g. "svc-execution").
  service : String
  /// Result ("SUCCESS" / "FAILURE" / domain status).
  result : String
  /// Trace identifier (ULID); monospace and copyable.
  trace : String
}

///|
/// Render the audit-log table.
///
/// - `logs`: the audit rows (already time-ordered by the caller).
/// - `empty_message`: text shown when there are no rows.
/// - `extra_style`: caller-appended inline style on the table wrapper.
pub fn audit_log_table(
  logs : Array[AuditRow],
  empty_message~ : String = "該当するログがありません。",
  extra_style~ : String = "",
) -> @luna.Node[Unit, String] {
  let grid_template = "grid-template-columns:1.4fr 1.4fr 1.2fr 0.9fr 1.6fr;"
  let header = audit_header_row(grid_template)
  let body : @luna.Node[Unit, String] = if logs.length() == 0 {
    div(
      attrs=[("role", @luna.attr_static("status"))],
      style="padding:var(--space-2xl,48px) var(--space-lg,24px);text-align:center;color:" +
        color_text_muted +
        ";font-size:0.875rem;" +
        font_ui,
      [text(empty_message)],
    )
  } else {
    let rows = logs.map(fn(row) { audit_body_row(row, grid_template) })
    div([..rows])
  }
  div(
    attrs=[
      ("role", @luna.attr_static("table")),
      ("aria-label", @luna.attr_static("監査ログ一覧")),
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
/// Header row labels for the audit-log table.
fn audit_header_row(grid_template : String) -> @luna.Node[Unit, String] {
  let labels = ["発生時刻", "イベント種別", "サービス", "結果", "トレース"]
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
/// One audit row: timestamp / event type / service / result badge / trace chip.
fn audit_body_row(
  row : AuditRow,
  grid_template : String,
) -> @luna.Node[Unit, String] {
  let time_cell = plain_cell(row.occurred_at, mono=true)
  let event_cell = plain_cell(row.event_type, mono=false)
  let service_cell = plain_cell(row.service, mono=false)
  let result_cell = div(
    attrs=[("role", @luna.attr_static("cell"))],
    style="padding:12px 16px;",
    [@atoms.status_badge_atom(row.result)],
  )
  let trace_cell = div(
    attrs=[("role", @luna.attr_static("cell"))],
    style="padding:12px 16px;",
    [trace_chip(row.trace)],
  )
  div(
    attrs=[
      ("role", @luna.attr_static("row")),
      ("data-audit-id", @luna.attr_static(row.identifier)),
    ],
    style="display:grid;align-items:center;" +
      grid_template +
      "border-bottom:1px solid " +
      color_border +
      ";" +
      transition,
    [time_cell, event_cell, service_cell, result_cell, trace_cell],
  )
}

///|
/// A copyable trace chip: the trace id in the monospace face with a copy
/// affordance the Island reads via `data-copy` / `data-trace`.
fn trace_chip(trace : String) -> @luna.Node[Unit, String] {
  span(
    attrs=[
      ("data-copy", @luna.attr_static("trace")),
      ("data-trace", @luna.attr_static(trace)),
      ("role", @luna.attr_static("button")),
      ("tabindex", @luna.attr_static("0")),
      ("aria-label", @luna.attr_static("トレースをコピー: " + trace)),
    ],
    style="display:inline-flex;align-items:center;gap:6px;padding:2px 8px;border-radius:var(--radius-sm,6px);border:1px solid " +
      color_border +
      ";color:" +
      color_text +
      ";font-size:0.8125rem;cursor:pointer;" +
      font_mono +
      transition,
    [text(trace)],
  )
}

///|
/// A plain text cell for the audit table.
fn plain_cell(value : String, mono~ : Bool) -> @luna.Node[Unit, String] {
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
