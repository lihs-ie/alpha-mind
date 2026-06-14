///| Tests for the Modal organism.

///|
test "modal renders a dialog with title and body" {
  let html = @server_dom.render(
    modal("m1", "確認", [@server_dom.text("本当に実行しますか？")]),
  )
  assert_true(html.contains("role=\"dialog\""))
  assert_true(html.contains("aria-modal=\"true\""))
  assert_true(html.contains("確認"))
  assert_true(html.contains("本当に実行しますか？"))
}

///|
test "modal is closed (display:none) by default at SSR time" {
  let html = @server_dom.render(modal("m1", "確認", [@server_dom.text("x")]))
  assert_true(html.contains("display:none"))
  assert_true(html.contains("data-modal-open=\"false\""))
}

///|
test "an open modal is displayed" {
  let html = @server_dom.render(
    modal("m1", "確認", [@server_dom.text("x")], open=true),
  )
  assert_true(html.contains("data-modal-open=\"true\""))
  assert_false(html.contains("display:none"))
}

///|
test "modal sits at the modal z-layer" {
  let html = @server_dom.render(modal("m1", "確認", [@server_dom.text("x")]))
  assert_true(html.contains("--z-modal"))
}

///|
test "modal associates labelledby and describedby ids with the dialog" {
  let html = @server_dom.render(modal("m1", "確認", [@server_dom.text("x")]))
  assert_true(html.contains("aria-labelledby=\"m1-title\""))
  assert_true(html.contains("aria-describedby=\"m1-body\""))
  assert_true(html.contains("id=\"m1-title\""))
  assert_true(html.contains("id=\"m1-body\""))
}

///|
test "modal without actions omits the footer buttons" {
  let html = @server_dom.render(modal("m1", "確認", [@server_dom.text("x")]))
  assert_false(html.contains("data-action=\"confirm\""))
}

///|
test "modal renders supplied confirm / cancel actions" {
  let html = @server_dom.render(
    modal(
      "m1",
      "承認",
      [@server_dom.text("x")],
      actions=modal_confirm_actions(confirm_label="承認する"),
    ),
  )
  assert_true(html.contains("承認する"))
  assert_true(html.contains("キャンセル"))
  assert_true(html.contains("data-action=\"confirm\""))
  assert_true(html.contains("data-action=\"cancel\""))
}

///|
test "destructive confirm actions use the danger button" {
  let html = @server_dom.render(
    modal(
      "m1",
      "削除",
      [@server_dom.text("x")],
      actions=modal_confirm_actions(confirm_label="削除", destructive=true),
    ),
  )
  // Danger variant button uses the danger colour #F87171.
  assert_true(html.contains("#F87171"))
}
