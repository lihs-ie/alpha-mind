"""Shared test configuration and SDK mocks for signal-generator tests."""

from __future__ import annotations

import sys
from unittest.mock import MagicMock


def _ensure_google_cloud_mocks() -> None:
    """Install mock Google SDK modules when real packages are unavailable."""
    try:
        import google.api_core.exceptions
        import google.cloud.firestore_v1
        import google.cloud.pubsub_v1
        import google.cloud.storage  # noqa: F401

        return
    except ImportError:
        pass

    google_module = sys.modules.get("google", MagicMock())
    google_cloud_module = sys.modules.get("google.cloud", MagicMock())
    google_module.cloud = google_cloud_module

    firestore_v1_module = MagicMock()
    firestore_v1_module.Client = MagicMock
    firestore_v1_base_document_module = MagicMock()

    storage_module = MagicMock()
    storage_module.Client = MagicMock

    pubsub_module = MagicMock()
    pubsub_module.PublisherClient = MagicMock()
    pubsub_module.PublisherClient.return_value = MagicMock()
    pubsub_module.SubscriberClient = MagicMock()
    pubsub_module.SubscriberClient.return_value = MagicMock()

    api_core_module = sys.modules.get("google.api_core", MagicMock())
    api_core_exceptions_module = MagicMock()

    google_api_error = type("GoogleAPICallError", (Exception,), {})
    api_core_exceptions_module.GoogleAPICallError = google_api_error
    api_core_exceptions_module.AlreadyExists = type("AlreadyExists", (google_api_error,), {})
    api_core_exceptions_module.DeadlineExceeded = type("DeadlineExceeded", (google_api_error,), {})
    api_core_exceptions_module.InternalServerError = type("InternalServerError", (google_api_error,), {})
    api_core_exceptions_module.NotFound = type("NotFound", (google_api_error,), {})
    api_core_exceptions_module.ServiceUnavailable = type("ServiceUnavailable", (google_api_error,), {})
    api_core_exceptions_module.TooManyRequests = type("TooManyRequests", (google_api_error,), {})

    modules_to_set = {
        "google": google_module,
        "google.cloud": google_cloud_module,
        "google.cloud.firestore_v1": firestore_v1_module,
        "google.cloud.firestore_v1.base_document": firestore_v1_base_document_module,
        "google.cloud.storage": storage_module,
        "google.cloud.pubsub_v1": pubsub_module,
        "google.api_core": api_core_module,
        "google.api_core.exceptions": api_core_exceptions_module,
    }

    for module_name, mock_module in modules_to_set.items():
        sys.modules.setdefault(module_name, mock_module)


_ensure_google_cloud_mocks()
