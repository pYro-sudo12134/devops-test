SHELL := /bin/bash
ENV ?= stage
COMPOSE := docker compose -f deploy/docker-compose.yml

.PHONY: help deploy down status logs smoke migrate backup restore lint test

help:
	@echo "make deploy ENV=stage|prod   — идемпотентный деплой"
	@echo "make down                    — остановить (БЕЗ удаления томов)"
	@echo "make status                  — статус сервисов"
	@echo "make logs                    — логи"
	@echo "make migrate                 — применить миграции (one-shot)"
	@echo "make smoke                   — smoke-тест"
	@echo "make backup                  — бэкап БД"
	@echo "make restore FILE=...        — восстановление"
	@echo "make lint / test             — локальные проверки"

deploy:
	./deploy/deploy.sh $(ENV)

down:
	$(COMPOSE) down

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

lint:
	ruff check services mock-provider

test:
	PYTHONPATH=services/api pytest services/api/tests
	PYTHONPATH=services/worker pytest services/worker/tests