///| Tests for the key_value and key_value_list molecules.

///|
test "key_value renders the key and value" {
  let html = @server_dom.render(key_value("銘柄", "7203 トヨタ"))
  assert_true(html.contains("銘柄"))
  assert_true(html.contains("7203 トヨタ"))
}

///|
test "key_value mono renders the value in the monospace face" {
  let html = @server_dom.render(key_value("数量", "1000", mono=true))
  assert_true(html.contains("JetBrains Mono"))
}

///|
test "key_value non-mono uses the UI font for the value" {
  let html = @server_dom.render(key_value("状態", "承認済み"))
  assert_true(html.contains("IBM Plex Sans"))
}

///|
test "key_value_list renders every row" {
  let html = @server_dom.render(
    key_value_list([
      ("注文ID", "01J..."),
      ("銘柄", "7203"),
      ("数量", "100"),
    ]),
  )
  assert_true(html.contains("注文ID"))
  assert_true(html.contains("銘柄"))
  assert_true(html.contains("数量"))
  assert_true(html.contains("01J..."))
}

///|
test "key_value_list marks the wrapper as a list" {
  let html = @server_dom.render(key_value_list([("a", "1"), ("b", "2")]))
  assert_true(html.contains("role=\"list\""))
}

///|
test "key_value_list adds separators between rows but not before the first" {
  let html = @server_dom.render(key_value_list([("a", "1"), ("b", "2")]))
  assert_true(html.contains("border-top"))
}

///|
test "key_value_list with a single row has no separator" {
  let html = @server_dom.render(key_value_list([("only", "1")]))
  assert_false(html.contains("border-top"))
}
