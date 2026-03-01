#!/usr/bin/env bash
# init-gcs.sh
# fake-gcs-server に Cloud Storage バケットを作成する。
# バケット命名: alpha-mind-{purpose}-local
# 冪等: 既存バケットへの再作成はスキップされる（HTTP 409 は無視）。

set -euo pipefail

GCS_HOST="${STORAGE_EMULATOR_HOST:-localhost:4443}"
BASE_URL="http://${GCS_HOST}/storage/v1"

# INF-003 に定義されたバケット一覧
BUCKETS=(
  "raw-market-data"
  "feature-store"
  "signal-store"
  "insight-raw"
  "insight-processed"
  "hypothesis-reports"
  "backtest-artifacts"
  "demo-artifacts"
)

create_bucket() {
  local purpose="$1"
  local bucket_name="alpha-mind-${purpose}-local"
  local url="${BASE_URL}/b"
  local body="{\"name\": \"${bucket_name}\"}"

  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "${body}" \
    "${url}")

  if [[ "${http_status}" == "200" ]]; then
    echo "  [created] bucket: ${bucket_name}"
  elif [[ "${http_status}" == "409" ]]; then
    echo "  [exists]  bucket: ${bucket_name}"
  else
    echo "  [ERROR]   bucket: ${bucket_name} (HTTP ${http_status})" >&2
    return 1
  fi
}

echo "==> Initializing GCS emulator (fake-gcs-server)"
echo "    Host: http://${GCS_HOST}"
echo ""

for purpose in "${BUCKETS[@]}"; do
  create_bucket "${purpose}"
done

echo ""
echo "==> GCS initialization complete."
