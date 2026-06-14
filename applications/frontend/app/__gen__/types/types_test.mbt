///| Auto-generated Props round-trip tests
///| Verifies to_json/from_json symmetry for all island Props types

///|
test "DashboardOperationsProps round-trip" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_runtime_state\": \"\", \"initial_kill_switch_enabled\": false }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : DashboardOperationsProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : DashboardOperationsProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "dashboard_operations ComponentRef url" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_runtime_state\": \"\", \"initial_kill_switch_enabled\": false }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : DashboardOperationsProps = @json.from_json(json)
  let cref = dashboard_operations(props)
  assert_true(cref.url.has_suffix("dashboard_operations.js"))
}

///|
test "LoginFormProps round-trip" {
  let json_str = "{ \"bff_base_url\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : LoginFormProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : LoginFormProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "login_form ComponentRef url" {
  let json_str = "{ \"bff_base_url\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : LoginFormProps = @json.from_json(json)
  let cref = login_form(props)
  assert_true(cref.url.has_suffix("login_form.js"))
}

