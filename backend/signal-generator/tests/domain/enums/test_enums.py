"""Tests for domain enums: ReasonCode, DegradationFlag, ModelStatus, EventType."""

from signal_generator.domain.enums.degradation_flag import DegradationFlag
from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.enums.reason_code import ReasonCode


class TestReasonCode:
    def test_model_not_approved_exists(self) -> None:
        assert ReasonCode.MODEL_NOT_APPROVED.value == "MODEL_NOT_APPROVED"

    def test_signal_generation_failed_exists(self) -> None:
        assert ReasonCode.SIGNAL_GENERATION_FAILED.value == "SIGNAL_GENERATION_FAILED"

    def test_request_validation_failed_exists(self) -> None:
        assert ReasonCode.REQUEST_VALIDATION_FAILED.value == "REQUEST_VALIDATION_FAILED"

    def test_dependency_timeout_exists(self) -> None:
        assert ReasonCode.DEPENDENCY_TIMEOUT.value == "DEPENDENCY_TIMEOUT"

    def test_dependency_unavailable_exists(self) -> None:
        assert ReasonCode.DEPENDENCY_UNAVAILABLE.value == "DEPENDENCY_UNAVAILABLE"

    def test_idempotency_duplicate_event_exists(self) -> None:
        assert ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT.value == "IDEMPOTENCY_DUPLICATE_EVENT"

    def test_state_conflict_exists(self) -> None:
        assert ReasonCode.STATE_CONFLICT.value == "STATE_CONFLICT"

    def test_reason_codes_are_strings(self) -> None:
        for reason_code in ReasonCode:
            assert isinstance(reason_code.value, str)

    def test_non_retryable_reason_codes(self) -> None:
        # MODEL_NOT_APPROVED と REQUEST_VALIDATION_FAILED は再試行しない
        assert ReasonCode.MODEL_NOT_APPROVED in ReasonCode.non_retryable()
        assert ReasonCode.REQUEST_VALIDATION_FAILED in ReasonCode.non_retryable()

    def test_retryable_reason_codes(self) -> None:
        # DEPENDENCY_TIMEOUT と DEPENDENCY_UNAVAILABLE は再試行する
        assert ReasonCode.DEPENDENCY_TIMEOUT in ReasonCode.retryable()
        assert ReasonCode.DEPENDENCY_UNAVAILABLE in ReasonCode.retryable()


class TestDegradationFlag:
    def test_normal_exists(self) -> None:
        assert DegradationFlag.NORMAL.value == "normal"

    def test_warn_exists(self) -> None:
        assert DegradationFlag.WARN.value == "warn"

    def test_block_exists(self) -> None:
        assert DegradationFlag.BLOCK.value == "block"

    def test_block_requires_compliance_review(self) -> None:
        # RULE-SG-007: block フラグは必ずコンプライアンスレビューを要求する
        assert DegradationFlag.BLOCK.requires_compliance_review() is True

    def test_normal_does_not_require_compliance_review(self) -> None:
        assert DegradationFlag.NORMAL.requires_compliance_review() is False

    def test_warn_does_not_require_compliance_review(self) -> None:
        assert DegradationFlag.WARN.requires_compliance_review() is False


class TestModelStatus:
    def test_candidate_exists(self) -> None:
        assert ModelStatus.CANDIDATE.value == "candidate"

    def test_approved_exists(self) -> None:
        assert ModelStatus.APPROVED.value == "approved"

    def test_rejected_exists(self) -> None:
        assert ModelStatus.REJECTED.value == "rejected"

    def test_only_approved_is_usable_for_inference(self) -> None:
        # RULE-SG-002: approved モデルのみ推論に利用できる
        assert ModelStatus.APPROVED.is_usable_for_inference() is True
        assert ModelStatus.CANDIDATE.is_usable_for_inference() is False
        assert ModelStatus.REJECTED.is_usable_for_inference() is False


class TestEventType:
    def test_signal_generation_started_exists(self) -> None:
        assert EventType.SIGNAL_GENERATION_STARTED.value == "signal.generation.started"

    def test_signal_generation_completed_exists(self) -> None:
        assert EventType.SIGNAL_GENERATION_COMPLETED.value == "signal.generation.completed"

    def test_signal_generation_failed_exists(self) -> None:
        assert EventType.SIGNAL_GENERATION_FAILED.value == "signal.generation.failed"

    def test_signal_generated_exists(self) -> None:
        assert EventType.SIGNAL_GENERATED.value == "signal.generated"

    def test_event_types_are_strings(self) -> None:
        for event_type in EventType:
            assert isinstance(event_type.value, str)


class TestGenerationStatus:
    def test_pending_exists(self) -> None:
        assert GenerationStatus.PENDING.value == "pending"

    def test_generated_exists(self) -> None:
        assert GenerationStatus.GENERATED.value == "generated"

    def test_failed_exists(self) -> None:
        assert GenerationStatus.FAILED.value == "failed"

    def test_pending_is_not_terminal(self) -> None:
        assert GenerationStatus.PENDING.is_terminal() is False

    def test_generated_is_terminal(self) -> None:
        assert GenerationStatus.GENERATED.is_terminal() is True

    def test_failed_is_terminal(self) -> None:
        assert GenerationStatus.FAILED.is_terminal() is True


class TestDispatchStatus:
    def test_pending_exists(self) -> None:
        assert DispatchStatus.PENDING.value == "pending"

    def test_published_exists(self) -> None:
        assert DispatchStatus.PUBLISHED.value == "published"

    def test_failed_exists(self) -> None:
        assert DispatchStatus.FAILED.value == "failed"

    def test_pending_is_not_terminal(self) -> None:
        assert DispatchStatus.PENDING.is_terminal() is False

    def test_published_is_terminal(self) -> None:
        assert DispatchStatus.PUBLISHED.is_terminal() is True

    def test_failed_is_terminal(self) -> None:
        assert DispatchStatus.FAILED.is_terminal() is True
