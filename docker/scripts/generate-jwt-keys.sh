#!/usr/bin/env bash
# generate-jwt-keys.sh
# RS256 JWT鍵ペアを生成する。
# 生成先: docker/secrets/jwt-private.pem, docker/secrets/jwt-public.pem
# 既に両ファイルが存在する場合は生成をスキップする（冪等）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/../secrets"
PRIVATE_KEY_PATH="${SECRETS_DIR}/jwt-private.pem"
PUBLIC_KEY_PATH="${SECRETS_DIR}/jwt-public.pem"

if [[ -f "${PRIVATE_KEY_PATH}" && -f "${PUBLIC_KEY_PATH}" ]]; then
  echo "==> JWT keys already exist, skipping generation."
  echo "    Private: ${PRIVATE_KEY_PATH}"
  echo "    Public:  ${PUBLIC_KEY_PATH}"
  exit 0
fi

if ! command -v openssl &>/dev/null; then
  echo "[ERROR] openssl is required but not installed." >&2
  exit 1
fi

mkdir -p "${SECRETS_DIR}"

echo "==> Generating RS256 JWT key pair..."
openssl genrsa -out "${PRIVATE_KEY_PATH}" 4096 2>/dev/null
openssl rsa -in "${PRIVATE_KEY_PATH}" -pubout -out "${PUBLIC_KEY_PATH}" 2>/dev/null

chmod 600 "${PRIVATE_KEY_PATH}"
chmod 644 "${PUBLIC_KEY_PATH}"

echo "    Private key: ${PRIVATE_KEY_PATH}"
echo "    Public key:  ${PUBLIC_KEY_PATH}"
echo "==> JWT key pair generation complete."
