# RUNBOOK

## Деплой
1. `cp deploy/.env.example deploy/.env`, заполнить.
2. `make deploy ENV=stage` (или `prod`).
3. Проверить `make status`, `make smoke`.

## Откат
- `./deploy/rollback.sh <version>` — откатывает api/worker на образ версии.
- **Схема БД НЕ откатывается.** Миграции forward-only; `003_add_amount_minor` необратим (DROP COLUMN amount). Для отката схемы — новая миграция (forward-fix), а не backward.

## Пропали секреты
- Локально: `deploy/.env` отсутствует/пуст → `seed.sh`/`render-env.sh` падают явно. Восстановить `.env` из `.env.example`, повторить `make deploy`.
- В Vault: `vault kv get secret/payment-stack/stage` — если пусто, `./deploy/vault/seed.sh stage` (только если `.env` есть).
- Если секрет не задан в CI (`SECRETS_SOURCE=env`) — `deploy.sh` падает на `:?` с понятным сообщением.

## Очередь растёт
- `docker compose exec rabbitmq rabbitmqctl list_queues name messages consumers`
- Если consumers=0 — worker упал: `docker compose ps worker`, `logs worker`.
- DLQ/лимит повторов — см. L3 (пока не реализовано, LIMITS).

## БД недоступна
- `/health` api вернёт 503 → healthcheck unhealthy → compose не раскатит (depends_on healthy).
- `docker compose logs db`, проверить диск/том.
- Восстановление: `./deploy/restore.sh backups/<file>.sql` (осторожно, см. выше).

## Проверка бэкапа
- `./scripts/verify-restore.sh` — делает бэкап, восстанавливает во временную БД, сверяет rows.