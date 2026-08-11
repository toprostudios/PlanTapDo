FROM python:3.13.14-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

RUN groupadd --system --gid 10001 plantapdo \
    && useradd --system --uid 10001 --gid plantapdo --home-dir /app plantapdo

COPY requirements.lock ./
RUN python -m pip install --require-hashes --requirement requirements.lock

COPY --chown=plantapdo:plantapdo . .

USER 10001:10001
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD ["python", "-c", "from urllib.request import urlopen; response = urlopen('http://127.0.0.1:8000/health/live/', timeout=3); assert response.status == 200"]

CMD ["daphne", "--bind", "0.0.0.0", "--port", "8000", "--verbosity", "1", "timetodo_api.asgi:application"]
