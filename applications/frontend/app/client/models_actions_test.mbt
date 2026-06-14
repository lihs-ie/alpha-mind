///| Tests for the ModelValidationActions Island logic (SCR-005).
///| Verifies Props serialization, Model-Status state-machine gating (promote/reject),
///| promote/reject validation (reason code, comment length, degradation flag,
///| compliance review), and metric formatting (% / 0.00).

///|
test "ModelValidationRowProps round-trip ToJson/FromJson" {
  let row : ModelValidationRowProps = {
    model_version: "model-2026-01-15",
    status: "candidate",
    degradation_flag: "normal",
    created_at: "2026-01-15T09:00:00Z",
  }
  let json = row.to_json()
  let restored : ModelValidationRowProps = @json.from_json(json)
  assert_eq(row.model_version, restored.model_version)
  assert_eq(row.status, restored.status)
  assert_eq(row.degradation_flag, restored.degradation_flag)
  assert_eq(row.created_at, restored.created_at)
}

///|
test "ModelsActionsProps round-trip with multiple models" {
  let props : ModelsActionsProps = {
    bff_base_url: "https://api.alpha-mind.dev",
    initial_models: [
      {
        model_version: "model-a",
        status: "candidate",
        degradation_flag: "normal",
        created_at: "2026-01-15T09:00:00Z",
      },
      {
        model_version: "model-b",
        status: "approved",
        degradation_flag: "warn",
        created_at: "2026-01-16T09:00:00Z",
      },
    ],
  }
  let json = props.to_json()
  let restored : ModelsActionsProps = @json.from_json(json)
  assert_eq(restored.bff_base_url, "https://api.alpha-mind.dev")
  assert_eq(restored.initial_models.length(), 2)
  assert_eq(restored.initial_models[0].model_version, "model-a")
  assert_eq(restored.initial_models[1].status, "approved")
  assert_eq(restored.initial_models[1].degradation_flag, "warn")
}

// ── Model Status state machine (candidate → approved | rejected, terminal) ────

///|
test "can_promote_model only from candidate" {
  assert_true(can_promote_model("candidate"))
  assert_false(can_promote_model("approved"))
  assert_false(can_promote_model("rejected"))
  assert_false(can_promote_model(""))
}

///|
test "can_reject_model only from candidate" {
  assert_true(can_reject_model("candidate"))
  assert_false(can_reject_model("approved"))
  assert_false(can_reject_model("rejected"))
}

// ── Promote validation (SCR-005 §5) ───────────────────────────────────────────

///|
test "validate_promote_model accepts a valid candidate decision" {
  // reason set, comment within limit, flag != block, no compliance hold.
  assert_eq(
    validate_promote_model("MANUAL_OPERATION", "looks good", "normal", false),
    "",
  )
  assert_eq(validate_promote_model("MODEL_REVIEW_DECISION", "", "warn", false), "")
}

///|
test "validate_promote_model requires a reason code" {
  assert_eq(
    validate_promote_model("", "comment", "normal", false),
    "昇格理由コードを選択してください",
  )
}

///|
test "validate_promote_model rejects a comment over 120 chars" {
  let long_comment = "a".repeat(121)
  assert_eq(
    validate_promote_model("MANUAL_OPERATION", long_comment, "normal", false),
    "コメントは120文字以内で入力してください",
  )
  // exactly 120 is allowed.
  let max_comment = "a".repeat(120)
  assert_eq(
    validate_promote_model("MANUAL_OPERATION", max_comment, "normal", false),
    "",
  )
}

///|
test "validate_promote_model blocks promotion when degradationFlag=block" {
  assert_eq(
    validate_promote_model("MANUAL_OPERATION", "", "block", false),
    "直近性能劣化のため昇格できません",
  )
}

///|
test "validate_promote_model blocks promotion when compliance review required" {
  assert_eq(
    validate_promote_model("MANUAL_OPERATION", "", "normal", true),
    "コンプライアンスレビュー完了後に実行してください",
  )
}

// ── Reject validation (SCR-005 §5) ────────────────────────────────────────────

///|
test "validate_reject_model requires a reason code" {
  assert_eq(
    validate_reject_model("", "comment"),
    "差し戻し理由コードを選択してください",
  )
}

///|
test "validate_reject_model rejects a comment over 120 chars" {
  let long_comment = "b".repeat(121)
  assert_eq(
    validate_reject_model("RISK_REJECTION", long_comment),
    "コメントは120文字以内で入力してください",
  )
}

///|
test "validate_reject_model accepts a valid reject decision" {
  assert_eq(validate_reject_model("RISK_REJECTION", "not viable"), "")
  assert_eq(validate_reject_model("POLICY_COMPLIANCE_HOLD", ""), "")
}

// ── Metric formatting (F-0053..F-0060) ────────────────────────────────────────

///|
test "format_percent_metric renders 2-decimal percent" {
  assert_eq(format_percent_metric(12.345), "12.35%")
  assert_eq(format_percent_metric(0.0), "0.00%")
  assert_eq(format_percent_metric(-3.2), "-3.20%")
}

///|
test "format_ratio_metric renders 2-decimal ratio" {
  assert_eq(format_ratio_metric(1.5), "1.50")
  assert_eq(format_ratio_metric(0.0), "0.00")
  assert_eq(format_ratio_metric(2.718), "2.72")
}
