#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?usage: rollback.sh <version>}"
cd "$(dirname "$0")"

IMAGE_PREFIX="${IMAGE_PREFIX:-northwind}"
if [ "${PULL_IMAGES:-0}" = "1" ]; then
  docker pull "${IMAGE_PREFIX}/payment-api:${VERSION}"
  docker pull "${IMAGE_PREFIX}/payment-worker:${VERSION}"
fi

if ! docker image inspect "${IMAGE_PREFIX}/payment-api:${VERSION}" >/dev/null 2>&1; then
  echo "image ${IMAGE_PREFIX}/payment-api:${VERSION} not found; cannot rollback" >&2
  exit 1
fi

APP_VERSION="$VERSION" IMAGE_PREFIX="$IMAGE_PREFIX" \
  docker compose up -d --no-build --no-deps api worker
docker compose restart reverse-proxy

echo "rolled back to ${VERSION} (${IMAGE_PREFIX})"
echo "NOTE: schema is NOT rolled back. See RUNBOOK.md (forward-only; 003 irreversible)."