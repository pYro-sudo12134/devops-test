# syntax=docker/dockerfile:1.7
FROM python:3.12-slim AS builder
ENV PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY mock-provider/requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

FROM python:3.12-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssl \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /install /usr/local
COPY mock-provider/app.py mock-provider/entrypoint.sh ./
RUN useradd --create-home --uid 10003 app \
 && chmod +x ./entrypoint.sh \
 && chown -R app:app /app
USER app
EXPOSE 9443
ENTRYPOINT ["./entrypoint.sh"]