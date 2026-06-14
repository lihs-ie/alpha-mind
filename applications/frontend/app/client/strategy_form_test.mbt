///| Tests for the StrategyForm Island logic.
///| Verifies Props serialization (ToJson/FromJson round-trips) and
///| BlackoutWindowProps serialization.

///|
test "StrategyFormProps round-trip — basic values" {
  let props : StrategyFormProps = {
    bff_base_url: "https://api.alpha-mind.dev",
    initial_market: "JP",
    initial_rebalance_frequency: "daily",
    initial_symbols: ["1306.T", "1321.T"],
    initial_daily_loss_limit: 5.0,
    initial_position_concentration_limit: 30.0,
    initial_daily_order_limit: 10,
    initial_restricted_symbols: ["AAPL"],
    initial_blackout_windows: [],
  }
  let json = props.to_json()
  let restored : StrategyFormProps = @json.from_json(json)
  assert_eq(props.bff_base_url, restored.bff_base_url)
  assert_eq(props.initial_market, restored.initial_market)
  assert_eq(props.initial_rebalance_frequency, restored.initial_rebalance_frequency)
  assert_eq(props.initial_daily_loss_limit, restored.initial_daily_loss_limit)
  assert_eq(
    props.initial_position_concentration_limit,
    restored.initial_position_concentration_limit,
  )
  assert_eq(props.initial_daily_order_limit, restored.initial_daily_order_limit)
}

///|
test "StrategyFormProps round-trip — weekly frequency" {
  let props : StrategyFormProps = {
    bff_base_url: "http://localhost:8080",
    initial_market: "JP",
    initial_rebalance_frequency: "weekly",
    initial_symbols: ["2558.T"],
    initial_daily_loss_limit: 2.5,
    initial_position_concentration_limit: 20.0,
    initial_daily_order_limit: 5,
    initial_restricted_symbols: [],
    initial_blackout_windows: [],
  }
  let json = props.to_json()
  let restored : StrategyFormProps = @json.from_json(json)
  assert_eq(props.initial_rebalance_frequency, restored.initial_rebalance_frequency)
  assert_eq(props.initial_daily_order_limit, restored.initial_daily_order_limit)
}

///|
test "BlackoutWindowProps round-trip" {
  let window : BlackoutWindowProps = {
    symbol: "7203.T",
    start_at: "2026-03-01T09:00:00Z",
    end_at: "2026-03-15T15:30:00Z",
    action_reason_code: "MANUAL_OPERATION",
  }
  let json = window.to_json()
  let restored : BlackoutWindowProps = @json.from_json(json)
  assert_eq(window.symbol, restored.symbol)
  assert_eq(window.start_at, restored.start_at)
  assert_eq(window.end_at, restored.end_at)
  assert_eq(window.action_reason_code, restored.action_reason_code)
}

///|
test "StrategyFormProps with blackout windows round-trip" {
  let window : BlackoutWindowProps = {
    symbol: "AAPL",
    start_at: "2026-01-15T09:00:00Z",
    end_at: "2026-01-16T09:00:00Z",
    action_reason_code: "MANUAL_OPERATION",
  }
  let props : StrategyFormProps = {
    bff_base_url: "https://api.alpha-mind.dev",
    initial_market: "JP",
    initial_rebalance_frequency: "daily",
    initial_symbols: ["1306.T"],
    initial_daily_loss_limit: 10.0,
    initial_position_concentration_limit: 25.0,
    initial_daily_order_limit: 20,
    initial_restricted_symbols: ["AAPL"],
    initial_blackout_windows: [window],
  }
  let json = props.to_json()
  let restored : StrategyFormProps = @json.from_json(json)
  assert_eq(props.initial_restricted_symbols.length(), restored.initial_restricted_symbols.length())
  assert_eq(props.initial_blackout_windows.length(), restored.initial_blackout_windows.length())
}

///|
test "StrategyFormProps bff_base_url preserved" {
  let url = "https://bff.example.com"
  let props : StrategyFormProps = {
    bff_base_url: url,
    initial_market: "JP",
    initial_rebalance_frequency: "daily",
    initial_symbols: ["1306.T"],
    initial_daily_loss_limit: 5.0,
    initial_position_concentration_limit: 30.0,
    initial_daily_order_limit: 10,
    initial_restricted_symbols: [],
    initial_blackout_windows: [],
  }
  let json = props.to_json()
  let restored : StrategyFormProps = @json.from_json(json)
  assert_eq(restored.bff_base_url, url)
}
