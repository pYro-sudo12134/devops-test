#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
mkdir -p ../backups
umask 077

FILE="../backups/payments-$(date +%Y%m%d-%H%M%S).sql"
docker compose exec -T db pg_dump -U payments -d payments --no-owner --no-privileges > "$FILE"
chmod 600 "$FILE"

ls -1t ../backups/payments-*.sql 2>/dev/null | tail -n +8 | xargs -r rm -f

echo "$FILE"