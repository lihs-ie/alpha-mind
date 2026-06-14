///| Tests for the FormSection organism.

///|
let login_fields : Array[FormFieldSpec] = [
  form_field_spec("メールアドレス", "email", required=true),
  form_field_spec(
    "パスワード",
    "password",
    input_type=@atoms.InputType::Password,
    required=true,
  ),
]

///|
test "form_section renders each field with its label and input" {
  let html = @server_dom.render(form_section(login_fields))
  assert_true(html.contains("メールアドレス"))
  assert_true(html.contains("パスワード"))
  assert_true(html.contains("<label"))
  assert_true(html.contains("<input"))
  assert_true(html.contains("id=\"email\""))
}

///|
test "form_section renders a submit button" {
  let html = @server_dom.render(
    form_section(login_fields, submit_label="ログイン"),
  )
  assert_true(html.contains("ログイン"))
  assert_true(html.contains("type=\"submit\""))
}

///|
test "form_section uses a card surface" {
  let html = @server_dom.render(form_section(login_fields))
  assert_true(html.contains("--color-surface"))
}

///|
test "form_section renders a section title in the card header" {
  let html = @server_dom.render(
    form_section(login_fields, title="ログイン"),
  )
  assert_true(html.contains("<h3"))
  assert_true(html.contains("ログイン"))
}

///|
test "form_section renders a top error summary as an alert region" {
  let html = @server_dom.render(
    form_section(login_fields, error_summary="入力に誤りがあります。"),
  )
  assert_true(html.contains("role=\"alert\""))
  assert_true(html.contains("入力に誤りがあります。"))
}

///|
test "form_section shows an inline field error and marks the input invalid" {
  let html = @server_dom.render(
    form_section([
      form_field_spec("メール", "email", error="必須項目です。"),
    ]),
  )
  assert_true(html.contains("必須項目です。"))
  assert_true(html.contains("aria-invalid=\"true\""))
}

///|
test "form_section renders a cancel button when a cancel label is given" {
  let html = @server_dom.render(
    form_section(login_fields, cancel_label="戻る"),
  )
  assert_true(html.contains("戻る"))
}

///|
test "a submitting form_section marks the submit button busy" {
  let html = @server_dom.render(
    form_section(login_fields, submitting=true),
  )
  assert_true(html.contains("aria-busy=\"true\""))
}

///|
test "form_section renders a password field as type password" {
  let html = @server_dom.render(form_section(login_fields))
  assert_true(html.contains("type=\"password\""))
}
