"""Tests for domain enum types."""

from enum import Enum


class TestSourceStatusValue:
    def test_has_ok_member(self) -> None:
        from src.domain.value_object.enums import SourceStatusValue

        assert SourceStatusValue.OK.value == "ok"

    def test_has_failed_member(self) -> None:
        from src.domain.value_object.enums import SourceStatusValue

        assert SourceStatusValue.FAILED.value == "failed"

    def test_is_enum(self) -> None:
        from src.domain.value_object.enums import SourceStatusValue

        assert issubclass(SourceStatusValue, Enum)

    def test_has_exactly_two_members(self) -> None:
        from src.domain.value_object.enums import SourceStatusValue

        assert len(SourceStatusValue) == 2


class TestFeatureGenerationStatus:
    def test_has_pending_member(self) -> None:
        from src.domain.value_object.enums import FeatureGenerationStatus

        assert FeatureGenerationStatus.PENDING.value == "pending"

    def test_has_generated_member(self) -> None:
        from src.domain.value_object.enums import FeatureGenerationStatus

        assert FeatureGenerationStatus.GENERATED.value == "generated"

    def test_has_failed_member(self) -> None:
        from src.domain.value_object.enums import FeatureGenerationStatus

        assert FeatureGenerationStatus.FAILED.value == "failed"

    def test_has_exactly_three_members(self) -> None:
        from src.domain.value_object.enums import FeatureGenerationStatus

        assert len(FeatureGenerationStatus) == 3


class TestDispatchStatus:
    def test_has_pending_member(self) -> None:
        from src.domain.value_object.enums import DispatchStatus

        assert DispatchStatus.PENDING.value == "pending"

    def test_has_published_member(self) -> None:
        from src.domain.value_object.enums import DispatchStatus

        assert DispatchStatus.PUBLISHED.value == "published"

    def test_has_failed_member(self) -> None:
        from src.domain.value_object.enums import DispatchStatus

        assert DispatchStatus.FAILED.value == "failed"

    def test_has_exactly_three_members(self) -> None:
        from src.domain.value_object.enums import DispatchStatus

        assert len(DispatchStatus) == 3


class TestPublishedEventType:
    def test_has_features_generated_member(self) -> None:
        from src.domain.value_object.enums import PublishedEventType

        assert PublishedEventType.FEATURES_GENERATED.value == "features.generated"

    def test_has_features_generation_failed_member(self) -> None:
        from src.domain.value_object.enums import PublishedEventType

        assert PublishedEventType.FEATURES_GENERATION_FAILED.value == "features.generation.failed"

    def test_has_exactly_two_members(self) -> None:
        from src.domain.value_object.enums import PublishedEventType

        assert len(PublishedEventType) == 2


class TestReasonCode:
    def test_has_request_validation_failed(self) -> None:
        from src.domain.value_object.enums import ReasonCode

        assert ReasonCode.REQUEST_VALIDATION_FAILED.value == "REQUEST_VALIDATION_FAILED"

    def test_has_dependency_unavailable(self) -> None:
        from src.domain.value_object.enums import ReasonCode

        assert ReasonCode.DEPENDENCY_UNAVAILABLE.value == "DEPENDENCY_UNAVAILABLE"

    def test_has_data_quality_leak_detected(self) -> None:
        from src.domain.value_object.enums import ReasonCode

        assert ReasonCode.DATA_QUALITY_LEAK_DETECTED.value == "DATA_QUALITY_LEAK_DETECTED"

    def test_has_data_schema_invalid(self) -> None:
        from src.domain.value_object.enums import ReasonCode

        assert ReasonCode.DATA_SCHEMA_INVALID.value == "DATA_SCHEMA_INVALID"

    def test_has_feature_generation_failed(self) -> None:
        from src.domain.value_object.enums import ReasonCode

        assert ReasonCode.FEATURE_GENERATION_FAILED.value == "FEATURE_GENERATION_FAILED"

    def test_has_idempotency_duplicate_event(self) -> None:
        from src.domain.value_object.enums import ReasonCode

        assert ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT.value == "IDEMPOTENCY_DUPLICATE_EVENT"

    def test_has_state_conflict(self) -> None:
        from src.domain.value_object.enums import ReasonCode

        assert ReasonCode.STATE_CONFLICT.value == "STATE_CONFLICT"

    def test_has_dispatch_failed(self) -> None:
        from src.domain.value_object.enums import ReasonCode

        assert ReasonCode.DISPATCH_FAILED.value == "DISPATCH_FAILED"

    def test_has_exactly_eight_members(self) -> None:
        from src.domain.value_object.enums import ReasonCode

        assert len(ReasonCode) == 8
