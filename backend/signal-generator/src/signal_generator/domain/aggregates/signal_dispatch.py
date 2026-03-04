"""SignalDispatch aggregate root."""

import datetime

from signal_generator.domain.enums.dispatch_status import DispatchStatus
from signal_generator.domain.enums.event_type import EventType
from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.domain.value_objects.dispatch_decision import DispatchDecision


class SignalDispatch:
    """シグナル発行処理の集約ルート。

    状態遷移: pending -> published / failed
    INV-SG-004: 同一イベント identifier は1回のみ published へ遷移できる。
    """

    def __init__(self, identifier: str, trace: str) -> None:
        self._identifier = identifier
        self._trace = trace
        self._dispatch_status: DispatchStatus = DispatchStatus.PENDING
        self._published_event: EventType | None = None
        self._reason_code: ReasonCode | None = None
        self._processed_at: datetime.datetime | None = None

    @property
    def identifier(self) -> str:
        return self._identifier

    @property
    def dispatch_status(self) -> DispatchStatus:
        return self._dispatch_status

    @property
    def trace(self) -> str:
        return self._trace

    @property
    def published_event(self) -> EventType | None:
        return self._published_event

    @property
    def reason_code(self) -> ReasonCode | None:
        return self._reason_code

    @property
    def processed_at(self) -> datetime.datetime | None:
        return self._processed_at

    def publish(self, published_event: EventType, processed_at: datetime.datetime) -> None:
        """イベント発行を確定する。INV-SG-004: 二重発行は禁止。統合イベントのみ許可。"""
        if not published_event.is_integration_event():
            raise ValueError(
                f"境界内ドメインイベント '{published_event.value}' は配信対象外。統合イベントのみ publish 可能"
            )
        if self._dispatch_status == DispatchStatus.PUBLISHED:
            raise ValueError(
                f"{ReasonCode.IDEMPOTENCY_DUPLICATE_EVENT}: identifier={self._identifier} は既に published"
            )
        if self._dispatch_status != DispatchStatus.PENDING:
            raise ValueError(
                f"{ReasonCode.STATE_CONFLICT}: status={self._dispatch_status.value} から published への遷移は不正"
            )
        self._published_event = published_event
        self._processed_at = processed_at
        self._dispatch_status = DispatchStatus.PUBLISHED

    def fail(self, reason_code: ReasonCode, processed_at: datetime.datetime) -> None:
        """発行失敗を確定する。"""
        if self._dispatch_status != DispatchStatus.PENDING:
            raise ValueError(
                f"{ReasonCode.STATE_CONFLICT}: status={self._dispatch_status.value} から failed への遷移は不正"
            )
        self._reason_code = reason_code
        self._processed_at = processed_at
        self._dispatch_status = DispatchStatus.FAILED

    def get_dispatch_decision(self) -> DispatchDecision:
        """現在の配信状態から DispatchDecision 値オブジェクトを返す。"""
        return DispatchDecision(
            dispatch_status=self._dispatch_status,
            published_event=self._published_event,
            reason_code=self._reason_code,
        )
