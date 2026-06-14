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

///|
test "BlackoutWindowProps round-trip" {
  let json_str = "{ \"symbol\": \"\", \"start_at\": \"\", \"end_at\": \"\", \"action_reason_code\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : BlackoutWindowProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : BlackoutWindowProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "blackout_window ComponentRef url" {
  let json_str = "{ \"symbol\": \"\", \"start_at\": \"\", \"end_at\": \"\", \"action_reason_code\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : BlackoutWindowProps = @json.from_json(json)
  let cref = blackout_window(props)
  assert_true(cref.url.has_suffix("blackout_window.js"))
}

///|
test "StrategyFormProps round-trip" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_market\": \"\", \"initial_rebalance_frequency\": \"\", \"initial_symbols\": [], \"initial_daily_loss_limit\": 0, \"initial_position_concentration_limit\": 0, \"initial_daily_order_limit\": 0, \"initial_restricted_symbols\": [], \"initial_blackout_windows\": [] }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : StrategyFormProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : StrategyFormProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "strategy_form ComponentRef url" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_market\": \"\", \"initial_rebalance_frequency\": \"\", \"initial_symbols\": [], \"initial_daily_loss_limit\": 0, \"initial_position_concentration_limit\": 0, \"initial_daily_order_limit\": 0, \"initial_restricted_symbols\": [], \"initial_blackout_windows\": [] }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : StrategyFormProps = @json.from_json(json)
  let cref = strategy_form(props)
  assert_true(cref.url.has_suffix("strategy_form.js"))
}

