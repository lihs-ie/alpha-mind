///| Auto-generated Props round-trip tests
///| Verifies to_json/from_json symmetry for all island Props types

///|
test "AuditRowProps round-trip" {
  let json_str = "{ \"identifier\": \"\", \"occurred_at\": \"\", \"event_type\": \"\", \"service\": \"\", \"result\": \"\", \"trace\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : AuditRowProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : AuditRowProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "audit_row ComponentRef url" {
  let json_str = "{ \"identifier\": \"\", \"occurred_at\": \"\", \"event_type\": \"\", \"service\": \"\", \"result\": \"\", \"trace\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : AuditRowProps = @json.from_json(json)
  let cref = audit_row(props)
  assert_true(cref.url.has_suffix("audit_row.js"))
}

///|
test "AuditSearchProps round-trip" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_logs\": [] }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : AuditSearchProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : AuditSearchProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "audit_search ComponentRef url" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_logs\": [] }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : AuditSearchProps = @json.from_json(json)
  let cref = audit_search(props)
  assert_true(cref.url.has_suffix("audit_search.js"))
}

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
test "ModelValidationRowProps round-trip" {
  let json_str = "{ \"model_version\": \"\", \"status\": \"\", \"degradation_flag\": \"\", \"created_at\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : ModelValidationRowProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : ModelValidationRowProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "model_validation_row ComponentRef url" {
  let json_str = "{ \"model_version\": \"\", \"status\": \"\", \"degradation_flag\": \"\", \"created_at\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : ModelValidationRowProps = @json.from_json(json)
  let cref = model_validation_row(props)
  assert_true(cref.url.has_suffix("model_validation_row.js"))
}

///|
test "ModelsActionsProps round-trip" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_models\": [] }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : ModelsActionsProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : ModelsActionsProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "models_actions ComponentRef url" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_models\": [] }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : ModelsActionsProps = @json.from_json(json)
  let cref = models_actions(props)
  assert_true(cref.url.has_suffix("models_actions.js"))
}

///|
test "OrderRowProps round-trip" {
  let json_str = "{ \"identifier\": \"\", \"symbol\": \"\", \"side\": \"\", \"qty\": 0, \"status\": \"\", \"created_at\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : OrderRowProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : OrderRowProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "order_row ComponentRef url" {
  let json_str = "{ \"identifier\": \"\", \"symbol\": \"\", \"side\": \"\", \"qty\": 0, \"status\": \"\", \"created_at\": \"\" }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : OrderRowProps = @json.from_json(json)
  let cref = order_row(props)
  assert_true(cref.url.has_suffix("order_row.js"))
}

///|
test "OrdersActionsProps round-trip" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_orders\": [], \"initial_kill_switch_enabled\": false }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : OrdersActionsProps = @json.from_json(json)
  let roundtrip = props.to_json()
  let restored : OrdersActionsProps = @json.from_json(roundtrip)
  assert_eq(props.to_json().stringify(), restored.to_json().stringify())
}

///|
test "orders_actions ComponentRef url" {
  let json_str = "{ \"bff_base_url\": \"\", \"initial_orders\": [], \"initial_kill_switch_enabled\": false }"
  let json : Json = @json.parse(json_str) catch { _ => panic() }
  let props : OrdersActionsProps = @json.from_json(json)
  let cref = orders_actions(props)
  assert_true(cref.url.has_suffix("orders_actions.js"))
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

