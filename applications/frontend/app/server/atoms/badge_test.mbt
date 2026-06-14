///| Tests for the badge and status_badge atoms.

///|
test "badge_atom renders a span with the label" {
  let html = @server_dom.render(badge_atom("NEW"))
  assert_true(html.contains("<span"))
  assert_true(html.contains("NEW"))
  assert_true(html.contains("border-radius:9999px"))
}

///|
test "badge_atom Success variant uses the CTA accent" {
  let html = @server_dom.render(badge_atom("OK", variant=Success))
  assert_true(html.contains("--color-cta"))
}

///|
test "badge_atom Danger variant uses the danger colour" {
  let html = @server_dom.render(badge_atom("NG", variant=Danger))
  assert_true(html.contains("248,113,113"))
}

///|
test "status_badge_meta maps order statuses to variant + label" {
  let (proposed_variant, proposed_label) = status_badge_meta("PROPOSED")
  assert_true(proposed_variant is Info)
  assert_eq(proposed_label, "提案中")
  let (approved_variant, approved_label) = status_badge_meta("APPROVED")
  assert_true(approved_variant is Success)
  assert_eq(approved_label, "承認済み")
  let (rejected_variant, _) = status_badge_meta("REJECTED")
  assert_true(rejected_variant is Danger)
  let (failed_variant, _) = status_badge_meta("FAILED")
  assert_true(failed_variant is Danger)
  let (executed_variant, _) = status_badge_meta("EXECUTED")
  assert_true(executed_variant is Success)
}

///|
test "status_badge_meta maps model statuses (lowercase)" {
  let (candidate_variant, candidate_label) = status_badge_meta("candidate")
  assert_true(candidate_variant is Info)
  assert_eq(candidate_label, "候補")
  let (approved_variant, _) = status_badge_meta("approved")
  assert_true(approved_variant is Success)
}

///|
test "status_badge_meta maps runtime and kill-switch states" {
  let (running_variant, running_label) = status_badge_meta("RUNNING")
  assert_true(running_variant is Success)
  assert_eq(running_label, "稼働中")
  let (stopped_variant, _) = status_badge_meta("STOPPED")
  assert_true(stopped_variant is Neutral)
  let (enabled_variant, _) = status_badge_meta("ENABLED")
  assert_true(enabled_variant is Warning)
  let (disabled_variant, _) = status_badge_meta("DISABLED")
  assert_true(disabled_variant is Neutral)
}

///|
test "status_badge_meta falls back to Neutral + raw label for unknown status" {
  let (variant, display) = status_badge_meta("WHATEVER")
  assert_true(variant is Neutral)
  assert_eq(display, "WHATEVER")
}

///|
test "status_badge_atom always renders a text label (not colour alone)" {
  let html = @server_dom.render(status_badge_atom("PROPOSED"))
  // Accessibility §9: status conveyed by text, not colour alone.
  assert_true(html.contains("提案中"))
}
