#!/usr/bin/env bash
set -euo pipefail

FILE="${1:?usage: restore.sh <backup.sql>}"
cd "$(dirname "$0")"

if [ ! -f "$FILE" ]; then
  echo "backup file not found: $FILE" >&2
  exit 1
fi

echo "restoring $FILE into db (payments)"
docker compose exec -T db psql -U payments -d payments -v ON_ERROR_STOP=1 < "$FILE"
echo "restore OK"