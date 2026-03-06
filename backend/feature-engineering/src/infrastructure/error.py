"""Infrastructure layer exceptions."""

from __future__ import annotations


class InfrastructureDataFormatError(Exception):
    """Raised when data from an external store cannot be deserialized into a domain object.

    Carries the collection/bucket name and the field path that caused the failure
    so that operators can quickly locate the corrupt document.
    """

    def __init__(self, source: str, detail: str, cause: Exception | None = None) -> None:
        self.source = source
        self.detail = detail
        self.__cause__ = cause
        super().__init__(f"[{source}] {detail}")
