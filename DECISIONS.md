# DECISIONS

## L1 — гигиена
- Убран `docker compose down -v` (уничтожал тома). Заменено на `up -d --wait`.
- Pinned-версии: postgres:16.4, rabbitmq:3.13.7-management, nginx:1.27.3, vault:1.17.6, prometheus:v2.54.1, python:3.12-slim.
- Multi-stage + non-root во всех Dockerfile'ах; `base`-stage с `--only-upgrade zlib1g` (точечно, не полный upgrade).
- Healthcheck'и реальные: `/health` проверяет БД+RabbitMQ (503), а не всегда ok; api healthcheck через python (в slim нет curl).
- `depends_on: condition: service_healthy` везде.
- stage/prod без копипасты: базовый compose + override; старый `docker-compose.prod.yml` (несовместимая копипаста) переписан.
- Секреты: `.env.example` (без значений), `runtime.env` в `.gitignore` + `chmod 600`; убран дефолтный root-токен Vault.
- `deploy/.env` не коммитится; `.gitattributes` eol=lf (Windows/CRLF).

## L2 — доставка
- Миграции one-shot `run --rm --no-deps -T migrate` до раскатки, не из реплик; `pg_advisory_lock` + `lock_timeout=30s`.
- `migrate` — отдельный образ/тег `payment-api-migrate` (target `migrate`), профиль `tools` (up его не поднимает, run работает).
- `certs-init` — init-контейнер (root) chown тома `provider-certs`; `mock-provider` ждёт `service_completed_successfully`; НЕ в профиле (зависимость).
- `APP_VERSION` из `git describe`, тег по версии; GHCR (`ghcr.io/<owner>/...`), пакеты публичные.
- CI (публичный репо, ubuntu-latest): lint (ruff) → test → build → trivy (fail on fixable CRITICAL/HIGH) → push GHCR → compose-smoke (тот же deploy.sh, SECRETS_SOURCE=env, PULL_IMAGES=1).
- Доказательство прогона — ссылка на Actions run.
- CD-workflow не добавлен (нет 24/7 раннера); CD-интерфейс — `make deploy` (идемпотентный), проверяется в CI через compose-smoke.
- Smoke + автооткат (`rollback.sh $PREV_VERSION`), `.last_version` пишется после успешного smoke.
- `backup.sh` дампит `payments` (было `postgres`), ротация 7, chmod 600; `restore.sh` + `verify-restore.sh` (проверенное восстановление).
- `SECRETS_SOURCE=vault|env`: локально Vault dev, CI — env.
- На данном моменте ИИ предложил `trivy`. Это нормально, но он не знал, что `aquasecurity/trivy-action@0.28.0` — неверная версия. Правильно: [aquasecurity/trivy-action@v0.28.0](https://github.com/aquasecurity/trivy-action/tree/v0.28.0/). Но эта версия даже невалидная, так что стоит выбрать [aquasecurity/trivy-action@v0.33.1](https://github.com/aquasecurity/trivy-action/tree/v0.33.1/)

## Уроки (где ошибались / что ловили)
- `${VAR:?}` валидируется при парсинге compose для всех сервисов, даже неактивных (Vault, db, rabbitmq) — CI падал на vault/db, которые не поднимались.
- `env_file` тоже валидируется при парсинге: `runtime.env` должен существовать до любых compose-команд (`touch` до `up vault`).
- `POSTGRES_PASSWORD` vs `DB_PASSWORD`: config.py читал одно, runtime.env давал другое — падало на `required()`. Унифицировано: config.py читает `DB_PASSWORD`/`RABBITMQ_PASSWORD`.
- Один тег — один образ: `migrate` и `api` делили тег `payment-api`, migrate запускал runtime (uvicorn) - зависание. Разные теги + target.
- `docker compose run` без `-T` может висеть в CI (TTY).
- `up --wait` считает `exited` провалом, если сервис не в `depends_on` как `service_completed_successfully` - `migrate` в профиль `tools`.
- `certs-init` нельзя в профиль: `depends_on` на неактивный сервис → «undefined service».
- GHCR: `github.repository_owner.lowercase` не существует (пустая строка → `ghcr.io//...`); нужен `tr` в `$GITHUB_ENV`. Пакет `payment-worker` transient `denied` — retry.
- Trivy поймал реальные CVE: `zlib1g` (base) и `starlette` (Python) — гейт работает; `--only-upgrade zlib1g` в `runtime`, `starlette==1.3.1`.
- `Settings` (dataclass repr) логировал пароли — убрано, логируем только version/log_level.