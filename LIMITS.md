# LIMITS

- Vault — dev-режим (данные в памяти), не persistent. Для прода — Vault с storage backend (вне рамок теста).
- DLQ / лимит повторов для worker — не реализовано (L3).
- `provider.py` использует `verify=False` — не исправлено (L3).
- `request_id` в логах api/worker — не реализовано (L3).
- RED/бизнес-метрики, алерты, мета-мониторинг, дашборд — L4.
- `reporting-ui` не подключён к деплою (L4).
- `compose-smoke` в CI проверяет стек без Vault (SECRETS_SOURCE=env).