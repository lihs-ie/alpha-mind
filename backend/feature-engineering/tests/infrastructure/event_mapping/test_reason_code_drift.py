"""Test that _ASYNCAPI_REASON_CODES stays in sync with ReasonCode.yaml."""

from pathlib import Path

import yaml

from infrastructure.event_mapping.domain_to_integration_event_mapper import (
    _ASYNCAPI_REASON_CODES,
)

REASON_CODE_YAML_PATH = (
    Path(__file__).resolve().parents[5] / "documents/外部設計/api/asyncapi/components/schemas/ReasonCode.yaml"
)


class TestReasonCodeDrift:
    def test_reason_codes_match_asyncapi_contract(self) -> None:
        """Ensure _ASYNCAPI_REASON_CODES matches the enum in ReasonCode.yaml exactly."""
        content = REASON_CODE_YAML_PATH.read_text()
        schema = yaml.safe_load(content)
        yaml_codes = frozenset(schema["enum"])

        assert yaml_codes == _ASYNCAPI_REASON_CODES, (
            f"ReasonCode drift detected.\n"
            f"  In code but not in YAML: {_ASYNCAPI_REASON_CODES - yaml_codes}\n"
            f"  In YAML but not in code: {yaml_codes - _ASYNCAPI_REASON_CODES}"
        )
