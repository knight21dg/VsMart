FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=config.settings.prod

WORKDIR /app

# System deps for psycopg + Pillow.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chmod +x /app/docker-entrypoint.sh

EXPOSE 8000

# Entrypoint runs migrate + collectstatic against the mounted volumes, then execs CMD.
ENTRYPOINT ["/app/docker-entrypoint.sh"]
# Serve via ASGI (Daphne) so the same process handles HTTP *and* WebSockets
# (live delivery dispatch + customer order tracking). The Redis channel layer
# (CHANNEL_LAYERS in prod settings) fans events across processes. Caddy's
# reverse_proxy forwards the WS Upgrade transparently — no Caddyfile change needed.
CMD ["daphne", "-b", "0.0.0.0", "-p", "8000", "config.asgi:application"]
