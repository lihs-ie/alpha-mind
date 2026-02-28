#!/usr/bin/env bash
# init-firestore.sh
# Firestore エミュレータにシードデータを投入する。
# seed-data.json に定義されたドキュメントをFirestore REST APIで作成する。
# 冪等: 既存ドキュメントは上書きする（エミュレータは PATCH で upsert）。

set -euo pipefail

FIRESTORE_HOST="${FIRESTORE_EMULATOR_HOST:-localhost:8080}"
PROJECT_ID="${GCP_PROJECT_ID:-alpha-mind-local}"
DATABASE="${FIRESTORE_DATABASE:-(default)}"
BASE_URL="http://${FIRESTORE_HOST}/v1/projects/${PROJECT_ID}/databases/${DATABASE}/documents"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEED_FILE="${SCRIPT_DIR}/seed-data.json"

if [[ ! -f "${SEED_FILE}" ]]; then
  echo "[ERROR] seed-data.json not found: ${SEED_FILE}" >&2
  exit 1
fi

upsert_document() {
  local collection="$1"
  local document_id="$2"
  local fields_json="$3"
  local url="${BASE_URL}/${collection}/${document_id}"
  local body="{\"fields\": ${fields_json}}"

  local http_status
  http_status=$(curl -s -o /dev/null -w "%{http_code}" -X PATCH \
    -H "Content-Type: application/json" \
    -d "${body}" \
    "${url}")

  if [[ "${http_status}" == "200" ]]; then
    echo "  [upserted] ${collection}/${document_id}"
  else
    echo "  [ERROR]    ${collection}/${document_id} (HTTP ${http_status})" >&2
    return 1
  fi
}

echo "==> Initializing Firestore emulator (project: ${PROJECT_ID}, database: ${DATABASE})"
echo "    Host: http://${FIRESTORE_HOST}"
echo ""

# seed-data.json を読み込んで各ドキュメントを投入する
document_count=$(jq '.documents | length' "${SEED_FILE}")
echo "    Seeding ${document_count} documents..."
echo ""

for i in $(seq 0 $((document_count - 1))); do
  collection=$(jq -r ".documents[${i}].collection" "${SEED_FILE}")
  document_id=$(jq -r ".documents[${i}].documentId" "${SEED_FILE}")
  fields_json=$(jq -c ".documents[${i}].fields" "${SEED_FILE}")

  upsert_document "${collection}" "${document_id}" "${fields_json}"
done

echo ""
echo "==> Firestore initialization complete."
