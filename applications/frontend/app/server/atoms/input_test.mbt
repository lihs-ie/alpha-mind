///| Tests for the input atom.

///|
test "input_atom Text renders type=text" {
  let html = @server_dom.render(input_atom(input_type=Text))
  assert_true(html.contains("<input"))
  assert_true(html.contains("type=\"text\""))
}

///|
test "input_atom Password renders type=password" {
  let html = @server_dom.render(input_atom(input_type=Password))
  assert_true(html.contains("type=\"password\""))
}

///|
test "input_atom Number renders type=number" {
  let html = @server_dom.render(input_atom(input_type=Number))
  assert_true(html.contains("type=\"number\""))
}

///|
test "input_atom passes through id, name and placeholder" {
  let html = @server_dom.render(
    input_atom(id="email", name="email", placeholder="operator@example.com"),
  )
  assert_true(html.contains("id=\"email\""))
  assert_true(html.contains("name=\"email\""))
  assert_true(html.contains("placeholder=\"operator@example.com\""))
}

///|
test "valid input_atom sets aria-invalid=false and neutral border" {
  let html = @server_dom.render(input_atom())
  assert_true(html.contains("aria-invalid=\"false\""))
}

///|
test "invalid input_atom sets aria-invalid=true and danger border" {
  let html = @server_dom.render(input_atom(invalid=true))
  assert_true(html.contains("aria-invalid=\"true\""))
  assert_true(html.contains("#F87171"))
}

///|
test "required input_atom sets the required attribute" {
  let html = @server_dom.render(input_atom(required=true))
  assert_true(html.contains("required"))
}

///|
test "disabled input_atom is disabled with not-allowed cursor" {
  let html = @server_dom.render(input_atom(disabled=true))
  assert_true(html.contains("disabled"))
  assert_true(html.contains("cursor:not-allowed"))
}

///|
test "input_atom declares a transition" {
  let html = @server_dom.render(input_atom())
  assert_true(html.contains("transition"))
}
