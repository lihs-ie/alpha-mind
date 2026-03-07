"""Compatibility wrapper for shared retry helpers."""

from alpha_mind_backend_common.resilience import retry as _shared_retry

time = _shared_retry.time
with_retry = _shared_retry.with_retry

__all__ = ["with_retry"]
