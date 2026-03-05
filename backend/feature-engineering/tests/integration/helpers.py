"""Shared constants and helper functions for integration tests."""

from __future__ import annotations

import base64
import contextlib
import json
import time
from typing import Any

from google.cloud.pubsub_v1 import SubscriberClient  # type: ignore[attr-defined]

PROJECT_ID = "alpha-mind-local"
FEATURES_GENERATED_TOPIC = "event-features-generated-v1"
FEATURES_GENERATION_FAILED_TOPIC = "event-features-generation-failed-v1"
FEATURE_STORE_BUCKET = "alpha-mind-feature-store-local"


def build_pubsub_push_body(cloud_event: dict[str, Any]) -> dict[str, Any]:
    """Encode a CloudEvents envelope into Pub/Sub push request format."""
    data = base64.b64encode(json.dumps(cloud_event).encode("utf-8")).decode("utf-8")
    return {"message": {"data": data}}


def pull_messages(
    subscriber_client: SubscriberClient,
    subscription_path: str,
    max_messages: int = 10,
    timeout: float = 5.0,
) -> list[dict[str, Any]]:
    """Pull messages from a subscription with retry, ack them, and return decoded payloads."""
    messages: list[dict[str, Any]] = []
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        response = subscriber_client.pull(
            request={
                "subscription": subscription_path,
                "max_messages": max_messages,
            },
            timeout=min(2.0, max(0.1, deadline - time.monotonic())),
        )
        if response.received_messages:
            ack_ids = []
            for received_message in response.received_messages:
                ack_ids.append(received_message.ack_id)
                decoded = json.loads(received_message.message.data.decode("utf-8"))
                messages.append(decoded)
            subscriber_client.acknowledge(
                request={
                    "subscription": subscription_path,
                    "ack_ids": ack_ids,
                }
            )
            break
        time.sleep(0.3)
    return messages


def drain_subscription(
    subscriber_client: SubscriberClient,
    subscription_path: str,
) -> None:
    """Drain all pending messages from a subscription."""
    with contextlib.suppress(Exception):
        response = subscriber_client.pull(
            request={
                "subscription": subscription_path,
                "max_messages": 100,
            },
            timeout=2.0,
        )
        if response.received_messages:
            ack_ids = [message.ack_id for message in response.received_messages]
            subscriber_client.acknowledge(
                request={
                    "subscription": subscription_path,
                    "ack_ids": ack_ids,
                }
            )
