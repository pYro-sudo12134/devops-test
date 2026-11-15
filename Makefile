SHELL := /bin/bash
ENV ?= stage
COMPOSE := docker compose -f deploy/docker-compose.yml
COMPOSE_REPORTING := docker compose -f deploy/docker-compose.yml -f deploy/docker-compose.reporting.yml

.PHONY: help deploy deploy-observability down status logs smoke migrate backup restore verify-restore rotate lint test

help:
	@echo "make deploy ENV=stage|prod        — бизнес-стек (идемпотентный)"
	@echo "make deploy-observability ENV=...  — бизнес + наблюдаемость (prometheus/grafana/alertmanager/reporting-ui/loki)"
	@echo "make down                          — остановить (БЕЗ удаления томов; бизнес + наблюдаемость)"
	@echo "make status                        — статус сервисов"
	@echo "make logs                          — логи"
	@echo "make migrate                       — применить миграции (one-shot)"
	@echo "make smoke                         — smoke-тест"
	@echo "make backup                        — бэкап БД (pg_dump payments, ротация 7)"
	@echo "make restore FILE=...              — восстановление"
	@echo "make verify-restore                — проверенное восстановление (временная БД, сверка rows)"
	@echo "make rotate KEY=...                — ротация PROVIDER_API_KEY"
	@echo "make lint / test                   — локальные проверки"

deploy:
	./deploy/deploy.sh $(ENV)

deploy-observability:
	COMPOSE_EXTRA_FILE=docker-compose.reporting.yml ./deploy/deploy.sh $(ENV)

down:
	APP_VERSION=$${APP_VERSION:-dev} $(COMPOSE_REPORTING) down

status:
	./scripts/status.sh

logs:
	$(COMPOSE) logs -f --tail=100

migrate:
	$(COMPOSE) run --rm migrate

smoke:
	./scripts/smoke.sh

backup:
	./deploy/backup.sh

restore:
	./deploy/restore.sh $(FILE)

verify-restore:
	./scripts/verify-restore.sh

rotate:
	./scripts/rotate-provider-key.sh $(KEY)

lint:
	ruff check services mock-provider

test:
	PYTHONPATH=services/api pytest services/api/tests
	PYTHONPATH=services/worker pytest services/worker/tests