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
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SERVICE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DOCKER_DIR="${REPO_ROOT}/docker"

COMPOSE_BASE="${DOCKER_DIR}/docker-compose.integration.base.yml"
COMPOSE_OVERLAY="${DOCKER_DIR}/docker-compose.integration.signal-generator.yml"

cd "$DOCKER_DIR"

echo "=== エミュレーターを起動 (base + signal-generator) ==="
docker compose -f "$COMPOSE_BASE" -f "$COMPOSE_OVERLAY" up -d --wait

echo "=== 統合テスト実行 ==="
set +e
cd "$SERVICE_DIR"
FIRESTORE_EMULATOR_HOST=localhost:8080 \
PUBSUB_EMULATOR_HOST=localhost:8085 \
STORAGE_EMULATOR_HOST=http://localhost:4443 \
MLFLOW_TRACKING_URI=http://localhost:5050 \
GCP_PROJECT=alpha-mind-local \
python -m pytest tests/integration/ -v --tb=long "$@"

TEST_EXIT_CODE=$?
set -e

echo "=== エミュレーターを停止 ==="
cd "$DOCKER_DIR"
docker compose -f "$COMPOSE_BASE" -f "$COMPOSE_OVERLAY" down

exit $TEST_EXIT_CODE
