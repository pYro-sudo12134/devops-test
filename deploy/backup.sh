#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(cd .. && pwd)"
mkdir -p "$ROOT/backups"
umask 077

FILE="$ROOT/backups/payments-$(date +%Y%m%d-%H%M%S).sql"
docker compose exec -T db pg_dump -U payments -d payments --no-owner --no-privileges > "$FILE"
chmod 600 "$FILE"

# ротация: 7 последних
ls -1t "$ROOT"/backups/payments-*.sql 2>/dev/null | tail -n +8 | xargs -r rm -f

echo "$FILE"