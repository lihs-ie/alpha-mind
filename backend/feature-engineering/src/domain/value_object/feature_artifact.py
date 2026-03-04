"""FeatureArtifact value object - generated feature file metadata."""

from dataclasses import dataclass


@dataclass(frozen=True)
class FeatureArtifact:
    """Metadata about a generated feature artifact stored in Cloud Storage."""

    feature_version: str
    storage_path: str
    row_count: int
    feature_count: int

    def __post_init__(self) -> None:
        if not self.feature_version:
            raise ValueError("feature_version must not be empty")
        if not self.storage_path:
            raise ValueError("storage_path must not be empty")
        if self.row_count < 0:
            raise ValueError(f"row_count must be non-negative, got {self.row_count}")
        if self.feature_count < 0:
            raise ValueError(f"feature_count must be non-negative, got {self.feature_count}")
