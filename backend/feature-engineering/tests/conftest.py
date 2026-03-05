"""Shared test configuration and fixtures.

Installs mock Google Cloud SDK modules into sys.modules when the actual
packages are not installed (e.g., in the local dev environment running
Python 3.9 without google-cloud-* packages).
"""

from __future__ import annotations

import sys
from unittest.mock import MagicMock


def _ensure_google_cloud_mocks() -> None:
    """Pre-populate sys.modules with mock Google Cloud SDK modules.

    Uses plain MagicMock (no spec) so that arbitrary attribute access
    like ``from google.cloud.firestore_v1 import Client`` succeeds.
    """
    if "google" in sys.modules and not isinstance(sys.modules["google"], MagicMock):
        # Real Google Cloud SDK is installed; nothing to do.
        return

    # Use plain MagicMock so that any attribute access works
    google_module = MagicMock()
    google_cloud_module = MagicMock()
    google_module.cloud = google_cloud_module

    firestore_module = MagicMock()
    firestore_module.Client = MagicMock
    google_cloud_module.firestore = firestore_module

    storage_module = MagicMock()
    storage_module.Client = MagicMock
    google_cloud_module.storage = storage_module

    pubsub_module = MagicMock()
    pubsub_module.PublisherClient = MagicMock()
    pubsub_module.PublisherClient.return_value = MagicMock()

    firestore_v1_module = MagicMock()
    firestore_v1_base_document_module = MagicMock()
    firestore_v1_transaction_module = MagicMock()

    api_core_module = MagicMock()
    api_core_exceptions_module = MagicMock()
    api_core_exceptions_module.AlreadyExists = type("AlreadyExists", (Exception,), {})

    modules_to_set = {
        "google": google_module,
        "google.cloud": google_cloud_module,
        "google.cloud.firestore": firestore_module,
        "google.cloud.firestore_v1": firestore_v1_module,
        "google.cloud.firestore_v1.base_document": firestore_v1_base_document_module,
        "google.cloud.firestore_v1.transaction": firestore_v1_transaction_module,
        "google.cloud.storage": storage_module,
        "google.cloud.pubsub_v1": pubsub_module,
        "google.api_core": api_core_module,
        "google.api_core.exceptions": api_core_exceptions_module,
    }

    for module_name, mock_module in modules_to_set.items():
        sys.modules.setdefault(module_name, mock_module)


_ensure_google_cloud_mocks()
