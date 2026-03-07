"""Compatibility wrapper for shared retry helpers."""

import time

from alpha_mind_backend_common.resilience.retry import with_retry

__all__ = ["time", "with_retry"]
