///| Tests for the toast / toast_region / retry_banner molecules.

///|
test "toast renders the message and a success status role" {
  let html = @server_dom.render(toast("保存しました", kind=Success))
  assert_true(html.contains("保存しました"))
  assert_true(html.contains("role=\"status\""))
  assert_true(html.contains("data-toast-kind=\"success\""))
}

///|
test "warning toast is assertive (role=alert)" {
  let html = @server_dom.render(toast("確認が必要です", kind=Warning))
  assert_true(html.contains("role=\"alert\""))
  assert_true(html.contains("data-toast-kind=\"warning\""))
}

///|
test "error toast is assertive and uses the danger colour" {
  let html = @server_dom.render(toast("失敗しました", kind=Error))
  assert_true(html.contains("role=\"alert\""))
  assert_true(html.contains("data-toast-kind=\"error\""))
  assert_true(html.contains("#F87171"))
}

///|
test "toast surfaces the auto-dismiss delay (default 5000ms)" {
  let html = @server_dom.render(toast("done"))
  assert_true(html.contains("data-auto-dismiss-ms=\"5000\""))
}

///|
test "toast honours a custom auto-dismiss delay" {
  let html = @server_dom.render(toast("done", auto_dismiss_ms=3000))
  assert_true(html.contains("data-auto-dismiss-ms=\"3000\""))
}

///|
test "toast conveys severity by an icon, not colour alone" {
  let html = @server_dom.render(toast("ok", kind=Success))
  assert_true(html.contains("<svg"))
}

///|
test "toast_region is a fixed top-right polite live region" {
  let html = @server_dom.render(toast_region())
  assert_true(html.contains("id=\"toast-region\""))
  assert_true(html.contains("aria-live=\"polite\""))
  assert_true(html.contains("--z-toast"))
}

///|
test "toast_region renders seeded toasts" {
  let html = @server_dom.render(toast_region(toasts=[toast("初期通知")]))
  assert_true(html.contains("初期通知"))
}

///|
test "retry_banner renders the message and a retry button as an alert" {
  let html = @server_dom.render(
    retry_banner("読み込みに失敗しました"),
  )
  assert_true(html.contains("role=\"alert\""))
  assert_true(html.contains("読み込みに失敗しました"))
  assert_true(html.contains("再試行"))
}

///|
test "retry_banner accepts a custom retry label" {
  let html = @server_dom.render(
    retry_banner("失敗", retry_label="もう一度"),
  )
  assert_true(html.contains("もう一度"))
}

///|
test "toast_kind_label maps each kind to a stable string" {
  assert_eq(toast_kind_label(Success), "success")
  assert_eq(toast_kind_label(Warning), "warning")
  assert_eq(toast_kind_label(Error), "error")
}
