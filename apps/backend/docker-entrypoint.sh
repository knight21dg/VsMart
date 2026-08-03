#!/bin/sh
# Run DB migrations and gather static files before the app server starts.
# Static lands in STATIC_ROOT (/app/staticfiles, a shared volume) and is served
# by Caddy; media is written to /app/media (also a shared volume).
set -e

echo "[entrypoint] Applying database migrations..."
python manage.py migrate --noinput

echo "[entrypoint] Collecting static files..."
python manage.py collectstatic --noinput

echo "[entrypoint] Starting: $*"
exec "$@"
