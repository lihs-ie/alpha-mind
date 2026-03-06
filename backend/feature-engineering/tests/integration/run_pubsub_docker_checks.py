"""Docker-based integration checks for feature-engineering Pub/Sub flows."""

from __future__ import annotations

import base64
import contextlib
import http.client
import http.server
import json
import random
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

PROJECT_ID = "alpha-mind-local"
PUBSUB_URL = "http://localhost:8085"
FIRESTORE_URL = f"http://localhost:8080/v1/projects/{PROJECT_ID}/databases/(default)/documents"
FEATURE_ENGINEERING_URL = "http://localhost:3003"
DOCKER_DIR = Path(__file__).resolve().parents[4] / "docker"


class IntegrationError(Exception):
    """Raised when an integration assertion fails."""


def main() -> None:
    """Start the Docker stack, run FE-IT-002..005, and tear the stack down."""
    _compose("up", "-d", "--build", "firestore", "pubsub", "gcs", "init", "feature-engineering")
    try:
        _wait_for_http_ok(f"{FEATURE_ENGINEERING_URL}/healthz", timeout_seconds=180)
        _wait_for_pubsub_topic("event-market-collected-v1", timeout_seconds=60)
        _run_pubsub_retry_and_dlq_checks()
        _run_fe_it_002()
        _run_fe_it_003()
        _run_fe_it_004()
        _run_fe_it_005()
        print("FE-IT-002..005 passed")
    finally:
        _compose("down", "--remove-orphans")


def _run_fe_it_002() -> None:
    """FE-IT-002: publish to market topic and receive features.generated."""
    identifier = _new_ulid_like()
    trace = _new_ulid_like()
    subscription_name = f"sub-it-fe-generated-{identifier.lower()}"
    _create_pull_subscription(subscription_name, "event-features-generated-v1")

    _publish_event(
        "event-market-collected-v1",
        {
            "identifier": identifier,
            "eventType": "market.collected",
            "occurredAt": "2026-03-05T00:10:00Z",
            "trace": trace,
            "schemaVersion": "1.0.0",
            "payload": {
                "targetDate": "2026-03-05",
                "storagePath": "gs://alpha-mind-raw-market-data-local/market/2026-03-05.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
        },
    )

    messages = _collect_messages(subscription_name, timeout_seconds=30)
    _assert(len(messages) == 1, f"FE-IT-002 expected 1 generated message, got {len(messages)}")
    envelope = messages[0]
    _assert(envelope["eventType"] == "features.generated", "FE-IT-002 eventType mismatch")
    _assert(envelope["trace"] == trace, "FE-IT-002 trace mismatch")

    generation = _get_firestore_document("feature_generations", identifier)
    dispatch = _get_firestore_document("feature_dispatches", identifier)
    outbox_entry = _get_firestore_document("feature_dispatch_outbox", identifier)
    _assert(_field(generation, "status") == "generated", "FE-IT-002 generation status mismatch")
    _assert(_field(dispatch, "dispatchStatus") == "published", "FE-IT-002 dispatch status mismatch")
    _assert(_field(outbox_entry, "status") == "published", "FE-IT-002 outbox status mismatch")


def _run_fe_it_003() -> None:
    """FE-IT-003: missing storagePath must emit features.generation.failed and persist failed state."""
    identifier = _new_ulid_like()
    trace = _new_ulid_like()
    subscription_name = f"sub-it-fe-failed-{identifier.lower()}"
    _create_pull_subscription(subscription_name, "event-features-generation-failed-v1")

    _publish_event(
        "event-market-collected-v1",
        {
            "identifier": identifier,
            "eventType": "market.collected",
            "occurredAt": "2026-03-05T00:11:00Z",
            "trace": trace,
            "schemaVersion": "1.0.0",
            "payload": {
                "targetDate": "2026-03-05",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
        },
    )

    messages = _collect_messages(subscription_name, timeout_seconds=30)
    _assert(len(messages) == 1, f"FE-IT-003 expected 1 failed message, got {len(messages)}")
    envelope = messages[0]
    payload = envelope["payload"]
    _assert(envelope["eventType"] == "features.generation.failed", "FE-IT-003 eventType mismatch")
    _assert(envelope["trace"] == trace, "FE-IT-003 trace mismatch")
    _assert(payload["reasonCode"] == "REQUEST_VALIDATION_FAILED", "FE-IT-003 reasonCode mismatch")

    generation = _get_firestore_document("feature_generations", identifier)
    dispatch = _get_firestore_document("feature_dispatches", identifier)
    outbox_entry = _get_firestore_document("feature_dispatch_outbox", identifier)
    _assert(_field(generation, "status") == "failed", "FE-IT-003 generation status mismatch")
    _assert(_field(dispatch, "dispatchStatus") == "published", "FE-IT-003 dispatch status mismatch")
    _assert(_field(outbox_entry, "status") == "published", "FE-IT-003 outbox status mismatch")


def _run_fe_it_004() -> None:
    """FE-IT-004: duplicate deliveries must not emit duplicate generated events."""
    identifier = _new_ulid_like()
    trace = _new_ulid_like()
    subscription_name = f"sub-it-fe-dup-{identifier.lower()}"
    envelope = {
        "identifier": identifier,
        "eventType": "market.collected",
        "occurredAt": "2026-03-05T00:12:00Z",
        "trace": trace,
        "schemaVersion": "1.0.0",
        "payload": {
            "targetDate": "2026-03-05",
            "storagePath": "gs://alpha-mind-raw-market-data-local/market/2026-03-05.parquet",
            "sourceStatus": {"jp": "ok", "us": "ok"},
        },
    }
    _create_pull_subscription(subscription_name, "event-features-generated-v1")

    _publish_event("event-market-collected-v1", envelope)
    _publish_event("event-market-collected-v1", envelope)

    messages = _collect_messages(subscription_name, timeout_seconds=30)
    _assert(len(messages) == 1, f"FE-IT-004 expected 1 generated message, got {len(messages)}")
    _assert(messages[0]["identifier"] == identifier, "FE-IT-004 identifier mismatch")

    idempotency = _get_firestore_document("idempotency_keys", f"feature-engineering:{identifier}")
    _assert(_field(idempotency, "processedAt") is not None, "FE-IT-004 processedAt missing")


def _run_pubsub_retry_and_dlq_checks() -> None:
    """Verify push subscription policy and runtime retry behaviour."""
    subscription = _get_pubsub_subscription("sub-feature-engineering-event-market-collected-v1")
    dead_letter_policy = subscription.get("deadLetterPolicy")
    retry_policy = subscription.get("retryPolicy")
    _assert(isinstance(dead_letter_policy, dict), "Pub/Sub subscription must include deadLetterPolicy")
    _assert(isinstance(retry_policy, dict), "Pub/Sub subscription must include retryPolicy")
    _assert(int(dead_letter_policy["maxDeliveryAttempts"]) >= 3, "Pub/Sub maxDeliveryAttempts must be at least 3")
    _assert(retry_policy["minimumBackoff"] == "10s", "Pub/Sub minimumBackoff mismatch")
    _assert(retry_policy["maximumBackoff"] == "600s", "Pub/Sub maximumBackoff mismatch")

    with _retry_probe_server(port=3099) as probe:
        retry_topic = "event-it-retry-probe-v1"
        retry_subscription = "sub-it-retry-probe-v1"
        retry_dlq_topic = "dlq-it-retry-probe-v1"
        _create_topic(retry_topic)
        _create_topic(retry_dlq_topic)
        _create_push_subscription_with_dlq(
            subscription_name=retry_subscription,
            topic_name=retry_topic,
            push_endpoint="http://host.docker.internal:3099/fail-three-then-ok",
            dead_letter_topic_name=retry_dlq_topic,
            max_delivery_attempts=5,
            minimum_backoff="1s",
            maximum_backoff="2s",
        )
        _publish_raw_message(retry_topic, {"probe": "retry"})
        _wait_for_probe_attempts(probe, "/fail-three-then-ok", expected_attempts=4, timeout_seconds=30)
        _assert_probe_attempts_stable(probe, "/fail-three-then-ok", expected_attempts=4, quiet_seconds=5)


def _run_fe_it_005() -> None:
    """FE-IT-005: generated event must preserve the input trace."""
    identifier = _new_ulid_like()
    trace = _new_ulid_like()
    subscription_name = f"sub-it-fe-trace-{identifier.lower()}"
    _create_pull_subscription(subscription_name, "event-features-generated-v1")

    _publish_event(
        "event-market-collected-v1",
        {
            "identifier": identifier,
            "eventType": "market.collected",
            "occurredAt": "2026-03-05T00:13:00Z",
            "trace": trace,
            "schemaVersion": "1.0.0",
            "payload": {
                "targetDate": "2026-03-05",
                "storagePath": "gs://alpha-mind-raw-market-data-local/market/2026-03-05.parquet",
                "sourceStatus": {"jp": "ok", "us": "ok"},
            },
        },
    )

    messages = _collect_messages(subscription_name, timeout_seconds=30)
    _assert(len(messages) == 1, f"FE-IT-005 expected 1 generated message, got {len(messages)}")
    _assert(messages[0]["trace"] == trace, "FE-IT-005 trace mismatch")


def _compose(*args: str) -> None:
    """Run a docker compose command in the project docker directory."""
    command = ["docker", "compose", "--env-file", ".env.local", "-f", "docker-compose.yml", *args]
    subprocess.run(command, cwd=DOCKER_DIR, check=True)


def _wait_for_http_ok(url: str, timeout_seconds: int) -> None:
    """Poll an HTTP endpoint until it returns 200."""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=5) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, http.client.RemoteDisconnected, ConnectionResetError):
            time.sleep(2)
            continue
        time.sleep(2)
    raise IntegrationError(f"Timed out waiting for {url}")


def _wait_for_pubsub_topic(topic_name: str, timeout_seconds: int) -> None:
    """Wait until the Pub/Sub emulator exposes the expected topic."""
    deadline = time.time() + timeout_seconds
    topic_url = f"{PUBSUB_URL}/v1/projects/{PROJECT_ID}/topics/{topic_name}"
    while time.time() < deadline:
        request = urllib.request.Request(topic_url, method="GET")
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                if response.status == 200:
                    return
        except urllib.error.URLError:
            time.sleep(2)
            continue
        time.sleep(2)
    raise IntegrationError(f"Timed out waiting for topic {topic_name}")


def _create_pull_subscription(subscription_name: str, topic_name: str) -> None:
    """Create a pull subscription for the integration test."""
    url = f"{PUBSUB_URL}/v1/projects/{PROJECT_ID}/subscriptions/{subscription_name}"
    payload = {
        "topic": f"projects/{PROJECT_ID}/topics/{topic_name}",
        "ackDeadlineSeconds": 60,
    }
    _request_json(url, payload, method="PUT")


def _create_push_subscription_with_dlq(
    *,
    subscription_name: str,
    topic_name: str,
    push_endpoint: str,
    dead_letter_topic_name: str,
    max_delivery_attempts: int,
    minimum_backoff: str,
    maximum_backoff: str,
) -> None:
    """Create a push subscription with retry and DLQ policy."""
    url = f"{PUBSUB_URL}/v1/projects/{PROJECT_ID}/subscriptions/{subscription_name}"
    payload = {
        "topic": f"projects/{PROJECT_ID}/topics/{topic_name}",
        "ackDeadlineSeconds": 60,
        "messageRetentionDuration": "604800s",
        "deadLetterPolicy": {
            "deadLetterTopic": f"projects/{PROJECT_ID}/topics/{dead_letter_topic_name}",
            "maxDeliveryAttempts": max_delivery_attempts,
        },
        "retryPolicy": {
            "minimumBackoff": minimum_backoff,
            "maximumBackoff": maximum_backoff,
        },
        "pushConfig": {
            "pushEndpoint": push_endpoint,
        },
    }
    _request_json(url, payload, method="PUT")


def _create_topic(topic_name: str) -> None:
    """Create one Pub/Sub topic."""
    request = urllib.request.Request(
        f"{PUBSUB_URL}/v1/projects/{PROJECT_ID}/topics/{topic_name}",
        method="PUT",
    )
    with urllib.request.urlopen(request, timeout=10):
        return


def _publish_event(topic_name: str, envelope: dict[str, Any]) -> None:
    """Publish one envelope to a Pub/Sub topic."""
    url = f"{PUBSUB_URL}/v1/projects/{PROJECT_ID}/topics/{topic_name}:publish"
    data = base64.b64encode(json.dumps(envelope).encode("utf-8")).decode("utf-8")
    _request_json(url, {"messages": [{"data": data}]})


def _publish_raw_message(topic_name: str, payload: dict[str, Any]) -> None:
    """Publish a plain JSON payload to a Pub/Sub topic."""
    url = f"{PUBSUB_URL}/v1/projects/{PROJECT_ID}/topics/{topic_name}:publish"
    data = base64.b64encode(json.dumps(payload).encode("utf-8")).decode("utf-8")
    _request_json(url, {"messages": [{"data": data}]})


def _collect_messages(subscription_name: str, timeout_seconds: int) -> list[dict[str, Any]]:
    """Pull and ack messages until a quiet window is observed."""
    deadline = time.time() + timeout_seconds
    messages: list[dict[str, Any]] = []
    last_received_at: float | None = None

    while time.time() < deadline:
        batch = _pull_messages(subscription_name)
        if batch:
            last_received_at = time.time()
            messages.extend(batch)
            continue
        if last_received_at is not None and time.time() - last_received_at >= 3:
            return messages
        time.sleep(1)

    return messages


def _pull_messages(subscription_name: str) -> list[dict[str, Any]]:
    """Pull up to 10 messages and acknowledge them immediately."""
    url = f"{PUBSUB_URL}/v1/projects/{PROJECT_ID}/subscriptions/{subscription_name}:pull"
    try:
        response = _request_json(url, {"maxMessages": 10})
    except (OSError, urllib.error.URLError, http.client.RemoteDisconnected):
        return []
    received_messages = response.get("receivedMessages", [])
    if not isinstance(received_messages, list) or not received_messages:
        return []

    ack_ids: list[str] = []
    envelopes: list[dict[str, Any]] = []
    for message in received_messages:
        ack_id = message["ackId"]
        raw_data = message["message"]["data"]
        ack_ids.append(ack_id)
        decoded = base64.b64decode(raw_data).decode("utf-8")
        envelopes.append(json.loads(decoded))

    _ack_messages(subscription_name, ack_ids)
    return envelopes


def _ack_messages(subscription_name: str, ack_ids: list[str]) -> None:
    """Acknowledge a batch of Pub/Sub messages."""
    url = f"{PUBSUB_URL}/v1/projects/{PROJECT_ID}/subscriptions/{subscription_name}:acknowledge"
    _request_json(url, {"ackIds": ack_ids})


def _get_firestore_document(collection_name: str, document_id: str) -> dict[str, Any]:
    """Load and decode a Firestore REST document."""
    encoded_id = urllib.parse.quote(document_id, safe="")
    url = f"{FIRESTORE_URL}/{collection_name}/{encoded_id}"
    request = urllib.request.Request(url, method="GET")
    with urllib.request.urlopen(request, timeout=5) as response:
        raw = json.loads(response.read().decode("utf-8"))
    fields = raw.get("fields", {})
    if not isinstance(fields, dict):
        raise IntegrationError(f"Unexpected Firestore fields for {collection_name}/{document_id}")
    return {key: _decode_firestore_value(value) for key, value in fields.items()}


def _get_pubsub_subscription(subscription_name: str) -> dict[str, Any]:
    """Load one Pub/Sub subscription."""
    request = urllib.request.Request(
        f"{PUBSUB_URL}/v1/projects/{PROJECT_ID}/subscriptions/{subscription_name}",
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def _decode_firestore_value(value: dict[str, Any]) -> Any:
    """Decode a Firestore REST value object into a plain Python value."""
    if "stringValue" in value:
        return value["stringValue"]
    if "booleanValue" in value:
        return value["booleanValue"]
    if "integerValue" in value:
        return int(value["integerValue"])
    if "timestampValue" in value:
        return value["timestampValue"]
    if "nullValue" in value:
        return None
    if "mapValue" in value:
        fields = value["mapValue"].get("fields", {})
        return {key: _decode_firestore_value(field_value) for key, field_value in fields.items()}
    raise IntegrationError(f"Unsupported Firestore value: {value}")


def _field(document: dict[str, Any], field_name: str) -> Any:
    """Return one decoded field from a decoded Firestore document."""
    return document.get(field_name)


def _request_json(url: str, payload: dict[str, Any], method: str = "POST") -> dict[str, Any]:
    """Send a JSON request and decode the JSON response body."""
    body = json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json"},
        method=method,
    )
    with urllib.request.urlopen(request, timeout=10) as response:
        response_body = response.read()
    if not response_body:
        return {}
    return json.loads(response_body.decode("utf-8"))


def _new_ulid_like() -> str:
    """Generate a Crockford-base32 identifier suitable for tests."""
    alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    return "".join(random.choice(alphabet) for _ in range(26))


def _assert(condition: bool, message: str) -> None:
    """Raise IntegrationError when a condition is false."""
    if not condition:
        raise IntegrationError(message)


class RetryProbeState:
    """In-process HTTP probe state for Pub/Sub retry checks."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.attempts: dict[str, int] = {}

    def record_attempt(self, path: str) -> int:
        """Record one attempt for a path and return the updated count."""
        with self._lock:
            next_attempt = self.attempts.get(path, 0) + 1
            self.attempts[path] = next_attempt
            return next_attempt

    def count(self, path: str) -> int:
        """Return the current attempt count for a path."""
        with self._lock:
            return self.attempts.get(path, 0)


@contextlib.contextmanager
def _retry_probe_server(port: int) -> Any:
    """Run a lightweight HTTP server for retry/DLQ tests."""
    state = RetryProbeState()

    class RetryProbeHandler(http.server.BaseHTTPRequestHandler):
        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length", "0"))
            self.rfile.read(length)
            attempt = state.record_attempt(self.path)
            if self.path == "/fail-three-then-ok" and attempt >= 4:
                self.send_response(204)
                self.end_headers()
                return
            self.send_response(503)
            self.end_headers()

        def log_message(self, format: str, *args: object) -> None:
            return

    server = http.server.ThreadingHTTPServer(("0.0.0.0", port), RetryProbeHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield state
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def _wait_for_probe_attempts(
    probe: RetryProbeState,
    path: str,
    expected_attempts: int,
    timeout_seconds: int,
) -> None:
    """Wait until the retry probe observes at least the expected attempt count."""
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if probe.count(path) >= expected_attempts:
            return
        time.sleep(1)
    raise IntegrationError(
        f"Timed out waiting for {path} attempts: expected {expected_attempts}, got {probe.count(path)}"
    )


def _assert_probe_attempts_stable(
    probe: RetryProbeState,
    path: str,
    expected_attempts: int,
    quiet_seconds: int,
) -> None:
    """Ensure the probe stops retrying after the expected number of attempts."""
    time.sleep(quiet_seconds)
    actual_attempts = probe.count(path)
    _assert(
        actual_attempts == expected_attempts,
        f"Expected {path} to stop at {expected_attempts} attempts, got {actual_attempts}",
    )


if __name__ == "__main__":
    main()
