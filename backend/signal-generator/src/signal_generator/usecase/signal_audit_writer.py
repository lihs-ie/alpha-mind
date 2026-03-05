"""SignalAuditWriter application service."""

import datetime
from dataclasses import dataclass

from signal_generator.domain.aggregates.signal_generation import SignalGeneration
from signal_generator.domain.enums.generation_status import GenerationStatus
from signal_generator.domain.enums.reason_code import ReasonCode


@dataclass(frozen=True)
class AuditEntry:
    """監査ログ記録用の値オブジェクト。

    SignalGeneration 集約の状態から構築され、監査ログサービスへ送信される。
    """

    identifier: str
    trace: str
    status: GenerationStatus
    processed_at: datetime.datetime | None
    model_version: str | None = None
    signal_version: str | None = None
    reason_code: ReasonCode | None = None


class SignalAuditWriter:
    """監査ログ記録を担当するアプリケーションサービス。

    推論判定ロジックは含まず、SignalGeneration 集約の状態から
    監査エントリを構築する責務のみを持つ。
    """

    def build_audit_entry(self, signal_generation: SignalGeneration) -> AuditEntry:
        """SignalGeneration 集約の現在状態から AuditEntry を構築する。"""
        model_version: str | None = None
        if signal_generation.model_snapshot is not None:
            model_version = signal_generation.model_snapshot.model_version

        signal_version: str | None = None
        if signal_generation.signal_artifact is not None:
            signal_version = signal_generation.signal_artifact.signal_version

        reason_code: ReasonCode | None = None
        if signal_generation.failure_detail is not None:
            reason_code = signal_generation.failure_detail.reason_code

        return AuditEntry(
            identifier=signal_generation.identifier,
            trace=signal_generation.trace,
            status=signal_generation.status,
            processed_at=signal_generation.processed_at,
            model_version=model_version,
            signal_version=signal_version,
            reason_code=reason_code,
        )
