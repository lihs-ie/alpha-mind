"""Typed search criteria for repository search() methods."""

from dataclasses import dataclass, field

from hypothesis_lab.domain.enums.hypothesis_status import HypothesisStatus
from hypothesis_lab.domain.enums.instrument_type import InstrumentType
from hypothesis_lab.domain.enums.reason_code import ReasonCode
from hypothesis_lab.domain.enums.run_type import RunType
from hypothesis_lab.domain.identifiers import HypothesisIdentifier


@dataclass(frozen=True)
class HypothesisSearchCriteria:
    """仮説リポジトリの検索条件。"""

    status: HypothesisStatus | None = None
    symbol: str | None = None
    instrument_type: InstrumentType | None = None


@dataclass(frozen=True)
class ValidationRunSearchCriteria:
    """検証実行リポジトリの検索条件。"""

    hypothesis: HypothesisIdentifier | None = None
    run_type: RunType | None = None


@dataclass(frozen=True)
class FailureKnowledgeSearchCriteria:
    """失敗知見リポジトリの検索条件。"""

    hypothesis: HypothesisIdentifier | None = None
    reason_code: ReasonCode | None = None
