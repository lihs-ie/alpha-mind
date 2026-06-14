///| Tests for the DashboardOperationsIsland logic.
///| Verifies Props serialization (ToJson/FromJson round-trips).

///|
test "DashboardOperationsProps round-trip — running + kill switch disabled" {
  let props : DashboardOperationsProps = {
    bff_base_url: "https://api.alpha-mind.dev",
    initial_runtime_state: "RUNNING",
    initial_kill_switch_enabled: false,
  }
  let json = props.to_json()
  let restored : DashboardOperationsProps = @json.from_json(json)
  assert_eq(props.bff_base_url, restored.bff_base_url)
  assert_eq(props.initial_runtime_state, restored.initial_runtime_state)
  assert_eq(
    props.initial_kill_switch_enabled,
    restored.initial_kill_switch_enabled,
  )
}

///|
test "DashboardOperationsProps round-trip — stopped + kill switch enabled" {
  let props : DashboardOperationsProps = {
    bff_base_url: "http://localhost:8080",
    initial_runtime_state: "STOPPED",
    initial_kill_switch_enabled: true,
  }
  let json = props.to_json()
  let restored : DashboardOperationsProps = @json.from_json(json)
  assert_eq(props.initial_runtime_state, restored.initial_runtime_state)
  assert_eq(
    props.initial_kill_switch_enabled,
    restored.initial_kill_switch_enabled,
  )
}

///|
test "DashboardOperationsProps bff_base_url preserved across serialization" {
  let url = "https://bff.example.com"
  let props : DashboardOperationsProps = {
    bff_base_url: url,
    initial_runtime_state: "STOPPED",
    initial_kill_switch_enabled: false,
  }
  let json = props.to_json()
  let restored : DashboardOperationsProps = @json.from_json(json)
  assert_eq(restored.bff_base_url, url)
}
