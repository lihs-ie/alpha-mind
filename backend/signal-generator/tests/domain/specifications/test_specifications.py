"""Tests for Specification implementations."""

import datetime

import pytest

from signal_generator.domain.enums.model_status import ModelStatus
from signal_generator.domain.specifications.approved_model_exists_specification import (
    ApprovedModelExistsSpecification,
)
from signal_generator.domain.specifications.feature_payload_integrity_specification import (
    FeaturePayloadIntegritySpecification,
)
from signal_generator.domain.specifications.prediction_count_consistency_specification import (
    PredictionCountConsistencySpecification,
)
from signal_generator.domain.value_objects.feature_snapshot import FeatureSnapshot
from signal_generator.domain.value_objects.model_snapshot import ModelSnapshot
from signal_generator.domain.value_objects.signal_artifact import SignalArtifact


class TestFeaturePayloadIntegritySpecification:
    def test_complete_feature_snapshot_satisfies_specification(self) -> None:
        # RULE-SG-001: 必須項目が全て揃っている場合は satisfied
        fixed_date = datetime.date(2026, 3, 15)
        spec = FeaturePayloadIntegritySpecification(clock=lambda: fixed_date)
        feature = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        assert spec.is_satisfied_by(feature) is True

    def test_missing_feature_version_does_not_satisfy(self) -> None:
        # RULE-SG-001: featureVersion 欠損時は推論不開始
        spec = FeaturePayloadIntegritySpecification()
        feature = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="",
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        assert spec.is_satisfied_by(feature) is False

    def test_missing_storage_path_does_not_satisfy(self) -> None:
        # RULE-SG-001: storagePath 欠損時は推論不開始
        spec = FeaturePayloadIntegritySpecification()
        feature = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="",
        )
        assert spec.is_satisfied_by(feature) is False

    def test_invalid_storage_path_prefix_does_not_satisfy(self) -> None:
        # Cloud Storage パスは gs:// で始まる必要がある
        spec = FeaturePayloadIntegritySpecification()
        feature = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version="v1.0.0",
            storage_path="/local/path/features.parquet",
        )
        assert spec.is_satisfied_by(feature) is False

    def test_future_target_date_does_not_satisfy(self) -> None:
        # 将来日付は有効な特徴量として扱わない
        spec = FeaturePayloadIntegritySpecification()
        feature = FeatureSnapshot(
            target_date=datetime.date(9999, 12, 31),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/9999-12-31/features.parquet",
        )
        assert spec.is_satisfied_by(feature) is False

    def test_today_target_date_satisfies_with_injected_clock(self) -> None:
        # clock DI: 当日の特徴量は有効
        fixed_date = datetime.date(2026, 3, 15)
        spec = FeaturePayloadIntegritySpecification(clock=lambda: fixed_date)
        feature = FeatureSnapshot(
            target_date=datetime.date(2026, 3, 15),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-03-15/features.parquet",
        )
        assert spec.is_satisfied_by(feature) is True

    def test_tomorrow_target_date_does_not_satisfy_with_injected_clock(self) -> None:
        # clock DI: 翌日の特徴量は無効
        fixed_date = datetime.date(2026, 3, 15)
        spec = FeaturePayloadIntegritySpecification(clock=lambda: fixed_date)
        feature = FeatureSnapshot(
            target_date=datetime.date(2026, 3, 16),
            feature_version="v1.0.0",
            storage_path="gs://feature_store/2026-03-16/features.parquet",
        )
        assert spec.is_satisfied_by(feature) is False

    def test_non_string_feature_version_does_not_satisfy(self) -> None:
        """feature_version が str でない場合は不合格。"""
        fixed_date = datetime.date(2026, 3, 15)
        spec = FeaturePayloadIntegritySpecification(clock=lambda: fixed_date)
        # feature_version に整数を渡す (型チェックをバイパス)
        feature = FeatureSnapshot.__new__(FeatureSnapshot)
        object.__setattr__(feature, "target_date", datetime.date(2026, 1, 1))
        object.__setattr__(feature, "feature_version", 12345)  # type: ignore[arg-type]
        object.__setattr__(feature, "storage_path", "gs://feature_store/2026-01-01/features.parquet")
        assert spec.is_satisfied_by(feature) is False

    @pytest.mark.parametrize(
        "malicious_version",
        [
            "../../x",
            "../etc/passwd",
            "v1.0.0/../../secret",
            "",
            " ",
            "a" * 65,  # 65文字 = 上限超過
        ],
    )
    def test_path_traversal_feature_version_does_not_satisfy(self, malicious_version: str) -> None:
        """feature_version にパス汚染値が含まれる場合は不合格になる。"""
        fixed_date = datetime.date(2026, 3, 15)
        spec = FeaturePayloadIntegritySpecification(clock=lambda: fixed_date)
        feature = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version=malicious_version,
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        assert spec.is_satisfied_by(feature) is False

    @pytest.mark.parametrize(
        "valid_version",
        [
            "v1.0.0",
            "v2.3.4-beta",
            "model_v1.2",
            "A",
            "a" * 64,  # ちょうど上限
        ],
    )
    def test_valid_feature_version_satisfies(self, valid_version: str) -> None:
        """正当な feature_version は合格する。"""
        fixed_date = datetime.date(2026, 3, 15)
        spec = FeaturePayloadIntegritySpecification(clock=lambda: fixed_date)
        feature = FeatureSnapshot(
            target_date=datetime.date(2026, 1, 1),
            feature_version=valid_version,
            storage_path="gs://feature_store/2026-01-01/features.parquet",
        )
        assert spec.is_satisfied_by(feature) is True


class TestApprovedModelExistsSpecification:
    def test_approved_model_satisfies_specification(self) -> None:
        # RULE-SG-002: approved モデルが存在する場合は satisfied
        spec = ApprovedModelExistsSpecification()
        model = ModelSnapshot(
            model_version="model-v1.0.0",
            status=ModelStatus.APPROVED,
            approved_at=datetime.datetime(2026, 1, 1, tzinfo=datetime.UTC),
        )
        assert spec.is_satisfied_by(model) is True

    def test_candidate_model_does_not_satisfy(self) -> None:
        spec = ApprovedModelExistsSpecification()
        model = ModelSnapshot(
            model_version="model-v2.0.0",
            status=ModelStatus.CANDIDATE,
            approved_at=None,
        )
        assert spec.is_satisfied_by(model) is False

    def test_rejected_model_does_not_satisfy(self) -> None:
        spec = ApprovedModelExistsSpecification()
        model = ModelSnapshot(
            model_version="model-v3.0.0",
            status=ModelStatus.REJECTED,
            approved_at=None,
        )
        assert spec.is_satisfied_by(model) is False

    def test_none_model_does_not_satisfy(self) -> None:
        spec = ApprovedModelExistsSpecification()
        assert spec.is_satisfied_by(None) is False


class TestPredictionCountConsistencySpecification:
    def test_matching_counts_satisfies_specification(self) -> None:
        # RULE-SG-004: 推論件数とユニバース件数が一致する場合は satisfied
        spec = PredictionCountConsistencySpecification()
        artifact = SignalArtifact(
            signal_version="signal-v1.0.0",
            storage_path="gs://signal_store/2026-01-01/signals.parquet",
            generated_count=100,
            universe_count=100,
        )
        assert spec.is_satisfied_by(artifact) is True

    def test_mismatching_counts_cannot_create_artifact(self) -> None:
        # RULE-SG-004: 件数不一致では SignalArtifact 自体が生成できない
        with pytest.raises(ValueError):
            SignalArtifact(
                signal_version="signal-v1.0.0",
                storage_path="gs://signal_store/2026-01-01/signals.parquet",
                generated_count=99,
                universe_count=100,
            )
