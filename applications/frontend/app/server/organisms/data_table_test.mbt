///| Tests for the generic DataTable organism.

///|
let sample_columns : Array[TableColumn] = [
  { label: "ID", width: "1fr", mono: true },
  { label: "名前", width: "2fr", mono: false },
]

///|
test "data_table renders an ARIA table with column headers" {
  let html = @server_dom.render(
    data_table(sample_columns, [["1", "甲"]]),
  )
  assert_true(html.contains("role=\"table\""))
  assert_true(html.contains("role=\"columnheader\""))
  assert_true(html.contains("ID"))
  assert_true(html.contains("名前"))
}

///|
test "data_table renders each row's cells with the cell role" {
  let html = @server_dom.render(
    data_table(sample_columns, [["1", "甲"], ["2", "乙"]]),
  )
  assert_true(html.contains("role=\"row\""))
  assert_true(html.contains("role=\"cell\""))
  assert_true(html.contains("甲"))
  assert_true(html.contains("乙"))
}

///|
test "data_table renders the empty state when there are no rows" {
  let html = @server_dom.render(
    data_table(sample_columns, [], empty_message="データなし"),
  )
  assert_true(html.contains("データなし"))
  assert_false(html.contains("role=\"cell\""))
}

///|
test "data_table renders mono columns in the monospace face" {
  let html = @server_dom.render(data_table(sample_columns, [["01ABC", "甲"]]))
  assert_true(html.contains("JetBrains Mono"))
}

///|
test "data_table uses the design-system surface and radius tokens" {
  let html = @server_dom.render(data_table(sample_columns, [["1", "甲"]]))
  assert_true(html.contains("--color-surface"))
  assert_true(html.contains("--radius-md"))
}

///|
test "data_table without pagination omits the page nav" {
  let html = @server_dom.render(data_table(sample_columns, [["1", "甲"]]))
  assert_false(html.contains("ページ送り"))
}

///|
test "data_table with pagination renders the page nav and summary" {
  let html = @server_dom.render(
    data_table(
      sample_columns,
      [["1", "甲"]],
      pagination=Some({
        summary: "1–1 件",
        has_prev: false,
        has_next: true,
        prev_cursor: "",
        next_cursor: "abc",
      }),
    ),
  )
  assert_true(html.contains("ページ送り"))
  assert_true(html.contains("1–1 件"))
  assert_true(html.contains("data-next-cursor=\"abc\""))
}

///|
test "data_table tolerates rows with fewer cells than columns" {
  let html = @server_dom.render(data_table(sample_columns, [["only"]]))
  assert_true(html.contains("only"))
}
