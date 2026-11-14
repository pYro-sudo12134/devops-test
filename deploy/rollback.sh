#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:?usage: rollback.sh <version>}"
cd "$(dirname "$0")"

if ! docker image inspect "northwind/payment-api:${VERSION}" >/dev/null 2>&1; then
  echo "image northwind/payment-api:${VERSION} not found; cannot rollback" >&2
  exit 1
fi

APP_VERSION="$VERSION" docker compose up -d --no-build --no-deps api worker
docker compose restart reverse-proxy

echo "rolled back to ${VERSION}"
echo "NOTE: schema is NOT rolled back. See RUNBOOK.md (migrations are forward-only; 003 is irreversible)."