"""GenerateSignalCommand DTO."""

import datetime
import re
from dataclasses import dataclass

_ULID_PATTERN = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")


@dataclass(frozen=True)
class GenerateSignalCommand:
    """features.generated イベントから変換されるユースケース入力 DTO。

    アプリケーション境界の入力として、イベントペイロードの必須項目を保持する。
    """

    identifier: str
    target_date: datetime.date
    feature_version: str
    storage_path: str
    universe_count: int
    trace: str

    def __post_init__(self) -> None:
        if not self.identifier:
            raise ValueError("identifier is required")
        if not _ULID_PATTERN.fullmatch(self.identifier):
            raise ValueError(f"identifier must be a valid ULID (got: {self.identifier})")
        if not self.trace:
            raise ValueError("trace is required")
        if not _ULID_PATTERN.fullmatch(self.trace):
            raise ValueError(f"trace must be a valid ULID (got: {self.trace})")
        if self.universe_count <= 0:
            raise ValueError("universe_count must be positive")
