"""Hypothesis aggregate root."""

import datetime

from hypothesis_lab.domain.enums.hypothesis_status import HypothesisStatus
from hypothesis_lab.domain.enums.insider_risk import InsiderRisk
from hypothesis_lab.domain.enums.instrument_type import InstrumentType
from hypothesis_lab.domain.enums.promotion_mode import PromotionMode
from hypothesis_lab.domain.exceptions import (
    InvariantViolationError,
    InvalidStateTransitionError,
    OperationNotAllowedError,
)
from hypothesis_lab.domain.identifiers import HypothesisIdentifier, ValidationRunIdentifier
from hypothesis_lab.domain.value_objects.compliance_snapshot import ComplianceSnapshot
from hypothesis_lab.domain.value_objects.demo_window import DemoWindow
from hypothesis_lab.domain.value_objects.performance_metrics import PerformanceMetrics


class Hypothesis:
    """仮説の集約ルート。

    状態遷移:
      (なし) -> DRAFT -> BACKTESTED -> DEMO -> LIVE (終端)
                      \\-> REJECTED (終端)
                                       \\-> REJECTED (終端)

    INV-HL-001: identifier は生成後不変。
    INV-HL-005: title, source_evidence, skill_version, instruction_profile_version は常に必須。
    """

    def __init__(
        self,
        identifier: HypothesisIdentifier,
        symbol: str,
        instrument_type: InstrumentType,
        status: HypothesisStatus,
        title: str,
        source_evidence: list[str],
        skill_version: str,
        instruction_profile_version: str,
        updated_at: datetime.datetime,
        insider_risk: InsiderRisk | None = None,
        requires_compliance_review: bool | None = None,
        mnpi_self_declared: bool | None = None,
        auto_promotion_eligible: bool | None = None,
        promotion_mode: PromotionMode | None = None,
        latest_failure_summary: str | None = None,
        updated_by: str | None = None,
        validation_runs: list[ValidationRunIdentifier] | None = None,
        performance_metrics: PerformanceMetrics | None = None,
        demo_window: DemoWindow | None = None,
        compliance_snapshot: ComplianceSnapshot | None = None,
    ) -> None:
        # INV-HL-005: 必須フィールドの検証
        if not title:
            raise InvariantViolationError("title は空文字列にできません (INV-HL-005)")
        if not source_evidence:
            raise InvariantViolationError("source_evidence は 1 件以上必要です (INV-HL-005)")
        if not skill_version:
            raise InvariantViolationError("skill_version は空文字列にできません (INV-HL-005)")
        if not instruction_profile_version:
            raise InvariantViolationError("instruction_profile_version は空文字列にできません (INV-HL-005)")

        self._identifier = identifier
        self._symbol = symbol
        self._instrument_type = instrument_type
        self._status = status
        self._title = title
        self._source_evidence = list(source_evidence)
        self._skill_version = skill_version
        self._instruction_profile_version = instruction_profile_version
        self._insider_risk = insider_risk
        self._requires_compliance_review = requires_compliance_review
        self._mnpi_self_declared = mnpi_self_declared
        self._auto_promotion_eligible = auto_promotion_eligible
        self._promotion_mode = promotion_mode
        self._latest_failure_summary = latest_failure_summary
        self._updated_at = updated_at
        self._updated_by = updated_by
        self._validation_runs: list[ValidationRunIdentifier] = list(validation_runs) if validation_runs else []
        self._performance_metrics = performance_metrics
        self._demo_window = demo_window
        self._compliance_snapshot = compliance_snapshot
        self._promotable: bool | None = None

    @property
    def identifier(self) -> HypothesisIdentifier:
        """INV-HL-001: identifier は不変。"""
        return self._identifier

    @property
    def symbol(self) -> str:
        return self._symbol

    @property
    def instrument_type(self) -> InstrumentType:
        return self._instrument_type

    @property
    def status(self) -> HypothesisStatus:
        return self._status

    @property
    def title(self) -> str:
        return self._title

    @property
    def source_evidence(self) -> list[str]:
        return list(self._source_evidence)

    @property
    def skill_version(self) -> str:
        return self._skill_version

    @property
    def instruction_profile_version(self) -> str:
        return self._instruction_profile_version

    @property
    def insider_risk(self) -> InsiderRisk | None:
        return self._insider_risk

    @property
    def requires_compliance_review(self) -> bool | None:
        return self._requires_compliance_review

    @property
    def mnpi_self_declared(self) -> bool | None:
        return self._mnpi_self_declared

    @property
    def auto_promotion_eligible(self) -> bool | None:
        return self._auto_promotion_eligible

    @property
    def promotion_mode(self) -> PromotionMode | None:
        return self._promotion_mode

    @property
    def latest_failure_summary(self) -> str | None:
        return self._latest_failure_summary

    @property
    def updated_at(self) -> datetime.datetime:
        return self._updated_at

    @property
    def updated_by(self) -> str | None:
        return self._updated_by

    @property
    def validation_runs(self) -> list[ValidationRunIdentifier]:
        return list(self._validation_runs)

    @property
    def performance_metrics(self) -> PerformanceMetrics | None:
        return self._performance_metrics

    @property
    def demo_window(self) -> DemoWindow | None:
        return self._demo_window

    @property
    def compliance_snapshot(self) -> ComplianceSnapshot | None:
        return self._compliance_snapshot

    @property
    def promotable(self) -> bool | None:
        """最新 demo 評価の昇格判定可否。"""
        return self._promotable

    def record_backtest_result(self, passed: bool, metrics: PerformanceMetrics) -> None:
        """バックテスト結果を記録する。

        DRAFT -> BACKTESTED (passed=True) or DRAFT -> REJECTED (passed=False)
        """
        if self._status != HypothesisStatus.DRAFT:
            raise InvalidStateTransitionError(
                f"backtest result は DRAFT 状態でのみ記録できます。現在の状態: {self._status.value}"
            )
        self._performance_metrics = metrics
        if passed:
            self._status = HypothesisStatus.BACKTESTED
        else:
            self._status = HypothesisStatus.REJECTED

    def start_demo_run(self) -> None:
        """demo 実行を開始する。

        BACKTESTED -> DEMO
        RULE-HL-001: DRAFT からの直接遷移は禁止。
        """
        if self._status != HypothesisStatus.BACKTESTED:
            raise InvalidStateTransitionError(
                f"demo 実行は BACKTESTED 状態でのみ開始できます。現在の状態: {self._status.value} "
                "(RULE-HL-001: DRAFT からの直接遷移は禁止)"
            )
        self._status = HypothesisStatus.DEMO

    def complete_demo_run(self, demo_window: DemoWindow, promotable: bool) -> None:
        """demo 実行を完了する。

        DEMO -> REJECTED (promotable=False)
        DEMO -> DEMO (promotable=True だが自動昇格条件未達、手動昇格待ち)
        """
        if self._status != HypothesisStatus.DEMO:
            raise InvalidStateTransitionError(
                f"demo 実行の完了は DEMO 状態でのみ行えます。現在の状態: {self._status.value}"
            )
        self._demo_window = demo_window
        self._promotable = promotable
        if not promotable:
            self._status = HypothesisStatus.REJECTED

    def promote(self, promotion_mode: PromotionMode) -> None:
        """仮説を live に昇格させる。

        INV-HL-002: PromotionReadySpecification を満たす場合のみ live 遷移を許可。
        """
        if self._status.is_terminal():
            raise InvalidStateTransitionError(
                f"終端状態 ({self._status.value}) からの状態遷移は禁止されています (INV)"
            )
        if self._status != HypothesisStatus.DEMO:
            raise InvalidStateTransitionError(
                f"promote は DEMO 状態でのみ実行できます。現在の状態: {self._status.value}"
            )
        # INV-HL-002: PromotionReadySpecification による昇格前提条件チェック
        from hypothesis_lab.domain.specifications.promotion_ready_specification import PromotionReadySpecification

        specification = PromotionReadySpecification()
        if not specification.is_satisfied_by(self):
            raise InvariantViolationError(
                "昇格前提条件 (PromotionReadySpecification) を満たしていません (INV-HL-002). "
                "demo_period_days >= 30 かつ requires_compliance_review == False かつ promotable == True が必要です"
            )
        self._promotion_mode = promotion_mode
        self._status = HypothesisStatus.LIVE

    def reject(self) -> None:
        """仮説を rejected に遷移させる (手動拒否)。"""
        if self._status.is_terminal():
            raise InvalidStateTransitionError(
                f"終端状態 ({self._status.value}) からの状態遷移は禁止されています (INV)"
            )
        if self._status not in (HypothesisStatus.DEMO, HypothesisStatus.BACKTESTED):
            raise InvalidStateTransitionError(
                f"reject は DEMO または BACKTESTED 状態でのみ実行できます。現在の状態: {self._status.value}"
            )
        self._status = HypothesisStatus.REJECTED

    def update_mnpi_self_declaration(self, mnpi_self_declared: bool) -> None:
        """MNPI 自己申告を更新する。

        RULE-HL-008: demo 状態でのみ更新を許可する。
        """
        if self._status != HypothesisStatus.DEMO:
            raise OperationNotAllowedError(
                f"mnpi_self_declared の更新は DEMO 状態でのみ許可されます。現在の状態: {self._status.value} "
                "(RULE-HL-008)"
            )
        self._mnpi_self_declared = mnpi_self_declared
