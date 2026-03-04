"""Domain enum types for feature-engineering bounded context."""

from enum import Enum


class SourceStatusValue(Enum):
    """Market data source collection status."""

    OK = "ok"
    FAILED = "failed"


class FeatureGenerationStatus(Enum):
    """Lifecycle status of a feature generation run."""

    PENDING = "pending"
    GENERATED = "generated"
    FAILED = "failed"


class DispatchStatus(Enum):
    """Lifecycle status of a feature dispatch."""

    PENDING = "pending"
    PUBLISHED = "published"
    FAILED = "failed"


class PublishedEventType(Enum):
    """Integration event types published by feature-engineering."""

    FEATURES_GENERATED = "features.generated"
    FEATURES_GENERATION_FAILED = "features.generation.failed"


class ReasonCode(Enum):
    """Failure reason codes for feature generation and dispatch."""

    REQUEST_VALIDATION_FAILED = "REQUEST_VALIDATION_FAILED"
    DEPENDENCY_UNAVAILABLE = "DEPENDENCY_UNAVAILABLE"
    DATA_QUALITY_LEAK_DETECTED = "DATA_QUALITY_LEAK_DETECTED"
    DATA_SCHEMA_INVALID = "DATA_SCHEMA_INVALID"
    FEATURE_GENERATION_FAILED = "FEATURE_GENERATION_FAILED"
    IDEMPOTENCY_DUPLICATE_EVENT = "IDEMPOTENCY_DUPLICATE_EVENT"
    STATE_CONFLICT = "STATE_CONFLICT"
    DISPATCH_FAILED = "DISPATCH_FAILED"
