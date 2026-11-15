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

## Секреты: проверка в deploy.sh, не :?-джокеры в compose
- Compose **не** использует `${VAR:?}` для секретов (`DB_PASSWORD`, `RABBITMQ_PASSWORD`, `PROVIDER_API_KEY`) — только `:-` (пустой дефолт), чтобы парсинг/build работали без секретов (CI, `docker compose config`).
- Обязательность — **в `deploy.sh`**, по режиму:
  - `env`: `:?` для `DB_PASSWORD`/`RABBITMQ_PASSWORD`/`PROVIDER_API_KEY` до compose-команд;
  - `vault`: `:?` для `VAULT_DEV_ROOT_TOKEN`; после `render-env.sh` — `require_runtime_secret` для `DB_PASSWORD`/`RABBITMQ_PASSWORD`/`PROVIDER_API_KEY` (пусто → падаем с понятным сообщением, а не стартуем с пустым).
- `mock-provider` получает `PROVIDER_API_KEY` через `environment` (значение экспортировано `deploy.sh` из `runtime.env`), **не** `env_file: runtime.env` — mock не видит DB/RabbitMQ пароли (наименьшие привилегии).
- `APP_VERSION` — `:?` (не секрет, версия обязательна везде; `deploy.sh` задаёт).
- `:?` в compose у секретов **убирали** потому, что Compose валидирует при парсинге для всех сервисов (Vault/db/rabbitmq), даже неактивных — CI падал на vault/db, которые не поднимались.

## L3 — DLQ (подтверждено), provider key
- DLQ работает: «ядовитое»/401 → 3 ретрая → `transfers.dlq`. `rabbitmqctl list_queues` подтверждает. Нормальный путь: `POST /transfers` → worker → mock-provider `201` → `COMPLETED`.
- `mock-provider` не получал `PROVIDER_API_KEY` → 401 на все payout'ы → ложный DLQ. Исправлено: `PROVIDER_API_KEY` в `mock-provider.environment` (значение экспортируется `deploy.sh` из `runtime.env`); mock не видит DB/RabbitMQ пароли (наименьшие привилегии).
- Обязательность секретов — в `deploy.sh` (`require_runtime_secret` после `render-env.sh`), не `:?`-джокеры в compose (compose валидирует при парсинге для всех сервисов, даже неактивных).
- `401` — валидный кейс DLQ (провайдер отклонил), но в тесте был **баг конфигурации** (mock без ключа). Различать: 401/403 — конфиг; битый JSON/нет transfer — «ядовитое».

## request_id (L3) — замкнут
- nginx `$request_id` → `X-Request-Id` в api (уже был в nginx.conf стартера, api не читал — доделали).
- api: `_request_id` (X-Request-Id или uuid) → лог (`created`/`get`/`invalid`) → `broker.publish(..., request_id)` → `x-request-id` в headers → ответ `X-Request-Id`.
- worker: `x-request-id` из `properties.headers` → `send_payout` (`X-Request-Id` провайдеру) → лог (`payout request`, `completed`, `retry`, `dlq`).
- При retry `x-request-id` сохраняется в headers; в DLQ — виден.
- Проверено: `curl -i` → `x-request-id` в ответе = `request_id` в логах api/worker.
- `proxy_pass` → api (единственный HTTP-вход для клиента); worker получает `request_id` из очереди, mock-provider — от worker. mock-provider не логирует `X-Request-Id` (внешний, опционально — LIMITS).

## Инцидент: 401 → DLQ → зависший PENDING (демонстрация метрики)
- transfer `b7f853ad` (22:34:58): worker 3× `401 Unauthorized` от mock-provider (mock без `PROVIDER_API_KEY`) → `retry 1/3..3/3` → DLQ. Статус в БД остался `PENDING` (worker не обновил — ушёл в DLQ).
- `oldest_pending_age_seconds` = 4791с — **корректно** показывает зависший PENDING. Алерт `>300s` сработал бы → RUNBOOK (DLQ/401/конфиг mock → fix → replay/FAILED).
- Это **доказательство** ценности `oldest_pending_age_seconds` + алерта: метрика поймала реальный инцидент (не декоративна).
- Для «чистого» дашборда — `b7f853ad` помечен FAILED (артефакт 401/DLQ; в проде — replay/ручной fix). Или оставлен PENDING как демонстрация (решение: <A/B>).

## Dual-write / outbox / CDC — найдено, описано, рекомендовано (не реализовано)
- **Проблема:** api делает `INSERT transfer` и `broker.publish` — две транзакции (dual-write). Если publish упадёт (RabbitMQ недоступен) — в БД `PENDING`, в очереди нет сообщения → «зависший PENDING» навсегда.
- **Рекомендация:** **transactional outbox** — `INSERT transfer` + `INSERT outbox` в одной транзакции; отдельный relay (поллер `FOR UPDATE SKIP LOCKED` → publish → `sent_at`) или **CDC** (Debezium/логическое декодирование WAL) → at-least-once, без потерь.
- **Что сделано вместо:** **метрика** `oldest_pending_age_seconds` + **алерт** `>300s` **ловят** зависшие PENDING; **RUNBOOK** — разбор (DLQ/потеря/worker down → replay/FAILED). Пример: `b7f853ad` (401→DLQ→PENDING 4791с) — метрика/алерт поймали.
- **Итог:** dual-write + DLQ + oldest_pending + RUNBOOK достаточно для «поведения при сбоях» в тесте; outbox/CDC — **рекомендация** (LIMITS), следующий шаг в проде.

## L4 — наблюдаемость
- `docker-compose.reporting.yml` — отдельный override (prometheus/alertmanager/grafana/reporting-ui); `make deploy` — бизнес, `make deploy-observability` — +наблюдаемость. `--remove-orphans` убран (чтобы deploy не сносил reporting).
- `reporting-ui` = nginx → `grafana:3000` (Grafana не публикуется; одна точка входа `127.0.0.1:8090`).
- Алерты (Prometheus rules): `oldest_pending_age_seconds>300` (5м, warning), `increase(worker_messages_total{result="dlq"}[5m])>0` (5м, warning), `up{job=api|worker}==0` (2м, critical), `absent(up)` (5м, critical — dead man's switch). Пороги обоснованы (300с — аномалия для перевода; DLQ>0 — разбор; up==0 — мета).
- Alertmanager — без внешних интеграций (UI 127.0.0.1:9093); в проде — slack/pagerduty/webhook (LIMITS).
- Дашборд «Payments — работают?» (provisioned): transfers 1h, oldest_pending (порог 60/300), dlq 5m, by status, up — за 10с.
- Метки `com.northwind.owner: payments|analytics` — на всех (anchor).
- `OldestPendingTooOld` **firing** на `b7f853ad` (PENDING 4791с) — демонстрация, что алерт работает (инцидент 401→DLQ).
- Grafana admin — Vault: `seed.sh` (grafana_admin_password), `render-env.sh` (в runtime.env), `deploy.sh` (require_runtime_secret + export из runtime.env). `reporting`: `${GRAFANA_ADMIN_PASSWORD:-admin}` (fallback для down/config; deploy-observability — реальный).
- Vault seed: `grafana_admin_password` обязателен (`:?` в seed.sh); при изменении набора секретов — `vault kv delete secret/payment-stack/<env>` + re-seed (seed не перезаписывает существующий секрет).