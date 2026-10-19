# VectorSense Labs - Scoring Engine: API + worker image (same image, different command)
FROM python:3.12-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
RUN groupadd -g 10001 app && useradd -u 10001 -g app -m app
COPY pyproject.toml ./
COPY app ./app
RUN pip install --upgrade pip && pip install .
COPY db ./db
COPY samples ./samples
COPY scripts ./scripts
RUN mkdir -p /app/samples/local && chown -R app:app /app/samples
USER 10001
EXPOSE 8000
# API: default. Worker: `python -m app.worker`. Migrations: `python -m app.migrate`.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
