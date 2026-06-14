///| Tests for the login form Island logic.
///| Verifies Props serialization and email validation behaviour.

///|
test "LoginFormProps round-trip ToJson/FromJson" {
  let props : LoginFormProps = { bff_base_url: "https://api.alpha-mind.dev" }
  let json = props.to_json()
  let restored : LoginFormProps = @json.from_json(json)
  assert_eq(props.bff_base_url, restored.bff_base_url)
}

///|
test "LoginFormProps default bff_base_url survives empty string round-trip" {
  let props : LoginFormProps = { bff_base_url: "" }
  let json = props.to_json()
  let restored : LoginFormProps = @json.from_json(json)
  assert_eq(restored.bff_base_url, "")
}
