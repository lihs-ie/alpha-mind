"""Pub/Sub subscriber endpoint blueprint.

Cloud Pub/Sub push サブスクリプションからの HTTP POST を受け付け、
features.generated イベントをデコードして SignalGenerationService に委譲する。
"""

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from flask import Blueprint, Response, current_app, jsonify, request

from signal_generator.domain.enums.reason_code import ReasonCode
from signal_generator.presentation.cloud_event_decoder import (
    CloudEventDecodeError,
    decode_pubsub_push_message,
    extract_envelope_identifiers,
)
from signal_generator.usecase.generate_signal_command import GenerateSignalCommand
from signal_generator.usecase.generate_signal_result import GenerateSignalResult

if TYPE_CHECKING:
    from signal_generator.usecase.signal_generation_service import SignalGenerationService

logger = logging.getLogger(__name__)

_SERVICE_NAME = "signal-generator"

subscriber_blueprint = Blueprint("subscriber", __name__)


@subscriber_blueprint.route("/", methods=["POST"])
def handle_pubsub_push() -> tuple[Response, int]:
    """Pub/Sub push エンドポイント。

    エラー戦略:
    - バリデーション失敗 (不正な eventType, 必須フィールド欠損): 200 (ack, 再試行不要)
    - retryable なユースケース失敗: 500 (nack, Pub/Sub が再配信)
    - non-retryable なユースケース失敗: 200 (ack)
    """
    # Step 1: リクエストボディの取得
    body = request.get_json(silent=True)
    if body is None:
        logger.warning(
            "Request body is not valid JSON",
            extra={"service": _SERVICE_NAME},
        )
        return jsonify({"status": "error", "error": "Invalid request body"}), 200

    # Step 2: CloudEvents エンベロープのデコード
    try:
        cloud_event_payload = decode_pubsub_push_message(body)
    except CloudEventDecodeError as error:
        logger.warning(
            "CloudEvent decode failed: %s",
            error,
            extra={"service": _SERVICE_NAME},
        )
        # identifier/trace が取得できる場合は failed イベントを発行する
        envelope_identifiers = extract_envelope_identifiers(body)
        if envelope_identifiers is not None:
            decode_failure_service: SignalGenerationService = current_app.config["SIGNAL_GENERATION_SERVICE"]
            decode_failure_service.handle_decode_failure(
                identifier=envelope_identifiers[0],
                trace=envelope_identifiers[1],
                detail=str(error),
            )
        return jsonify({"status": "error", "error": str(error)}), 200

    # Step 3: GenerateSignalCommand の構築
    service: SignalGenerationService = current_app.config["SIGNAL_GENERATION_SERVICE"]

    structured_extra = {
        "service": _SERVICE_NAME,
        "identifier": cloud_event_payload.identifier,
        "trace": cloud_event_payload.trace,
        "eventType": cloud_event_payload.event_type,
    }

    try:
        command = GenerateSignalCommand(
            identifier=cloud_event_payload.identifier,
            target_date=cloud_event_payload.target_date,
            feature_version=cloud_event_payload.feature_version,
            storage_path=cloud_event_payload.storage_path,
            universe_count=cloud_event_payload.universe_count,
            trace=cloud_event_payload.trace,
        )
    except ValueError as error:
        logger.warning(
            "Command validation failed: %s",
            error,
            extra=structured_extra,
        )
        return jsonify({"status": "error", "error": str(error)}), 200

    # Step 4: ユースケース実行
    logger.info(
        "Processing signal generation: identifier=%s, trace=%s",
        command.identifier,
        command.trace,
        extra=structured_extra,
    )

    try:
        result: GenerateSignalResult = service.execute(command)
    except Exception:
        logger.exception(
            "Unhandled exception in signal generation: identifier=%s",
            command.identifier,
            extra=structured_extra,
        )
        return jsonify({"status": "error", "error": "Internal server error"}), 500

    # Step 5: 結果に応じたレスポンス
    if result.is_success:
        logger.info(
            "Signal generation completed: identifier=%s",
            command.identifier,
            extra=structured_extra,
        )
        return jsonify({"status": "ok"}), 200

    # 失敗 - retryable かどうかで HTTP ステータスを分ける
    # reason_code が None の場合は安全側で nack (500) を返す
    if result.reason_code is None:
        logger.warning(
            "Failure with unknown reason_code (defaulting to nack): identifier=%s, trace=%s",
            command.identifier,
            command.trace,
            extra=structured_extra,
        )
        return jsonify({"status": "error", "error": result.detail or "Unknown failure"}), 500

    failure_extra = {
        **structured_extra,
        "reasonCode": str(result.reason_code),
    }

    is_retryable = result.reason_code not in ReasonCode.non_retryable()

    if is_retryable:
        logger.warning(
            "Retryable failure: identifier=%s, reason=%s",
            command.identifier,
            result.reason_code,
            extra=failure_extra,
        )
        return jsonify({"status": "error", "error": result.detail or str(result.reason_code)}), 500

    logger.info(
        "Non-retryable failure (ack): identifier=%s, reason=%s",
        command.identifier,
        result.reason_code,
        extra=failure_extra,
    )
    return jsonify({"status": "error", "error": result.detail or str(result.reason_code)}), 200
