///| Tests for the form_field molecule.

///| Renders to HTML via @server_dom.render and asserts on structure / a11y / state.

///|
test "form_field renders a label associated with the input id" {
  let html = @server_dom.render(form_field("メールアドレス", "email"))
  assert_true(html.contains("<label"))
  assert_true(html.contains("for=\"email\""))
  assert_true(html.contains("id=\"email\""))
  assert_true(html.contains("メールアドレス"))
}

///|
test "form_field defaults the input name to the field id" {
  let html = @server_dom.render(form_field("ユーザー名", "username"))
  assert_true(html.contains("name=\"username\""))
}

///|
test "form_field uses an explicit name when provided" {
  let html = @server_dom.render(
    form_field("ユーザー名", "username", name="user_name"),
  )
  assert_true(html.contains("name=\"user_name\""))
}

///|
test "form_field with an error marks the input invalid and announces the message" {
  let html = @server_dom.render(
    form_field(
      "パスワード",
      "password",
      error="8文字以上で入力してください",
    ),
  )
  assert_true(html.contains("aria-invalid=\"true\""))
  assert_true(html.contains("role=\"alert\""))
  assert_true(html.contains("8文字以上で入力してください"))
}

///|
test "form_field without an error is valid" {
  let html = @server_dom.render(form_field("名前", "name"))
  assert_true(html.contains("aria-invalid=\"false\""))
}

///|
test "form_field shows help text when there is no error" {
  let html = @server_dom.render(
    form_field("金額", "amount", help="円単位で入力"),
  )
  assert_true(html.contains("円単位で入力"))
  assert_false(html.contains("role=\"alert\""))
}

///|
test "form_field error takes precedence over help text" {
  let html = @server_dom.render(
    form_field(
      "金額",
      "amount",
      help="円単位で入力",
      error="必須項目です",
    ),
  )
  assert_true(html.contains("必須項目です"))
  assert_false(html.contains("円単位で入力"))
}

///|
test "required form_field shows a required marker and required attribute" {
  let html = @server_dom.render(
    form_field("メール", "email2", required=true),
  )
  assert_true(html.contains("required"))
  assert_true(html.contains("*"))
}

///|
test "password form_field renders a password input" {
  let html = @server_dom.render(
    form_field("パスワード", "pw", input_type=Password),
  )
  assert_true(html.contains("type=\"password\""))
}
