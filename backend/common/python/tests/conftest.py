"""Test helpers for python-common."""

from __future__ import annotations

import sys
from types import ModuleType


def _install_google_api_core_mocks() -> None:
    """Install minimal google.api_core.exceptions mocks when the package is absent."""
    try:
        import google.api_core.exceptions  # noqa: F401

        return
    except ImportError:
        pass

    google_module = sys.modules.setdefault("google", ModuleType("google"))
    api_core_module = sys.modules.setdefault("google.api_core", ModuleType("google.api_core"))
    exceptions_module = ModuleType("google.api_core.exceptions")

    class GoogleAPICallError(Exception):
        """Fallback Google API base exception for tests."""

    class ServiceUnavailable(GoogleAPICallError):
        """Fallback ServiceUnavailable exception for tests."""

    class InternalServerError(GoogleAPICallError):
        """Fallback InternalServerError exception for tests."""

    class DeadlineExceeded(GoogleAPICallError):
        """Fallback DeadlineExceeded exception for tests."""

    class TooManyRequests(GoogleAPICallError):
        """Fallback TooManyRequests exception for tests."""

    class NotFound(GoogleAPICallError):
        """Fallback NotFound exception for tests."""

    exceptions_module.GoogleAPICallError = GoogleAPICallError
    exceptions_module.ServiceUnavailable = ServiceUnavailable
    exceptions_module.InternalServerError = InternalServerError
    exceptions_module.DeadlineExceeded = DeadlineExceeded
    exceptions_module.TooManyRequests = TooManyRequests
    exceptions_module.NotFound = NotFound

    api_core_module.exceptions = exceptions_module
    google_module.api_core = api_core_module
    sys.modules["google.api_core.exceptions"] = exceptions_module


_install_google_api_core_mocks()
