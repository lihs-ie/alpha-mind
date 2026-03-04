"""SignalArtifact value object."""

from dataclasses import dataclass


@dataclass(frozen=True)
class SignalArtifact:
    """推論結果ファイル情報。RULE-SG-004: 件数整合を不変条件として保証する。"""

    signal_version: str
    storage_path: str
    generated_count: int
    universe_count: int

    def __post_init__(self) -> None:
        # RULE-SG-004: 推論件数はユニバース件数と一致しなければならない
        if self.generated_count != self.universe_count:
            raise ValueError(
                f"推論件数({self.generated_count})がユニバース件数({self.universe_count})と一致しない (RULE-SG-004)"
            )
