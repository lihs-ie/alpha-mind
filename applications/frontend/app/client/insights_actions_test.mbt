///| Tests for the InsightsActions Island logic (SCR-006).
///| Verifies Props serialization, theme/source filter matching, and
///| hypothesize/adopt/reject validation (sourceUrl, reason code).

///|
test "InsightRowProps round-trip ToJson/FromJson" {
  let row : InsightRowProps = {
    identifier: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
    source_type: "youtube",
    summary: "生成AI関連銘柄の短期モメンタムが継続",
    source_url: "https://example.com/live/stream",
    collected_at: "2026-01-15T09:00:00Z",
    signal_class: "structural_anomaly",
    so_what_score: 0.78,
  }
  let json = row.to_json()
  let restored : InsightRowProps = @json.from_json(json)
  assert_eq(row.identifier, restored.identifier)
  assert_eq(row.source_type, restored.source_type)
  assert_eq(row.summary, restored.summary)
  assert_eq(row.source_url, restored.source_url)
  assert_eq(row.signal_class, restored.signal_class)
  assert_eq(row.so_what_score, restored.so_what_score)
}

///|
test "InsightsActionsProps round-trip with multiple insights" {
  let props : InsightsActionsProps = {
    bff_base_url: "https://api.alpha-mind.dev",
    initial_next_cursor: "cursor-2",
    initial_insights: [
      {
        identifier: "01ARZ3NDEKTSV4RRFFQ69G5FAV",
        source_type: "x",
        summary: "ai-momentum 継続",
        source_url: "https://example.com/a",
        collected_at: "2026-01-15T09:00:00Z",
        signal_class: "structural_anomaly",
        so_what_score: 0.82,
      },
      {
        identifier: "01ARZ3NDEKTSV4RRFFQ69G5FBW",
        source_type: "paper",
        summary: "event noise の検証",
        source_url: "https://example.com/b",
        collected_at: "2026-01-16T09:00:00Z",
        signal_class: "event_noise",
        so_what_score: 0.41,
      },
    ],
  }
  let restored : InsightsActionsProps = @json.from_json(props.to_json())
  assert_eq(restored.bff_base_url, "https://api.alpha-mind.dev")
  assert_eq(restored.initial_next_cursor, "cursor-2")
  assert_eq(restored.initial_insights.length(), 2)
  assert_eq(restored.initial_insights[1].source_type, "paper")
}

// ── theme/source filter matching ──────────────────────────────────────────────

///|
test "insight_matches_filter: empty filters match everything" {
  assert_true(insight_matches_filter("any summary", "x", "", ""))
}

///|
test "insight_matches_filter: theme matches summary substring (case-insensitive)" {
  assert_true(
    insight_matches_filter("AI-Momentum が継続", "youtube", "ai-momentum", ""),
  )
}

///|
test "insight_matches_filter: theme matches source type substring" {
  assert_true(insight_matches_filter("需給改善", "youtube", "youtube", ""))
}

///|
test "insight_matches_filter: non-matching theme is filtered out" {
  assert_false(
    insight_matches_filter("半導体の需給", "x", "暗号資産", ""),
  )
}

///|
test "insight_matches_filter: source filter is exact" {
  assert_true(insight_matches_filter("s", "github", "", "github"))
  assert_false(insight_matches_filter("s", "github", "", "x"))
}

///|
test "insight_matches_filter: theme AND source must both match" {
  // theme matches summary, but source mismatches → excluded.
  assert_false(
    insight_matches_filter("ai-momentum", "youtube", "ai-momentum", "x"),
  )
  // both match → included.
  assert_true(
    insight_matches_filter("ai-momentum", "x", "ai-momentum", "x"),
  )
}

// ── operation validation ──────────────────────────────────────────────────────

///|
test "validate_adopt_insight: missing sourceUrl is rejected" {
  assert_eq(
    validate_adopt_insight("MANUAL_OPERATION", ""),
    "根拠リンクがないため採用できません",
  )
}

///|
test "validate_adopt_insight: missing reason code is rejected" {
  assert_eq(
    validate_adopt_insight("", "https://example.com/x"),
    "理由コードを選択してください",
  )
}

///|
test "validate_adopt_insight: valid input passes" {
  assert_eq(
    validate_adopt_insight("MANUAL_OPERATION", "https://example.com/x"),
    "",
  )
}

///|
test "validate_reject_insight: missing reason code is rejected" {
  assert_eq(validate_reject_insight(""), "却下理由コードを選択してください")
}

///|
test "validate_reject_insight: valid input passes" {
  assert_eq(validate_reject_insight("MODEL_REVIEW_DECISION"), "")
}

///|
test "validate_hypothesize_insight: missing reason code is rejected" {
  assert_eq(
    validate_hypothesize_insight(""),
    "理由コードを選択してください",
  )
}

///|
test "validate_hypothesize_insight: valid input passes" {
  assert_eq(validate_hypothesize_insight("MANUAL_OPERATION"), "")
}

// ── score formatting ──────────────────────────────────────────────────────────

///|
test "format_so_what_score: two fraction digits" {
  assert_eq(format_so_what_score(0.8), "0.80")
  assert_eq(format_so_what_score(0.785), "0.79")
}
