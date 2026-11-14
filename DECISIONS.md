# DECISIONS

Для помощи использовал DeepSeek.

## L1
- **Убран `docker compose down -v`** из деплоя: уничтожал тома БД/RabbitMQ при каждом деплое (запрещено условием). Заменено на `up -d --wait` + `--remove-orphans`.
- **Pinned-версии образов** (postgres:16.4, rabbitmq:3.13.7-management, nginx:1.27.3, vault:1.17.6, prometheus:v2.54.1, python:3.12-slim): `latest` невоспроизводим.
- **Multi-stage + non-root** во всех Dockerfile'ах: меньше поверхность, образ без компиляторов.
- **Healthcheck через python, а не curl**: в `python:3.12-slim` нет curl; тащить его ради healthcheck — лишний слой.
- **`/health` реально проверяет БД+RabbitMQ** (503 при недоступности): старый всегда `ok` → `depends_on: service_healthy` был бесполезен.
- **`depends_on: condition: service_healthy`**: порядок запуска, а не «надежда».
- **stage/prod без копипасты**: базовый compose + override; старый `docker-compose.prod.yml` был несовместимой копипастой (без worker/proxy/prometheus) — переписан как override с отличиями.
- **Секреты:** `deploy/.env` → `.env.example`; `runtime.env` в `.gitignore` + `chmod 600`; убран дефолтный root-токен Vault (`:?`).

## L2
- **Миграции — one-shot `run --rm --no-deps migrate` до раскатки**, не из реплик api (старый `entrypoint.sh` запускал `app.migrate` в каждой реплике — гонка). Плюс `pg_advisory_lock` в `migrate.py` от человеческой ошибки.
- **`migrate` — отдельный target в Dockerfile** (семантическое разделение), один образ, не тащим лишнее.
- **`APP_VERSION` из `git describe`**, тег образа по версии (L2).
- **Smoke + автооткат**: `smoke.sh` (health → POST → GET), при провале `rollback.sh $PREV_VERSION`.
- **`.last_version`** — предыдущая версия для отката, пишется только после успешного smoke.
- **CI на `ubuntu-latest`** (публичный репо): lint → test → build → trivy scan → compose-smoke (тот же `deploy.sh`, `SECRETS_SOURCE=env`). Доказательство — ссылка на прогон.
- **CD-workflow не добавлен**: нет 24/7 раннера; CD-интерфейс — `make deploy` (идемпотентный, проверяется в CI через compose-smoke). Оговорено в ASSUMPTIONS/LIMITS.
- **`SECRETS_SOURCE=vault|env`**: локально Vault dev, в CI — env. Vault dev — оговорка в LIMITS.
- **`backup.sh` дампит `payments`** (было `postgres` — бесполезный бэкап), ротация 7, `chmod 600`. `verify-restore.sh` — проверенное восстановление.
- **`reporting-ui` отложен на L4** (дашборд «платежи работают?»); сейчас не в деплое, порт наружу не публикуется.
- На данном моменте ИИ предложил `trivy`. Это нормально, но он не знал, что `aquasecurity/trivy-action@0.28.0` — неверная версия. Правильно: [aquasecurity/trivy-action@v0.28.0](https://github.com/aquasecurity/trivy-action/tree/v0.28.0/). Но эта версия даже невалидная, так что стоит выбрать [aquasecurity/trivy-action@v0.33.1](https://github.com/aquasecurity/trivy-action/tree/v0.33.1/)

### GHCR / реестр
- **Образы в GHCR** (`ghcr.io/<owner>/...`), тег по git sha (`APP_VERSION`). «Тег по версии» и «доставка» становятся осмысленными: CI пушит, compose-smoke пуллит **тот же** образ (не пересобирает) — проверяется реальная доставка, а не «собралось локально».
- **Пакеты публичные** (для теста): проще откат/пулл на другой машине. В проде — приватные + pull secret; отмечено в LIMITS.
- **`mock-provider` тоже в GHCR** — единообразие, smoke проверяет ровно реестр.
- **Vault-валидация в `deploy.sh`, не в compose** (`:?` убран у `VAULT_DEV_ROOT_TOKEN`): compose парсит `${...:?}` для всего файла даже при `profiles: disabled`, из-за чего CI падал на vault, который не поднимается. Обязательность — по режиму (`vault`/`env`) в скрипте.
- **`APP_VERSION` без дефолта `dev`**: `:?` в compose + проверка в `deploy.sh`. `dev`-тег ломал бы откат (два билда = один тег). Это было решено для RabbitMQ, Postgres, Vault.
- **Trivy: `--ignore-unfixed`**. Гейт падает только на CVE с доступным фиксом. Нефиксимые CVE базового Debian (`util-linux`, `ncurses`, `sqlite`, `systemd`) видны в отчёте, но не блокируют деплой — иначе доставка невозможна из-за пакетов, которые мы не контролируем. Политика пересматривается при обновлении base.
- **`starlette` обновлён** до версии с фиксом CVE (DoS/SSRF). Тесты api проходят.
- **`docker compose build --pull`** в CI — подтягиваем свежий base, чтобы уменьшить «fixed, но не подтянуто» (например, `zlib1g`). В проде — пиновать base по digest.
## Trivy-гейт
- **Trivy блокирует HIGH/CRITICAL** (`exit-code: 1`). Первый прогон поймал реальные CVE: `zlib1g` (debian base) и `starlette` (Python). Это доказывает, что гейт работает, а не декоративен.
- **`starlette` обновлён до 1.3.1** (fixed versions для CVE-2026-48818/54283). Проверено тестами/импортом — API совместим.
- **`zlib1g` — точечный `--only-upgrade`** в runtime-слое, а не полный `apt-get upgrade`: детерминированнее, закрывает конкретный CVE, не «дрейфит» образ.
- **Почему не `exit-code: 0` для HIGH:** гейт должен блокировать; ослабление — только если HIGH в base-образе неустранимы (тогда — запись в LIMITS и обоснование). Пока устранимы.