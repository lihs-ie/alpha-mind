"""Feature Engineering service entrypoint."""

from __future__ import annotations

import base64
import datetime
import json
import os
import re
from collections.abc import Mapping
from dataclasses import dataclass

from flask import Flask, Response, request
from google.cloud.firestore_v1 import Client as FirestoreClient
from google.cloud.pubsub_v1 import PublisherClient
from google.cloud.storage import Client as StorageClient

from application.feature_generation_service import (
    EventEnvelope,
    FeatureGenerationService,
    FeatureProcessingError,
)
from domain.factory.feature_dispatch_factory import FeatureDispatchFactory
from domain.factory.feature_generation_factory import FeatureGenerationFactory
from domain.service.feature_leakage_policy import FeatureLeakagePolicy
from domain.service.feature_version_generator import FeatureVersionGenerator
from domain.service.point_in_time_join_policy import PointInTimeJoinPolicy
from domain.value_object.enums import ReasonCode
from infrastructure.messaging.pubsub.features_generated_publisher import FeaturesGeneratedPublisher
from infrastructure.messaging.pubsub.features_generation_failed_publisher import (
    FeaturesGenerationFailedPublisher,
)
from infrastructure.persistence.cloud_storage.cloud_storage_feature_artifact_repository import (
    CloudStorageFeatureArtifactRepository,
)
from infrastructure.persistence.firestore.firestore_feature_dispatch_outbox_repository import (
    FirestoreFeatureDispatchOutboxRepository,
)
from infrastructure.persistence.firestore.firestore_feature_dispatch_repository import (
    FirestoreFeatureDispatchRepository,
)
from infrastructure.persistence.firestore.firestore_feature_generation_repository import (
    FirestoreFeatureGenerationRepository,
)
from infrastructure.persistence.firestore.firestore_idempotency_key_repository import (
    FirestoreIdempotencyKeyRepository,
)
from infrastructure.persistence.firestore.firestore_insight_record_repository import (
    FirestoreInsightRecordRepository,
)

SERVICE_NAME = "feature-engineering"
EXPECTED_SCHEMA_VERSION = "1.0.0"
EXPECTED_EVENT_TYPE = "market.collected"
DEFAULT_TRACE = "00000000000000000000000000"
_ULID_PATTERN = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")


class InvalidEnvelopeError(FeatureProcessingError):
    """Raised when the Pub/Sub push envelope is malformed."""


@dataclass(frozen=True)
class ProblemDetail:
    """RFC 9457 Problem Details response body."""

    type: str
    title: str
    status: int
    reason_code: str
    trace: str
    retryable: bool
    detail: str | None = None

    def to_dict(self) -> dict[str, object]:
        """Convert to a JSON-serializable mapping."""
        body: dict[str, object] = {
            "type": self.type,
            "title": self.title,
            "status": self.status,
            "reasonCode": self.reason_code,
            "trace": self.trace,
            "retryable": self.retryable,
        }
        if self.detail is not None:
            body["detail"] = self.detail
        return body


class DailyFeatureVersionGenerator(FeatureVersionGenerator):
    """Generates a deterministic feature version per target date."""

    def generate(self, target_date: datetime.date) -> str:
        """Generate a stable feature version for the target date."""
        return f"v{target_date.strftime('%Y%m%d')}-001"


class PubSubPushDecoder:
    """Decodes and validates the Pub/Sub push request envelope."""

    def decode(self, raw_body: bytes) -> EventEnvelope:
        """Decode a Pub/Sub push request body into a normalized envelope."""
        try:
            request_body = json.loads(raw_body.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise self._invalid_envelope("Request body must be valid JSON.", DEFAULT_TRACE) from error

        if not isinstance(request_body, dict):
            raise self._invalid_envelope("Request body must be a JSON object.", DEFAULT_TRACE)

        trace = self._extract_trace(request_body)
        message = request_body.get("message")
        if not isinstance(message, dict):
            raise self._invalid_envelope("Pub/Sub push request must include message.", trace)

        encoded_data = message.get("data")
        if not isinstance(encoded_data, str) or not encoded_data:
            raise self._invalid_envelope("Pub/Sub message.data is required.", trace)

        try:
            envelope_bytes = base64.b64decode(encoded_data, validate=True)
            envelope_body = json.loads(envelope_bytes.decode("utf-8"))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise self._invalid_envelope("Pub/Sub message.data must be base64-encoded JSON.", trace) from error

        if not isinstance(envelope_body, dict):
            raise self._invalid_envelope("Event envelope must be a JSON object.", trace)

        identifier = self._require_ulid(envelope_body.get("identifier"), "identifier", trace)
        event_type = self._require_string(envelope_body.get("eventType"), "eventType", trace)
        if event_type != EXPECTED_EVENT_TYPE:
            raise self._invalid_envelope(f"eventType must be '{EXPECTED_EVENT_TYPE}'.", trace)

        occurred_at = self._parse_occurred_at(envelope_body.get("occurredAt"), trace)
        normalized_trace = self._require_ulid(envelope_body.get("trace"), "trace", trace)

        schema_version = self._require_string(envelope_body.get("schemaVersion"), "schemaVersion", normalized_trace)
        if schema_version != EXPECTED_SCHEMA_VERSION:
            raise self._invalid_envelope(
                f"schemaVersion must be '{EXPECTED_SCHEMA_VERSION}'.",
                normalized_trace,
            )

        payload = envelope_body.get("payload")
        if not isinstance(payload, dict):
            raise self._invalid_envelope("payload must be an object.", normalized_trace)

        return EventEnvelope(
            identifier=identifier,
            event_type=event_type,
            occurred_at=occurred_at,
            trace=normalized_trace,
            payload=payload,
        )

    def _extract_trace(self, request_body: Mapping[str, object]) -> str:
        """Best-effort extraction of trace for problem responses."""
        message = request_body.get("message")
        if not isinstance(message, dict):
            return DEFAULT_TRACE
        encoded_data = message.get("data")
        if not isinstance(encoded_data, str) or not encoded_data:
            return DEFAULT_TRACE
        # fmt: off
        try:
            envelope_bytes = base64.b64decode(encoded_data, validate=False)
            envelope_body = json.loads(envelope_bytes.decode("utf-8"))
        except (ValueError, UnicodeDecodeError, json.JSONDecodeError):
            return DEFAULT_TRACE
        # fmt: on
        if not isinstance(envelope_body, dict):
            return DEFAULT_TRACE
        trace = envelope_body.get("trace")
        if isinstance(trace, str) and _ULID_PATTERN.fullmatch(trace):
            return trace
        return DEFAULT_TRACE

    def _require_string(self, value: object, field_name: str, trace: str) -> str:
        """Require a non-empty string field."""
        if not isinstance(value, str) or not value:
            raise self._invalid_envelope(f"{field_name} must be a non-empty string.", trace)
        return value

    def _require_ulid(self, value: object, field_name: str, trace: str) -> str:
        """Require a ULID string field."""
        string_value = self._require_string(value, field_name, trace)
        if not _ULID_PATTERN.fullmatch(string_value):
            raise self._invalid_envelope(f"{field_name} must be a valid ULID.", trace)
        return string_value

    def _parse_occurred_at(self, value: object, trace: str) -> datetime.datetime:
        """Parse `occurredAt` as a UTC timestamp."""
        occurred_at_text = self._require_string(value, "occurredAt", trace)
        normalized = occurred_at_text.replace("Z", "+00:00")
        try:
            occurred_at = datetime.datetime.fromisoformat(normalized)
        except ValueError as error:
            raise self._invalid_envelope("occurredAt must be an ISO 8601 timestamp.", trace) from error
        if occurred_at.tzinfo is None:
            raise self._invalid_envelope("occurredAt must include a timezone offset.", trace)
        return occurred_at.astimezone(datetime.UTC)

    def _invalid_envelope(self, detail: str, trace: str) -> InvalidEnvelopeError:
        """Build a standardized invalid-envelope error."""
        return InvalidEnvelopeError(
            status=400,
            title="Bad Request",
            detail=detail,
            reason_code=ReasonCode.REQUEST_VALIDATION_FAILED,
            trace=trace,
            retryable=False,
        )


def create_app(service: FeatureGenerationService | None = None) -> Flask:
    """Create the Flask application."""
    app = Flask(__name__)
    decoder = PubSubPushDecoder()
    effective_service = service or _build_default_service()

    @app.get("/healthz")
    def healthz() -> tuple[str, int]:
        """Return the health status."""
        return "ok", 200

    @app.post("/")
    @app.post("/pubsub/push")
    def pubsub_push() -> Response:
        """Receive Pub/Sub push deliveries for `market.collected`."""
        try:
            envelope = decoder.decode(request.get_data())
            effective_service.process(envelope)
            return Response(status=204)
        except FeatureProcessingError as error:
            return _problem_response(error)

    return app


def _problem_response(error: FeatureProcessingError) -> Response:
    """Build an RFC 9457 response."""
    problem = ProblemDetail(
        type="about:blank",
        title=error.title,
        status=error.status,
        detail=error.detail,
        trace=error.trace,
        reason_code=error.reason_code.value,
        retryable=error.retryable,
    )
    return Response(
        response=json.dumps(problem.to_dict()),
        status=error.status,
        mimetype="application/problem+json",
    )


def _utcnow() -> datetime.datetime:
    """Return the current UTC time."""
    return datetime.datetime.now(datetime.UTC)


def _extract_bucket_name(feature_store_base_path: str) -> str:
    """Extract the bucket name from a `gs://` path."""
    if not feature_store_base_path.startswith("gs://"):
        raise ValueError("FEATURE_STORE_BASE_PATH must start with gs://")
    path_without_scheme = feature_store_base_path.removeprefix("gs://")
    bucket_name, _, _ = path_without_scheme.partition("/")
    if not bucket_name:
        raise ValueError("FEATURE_STORE_BASE_PATH must include a bucket name")
    return bucket_name


def _build_default_service() -> FeatureGenerationService:
    """Build the production service with Firestore, Storage, and Pub/Sub dependencies."""
    project_id = os.environ.get("GCP_PROJECT_ID", "alpha-mind-local")
    lease_seconds = int(os.environ.get("IDEMPOTENCY_LEASE_SECONDS", "300"))
    feature_store_base_path = os.environ.get(
        "FEATURE_STORE_BASE_PATH",
        "gs://alpha-mind-feature-store-local/features",
    )
    feature_store_bucket = os.environ.get("FEATURE_STORE_BUCKET", _extract_bucket_name(feature_store_base_path))

    firestore_client = FirestoreClient(project=project_id)
    storage_client = StorageClient(project=project_id)
    publisher_client = PublisherClient()

    generated_topic = os.environ.get("FEATURES_GENERATED_TOPIC", "event-features-generated-v1")
    failed_topic = os.environ.get("FEATURES_GENERATION_FAILED_TOPIC", "event-features-generation-failed-v1")

    return FeatureGenerationService(
        feature_generation_repository=FirestoreFeatureGenerationRepository(firestore_client),
        feature_dispatch_repository=FirestoreFeatureDispatchRepository(firestore_client),
        feature_dispatch_outbox_repository=FirestoreFeatureDispatchOutboxRepository(firestore_client),
        feature_artifact_repository=CloudStorageFeatureArtifactRepository(storage_client, feature_store_bucket),
        insight_record_repository=FirestoreInsightRecordRepository(firestore_client),
        idempotency_key_repository=FirestoreIdempotencyKeyRepository(firestore_client, SERVICE_NAME),
        features_generated_publisher=FeaturesGeneratedPublisher(
            publisher_client,
            publisher_client.topic_path(project_id, generated_topic),
        ),
        features_generation_failed_publisher=FeaturesGenerationFailedPublisher(
            publisher_client,
            publisher_client.topic_path(project_id, failed_topic),
        ),
        feature_generation_factory=FeatureGenerationFactory(DailyFeatureVersionGenerator()),
        feature_dispatch_factory=FeatureDispatchFactory(),
        point_in_time_join_policy=PointInTimeJoinPolicy(),
        feature_leakage_policy=FeatureLeakagePolicy(),
        feature_store_base_path=feature_store_base_path,
        lease_seconds=lease_seconds,
        clock=_utcnow,
    )


def main() -> None:
    """Run the Flask application."""
    port = int(os.environ.get("PORT", "8080"))
    app = create_app()
    app.run(host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
