///| Tests for the pagination molecule (cursor-based).

///|
test "pagination renders prev and next controls in a labelled nav" {
  let html = @server_dom.render(pagination())
  assert_true(html.contains("<nav"))
  assert_true(html.contains("aria-label=\"ページ送り\""))
  assert_true(html.contains("前へ"))
  assert_true(html.contains("次へ"))
}

///|
test "pagination disables prev when there is no previous page" {
  let html = @server_dom.render(pagination(has_prev=false, has_next=true))
  assert_true(html.contains("disabled"))
}

///|
test "pagination enables next and exposes its cursor as a data attribute" {
  let html = @server_dom.render(
    pagination(has_next=true, next_cursor="cursor-abc"),
  )
  assert_true(html.contains("data-next-cursor=\"cursor-abc\""))
}

///|
test "pagination exposes the prev cursor as a data attribute" {
  let html = @server_dom.render(
    pagination(has_prev=true, prev_cursor="cursor-xyz"),
  )
  assert_true(html.contains("data-prev-cursor=\"cursor-xyz\""))
}

///|
test "pagination renders a summary when provided" {
  let html = @server_dom.render(pagination(summary="1–20 件"))
  assert_true(html.contains("1–20 件"))
}

///|
test "pagination omits the summary when empty" {
  let html = @server_dom.render(pagination())
  assert_true(html.contains("display:none"))
}
