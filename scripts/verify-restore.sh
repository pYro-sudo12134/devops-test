#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

BACKUP=$(./deploy/backup.sh)
echo "backup: $BACKUP"

CURRENT=$(docker compose -f deploy/docker-compose.yml exec -T db \
  psql -U payments -d payments -tAc "SELECT count(*) FROM transfers")

docker compose -f deploy/docker-compose.yml exec -T db \
  psql -U payments -d postgres -v ON_ERROR_STOP=1 -c "DROP DATABASE IF EXISTS restore_check" \
  -c "CREATE DATABASE restore_check"

docker compose -f deploy/docker-compose.yml exec -T db \
  psql -U payments -d restore_check -v ON_ERROR_STOP=1 < "$BACKUP"

RESTORED=$(docker compose -f deploy/docker-compose.yml exec -T db \
  psql -U payments -d restore_check -tAc "SELECT count(*) FROM transfers")

docker compose -f deploy/docker-compose.yml exec -T db \
  psql -U payments -d postgres -c "DROP DATABASE restore_check"

if [ "$CURRENT" != "$RESTORED" ]; then
  echo "restore verification FAILED: current=$CURRENT restored=$RESTORED" >&2
  exit 1
fi
echo "restore verification OK: $RESTORED rows"