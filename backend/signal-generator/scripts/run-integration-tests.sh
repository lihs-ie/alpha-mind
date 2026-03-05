#!/usr/bin/env bash
set -euo pipefail

# signal-generator 統合テスト実行スクリプト
#
# 使用方法:
#   ./scripts/run-integration-tests.sh
#
# 前提条件:
#   Docker が起動していること。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

echo "=== Firestore / Pub/Sub / fake-gcs / MLflow エミュレーターを起動 ==="
docker compose -f docker-compose.integration.yml up -d --wait

echo "=== エミュレーターの起動完了を待機 ==="
sleep 5

echo "=== 統合テスト実行 ==="
set +e
FIRESTORE_EMULATOR_HOST=localhost:8181 \
PUBSUB_EMULATOR_HOST=localhost:8085 \
STORAGE_EMULATOR_HOST=http://localhost:4443 \
MLFLOW_TRACKING_URI=http://localhost:5000 \
GCP_PROJECT=alpha-mind-local \
python -m pytest tests/integration/ -v --tb=long "$@"

TEST_EXIT_CODE=$?
set -e

echo "=== エミュレーターを停止 ==="
docker compose -f docker-compose.integration.yml down

exit $TEST_EXIT_CODE
