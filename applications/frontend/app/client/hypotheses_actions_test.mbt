///| Tests for the HypothesesActions Island logic (SCR-007 仮説ラボ).
///| Verifies Props serialization, status filter matching, state-machine-aware
///| operation availability (M8), and promote/reject/mnpi validation (M9).

///|
test "HypothesisRowProps round-trip ToJson/FromJson" {
  let row : HypothesisRowProps = {
    identifier: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
    symbol: "1306.T",
    instrument_type: "ETF",
    status: "demo",
    title: "低ボラETFの押し目反発仮説",
    updated_at: "2026-01-15T09:00:00Z",
  }
  let json = row.to_json()
  let restored : HypothesisRowProps = @json.from_json(json)
  assert_eq(row.identifier, restored.identifier)
  assert_eq(row.symbol, restored.symbol)
  assert_eq(row.instrument_type, restored.instrument_type)
  assert_eq(row.status, restored.status)
  assert_eq(row.title, restored.title)
  assert_eq(row.updated_at, restored.updated_at)
}

///|
test "HypothesesActionsProps round-trip with multiple hypotheses" {
  let props : HypothesesActionsProps = {
    bff_base_url: "https://api.alpha-mind.dev",
    initial_next_cursor: "cursor-2",
    initial_hypotheses: [
      {
        identifier: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
        symbol: "1306.T",
        instrument_type: "ETF",
        status: "demo",
        title: "低ボラETFの押し目反発",
        updated_at: "2026-01-15T09:00:00Z",
      },
      {
        identifier: "01ARZ3NDEKTSV4RRFFQ69G5FBW",
        symbol: "7203.T",
        instrument_type: "STOCK",
        status: "backtested",
        title: "自動車の需給改善",
        updated_at: "2026-01-16T09:00:00Z",
      },
    ],
  }
  let restored : HypothesesActionsProps = @json.from_json(props.to_json())
  assert_eq(restored.bff_base_url, "https://api.alpha-mind.dev")
  assert_eq(restored.initial_next_cursor, "cursor-2")
  assert_eq(restored.initial_hypotheses.length(), 2)
  assert_eq(restored.initial_hypotheses[1].instrument_type, "STOCK")
  assert_eq(restored.initial_hypotheses[1].status, "backtested")
}

// ── status filter matching ──────────────────────────────────────────────────

///|
test "hypothesis_matches_filter: empty filter matches everything" {
  assert_true(hypothesis_matches_filter("draft", ""))
  assert_true(hypothesis_matches_filter("live", ""))
}

///|
test "hypothesis_matches_filter: status filter is exact" {
  assert_true(hypothesis_matches_filter("demo", "demo"))
  assert_false(hypothesis_matches_filter("draft", "demo"))
}

// ── operation availability (state machine, M8) ────────────────────────────────

///|
test "can_retest_hypothesis: allowed for non-terminal states, blocked for live/rejected" {
  assert_true(can_retest_hypothesis("draft"))
  assert_true(can_retest_hypothesis("backtested"))
  assert_true(can_retest_hypothesis("demo"))
  assert_false(can_retest_hypothesis("live"))
  assert_false(can_retest_hypothesis("rejected"))
}

///|
test "can_promote_hypothesis: only demo is promotable" {
  assert_true(can_promote_hypothesis("demo"))
  assert_false(can_promote_hypothesis("draft"))
  assert_false(can_promote_hypothesis("backtested"))
  assert_false(can_promote_hypothesis("live"))
  assert_false(can_promote_hypothesis("rejected"))
}

///|
test "can_update_mnpi_hypothesis: only demo can self-declare" {
  assert_true(can_update_mnpi_hypothesis("demo"))
  assert_false(can_update_mnpi_hypothesis("draft"))
  assert_false(can_update_mnpi_hypothesis("live"))
}

///|
test "can_reject_hypothesis: allowed for non-terminal states" {
  assert_true(can_reject_hypothesis("draft"))
  assert_true(can_reject_hypothesis("backtested"))
  assert_true(can_reject_hypothesis("demo"))
  assert_false(can_reject_hypothesis("live"))
  assert_false(can_reject_hypothesis("rejected"))
}

// ── promote validation (M9, SCR-007 §5 / 条件付き自動昇格設計 §5) ───────────────

///|
test "validate_promote_hypothesis: insufficient demo period is rejected" {
  // 29 days < 1 month threshold.
  assert_eq(
    validate_promote_hypothesis("MODEL_REVIEW_DECISION", 29, false, true),
    "デモ期間が不足しています",
  )
}

///|
test "validate_promote_hypothesis: requiresComplianceReview blocks promotion" {
  assert_eq(
    validate_promote_hypothesis("MODEL_REVIEW_DECISION", 45, true, true),
    "コンプライアンスレビュー未完了です",
  )
}

///|
test "validate_promote_hypothesis: missing MNPI self-declaration is rejected" {
  assert_eq(
    validate_promote_hypothesis("MODEL_REVIEW_DECISION", 45, false, false),
    "MNPI自己申告が未完了です",
  )
}

///|
test "validate_promote_hypothesis: missing reason code is rejected" {
  assert_eq(
    validate_promote_hypothesis("", 45, false, true),
    "操作理由コードを選択してください",
  )
}

///|
test "validate_promote_hypothesis: all conditions met passes" {
  assert_eq(
    validate_promote_hypothesis("MODEL_REVIEW_DECISION", 45, false, true),
    "",
  )
  // exactly 30 days (1 month) is sufficient.
  assert_eq(
    validate_promote_hypothesis("MODEL_REVIEW_DECISION", 30, false, true),
    "",
  )
}

// ── reject / mnpi validation (M9) ─────────────────────────────────────────────

///|
test "validate_reject_hypothesis: missing reason code is rejected" {
  assert_eq(validate_reject_hypothesis(""), "却下理由コードを選択してください")
}

///|
test "validate_reject_hypothesis: valid input passes" {
  assert_eq(validate_reject_hypothesis("POLICY_COMPLIANCE_HOLD"), "")
}

///|
test "validate_mnpi_hypothesis: missing reason code is rejected" {
  assert_eq(
    validate_mnpi_hypothesis(""),
    "操作理由コードを選択してください",
  )
}

///|
test "validate_mnpi_hypothesis: valid input passes" {
  assert_eq(validate_mnpi_hypothesis("MANUAL_OPERATION"), "")
}

// ── demo period parsing ───────────────────────────────────────────────────────

///|
test "parse_demo_period_days: day suffix" {
  assert_eq(parse_demo_period_days("45d"), 45)
  assert_eq(parse_demo_period_days("7days"), 7)
}

///|
test "parse_demo_period_days: week and month suffixes" {
  assert_eq(parse_demo_period_days("2w"), 14)
  assert_eq(parse_demo_period_days("2m"), 60)
  assert_eq(parse_demo_period_days("1month"), 30)
}

///|
test "parse_demo_period_days: bare integer treated as days; empty is zero" {
  assert_eq(parse_demo_period_days("90"), 90)
  assert_eq(parse_demo_period_days(""), 0)
}

// ── status badge styling ──────────────────────────────────────────────────────

///|
test "hypothesis_status_badge_style: distinct colours per status" {
  let live = hypothesis_status_badge_style("live")
  let rejected = hypothesis_status_badge_style("rejected")
  // live uses the profit colour token; rejected uses the loss colour token.
  assert_true(live != rejected)
  assert_true(live.contains("--color-profit"))
  assert_true(rejected.contains("--color-loss"))
}

// ── metric formatting ─────────────────────────────────────────────────────────

///|
test "format_metric: fraction digits" {
  assert_eq(format_metric(4.2, 2), "4.20")
  assert_eq(format_metric(1.14, 2), "1.14")
  assert_eq(format_metric(0.085, 2), "0.09")
}
