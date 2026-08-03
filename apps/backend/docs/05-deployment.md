# 05 · Deployment (VPS + Docker)

Target: a single Linux VPS (Ubuntu 22.04+), **2 vCPU / 4 GB / 80 GB SSD** to start.
Everything runs as containers via Docker Compose. Caddy handles TLS automatically.

## Containers

| Service | Image | Role |
|---|---|---|
| `caddy` | caddy:2 | Reverse proxy, auto-HTTPS, serves `/media` |
| `api` | built (Django + gunicorn) | REST API + `/admin` console |
| `worker` | same image | Celery worker (jobs) |
| `beat` | same image | Celery beat (scheduler) |
| `db` | postgres:16 | Primary database |
| `redis` | redis:7 | Cache, broker, OTP, rate-limit |
| `minio` | minio/minio | S3-compatible file storage |

> Start lean: `api`, `db`, `redis`, `caddy`. Add `worker`+`beat` when statements/reminders
> land; add `minio` when KYC uploads land (or use Cloudflare R2 and skip the container).

## `docker-compose.yml` (shape)

```yaml
services:
  caddy:
    image: caddy:2
    ports: ["80:80", "443:443"]
    volumes: ["./Caddyfile:/etc/caddy/Caddyfile", "caddy_data:/data"]
    depends_on: [api]
  api:
    build: .
    command: gunicorn config.wsgi --bind 0.0.0.0:8000 --workers 3
    env_file: .env
    depends_on: [db, redis]
  worker:
    build: .
    command: celery -A config worker -l info
    env_file: .env
    depends_on: [db, redis]
  beat:
    build: .
    command: celery -A config beat -l info
    env_file: .env
    depends_on: [db, redis]
  db:
    image: postgres:16
    environment: [POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD]
    volumes: ["pgdata:/var/lib/postgresql/data"]
  redis:
    image: redis:7
    command: redis-server --appendonly yes
    volumes: ["redisdata:/data"]
  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    environment: [MINIO_ROOT_USER, MINIO_ROOT_PASSWORD]
    volumes: ["miniodata:/data"]
volumes: { pgdata: {}, redisdata: {}, miniodata: {}, caddy_data: {} }
```

## `Caddyfile`

```
api.vsmart.app {
    encode gzip
    handle_path /media/* { reverse_proxy minio:9000 }
    reverse_proxy api:8000
}
```
Caddy auto-issues + renews Let's Encrypt certs. Point the domain's A record at the VPS IP first.

## `.env.example` (keys)

```
# Django
DJANGO_SETTINGS_MODULE=config.settings.prod
SECRET_KEY=change-me
ALLOWED_HOSTS=api.vsmart.app
DEBUG=0
# DB
POSTGRES_DB=vsmart
POSTGRES_USER=vsmart
POSTGRES_PASSWORD=change-me
DATABASE_URL=postgres://vsmart:change-me@db:5432/vsmart
# Redis
REDIS_URL=redis://redis:6379/0
CELERY_BROKER_URL=redis://redis:6379/1
# JWT
JWT_ACCESS_MINUTES=30
JWT_REFRESH_DAYS=30
# Storage (MinIO or R2)
S3_ENDPOINT=http://minio:9000
S3_BUCKET=vsmart-media
S3_ACCESS_KEY=...
S3_SECRET_KEY=...
# SMS (OTP)
SMS_PROVIDER=msg91
SMS_API_KEY=...
SMS_SENDER_ID=VSMART
# Payments
RAZORPAY_KEY_ID=...
RAZORPAY_KEY_SECRET=...
RAZORPAY_WEBHOOK_SECRET=...
# App
GST_RATE=0.18
FREE_DELIVERY_THRESHOLD=499
DELIVERY_FEE=45
```

## First deploy

```bash
git clone <repo> && cd apps/backend
cp .env.example .env            # fill secrets
docker compose up -d --build
docker compose exec api python manage.py migrate
docker compose exec api python manage.py createsuperuser   # first superadmin
docker compose exec api python manage.py collectstatic --noinput
docker compose exec api python manage.py seed_demo         # optional fixtures
```

## Operations

- **Backups (do this day one):** nightly `pg_dump` to off-box storage (R2/S3) via a cron
  container or host cron; test a restore. Retain 7 daily + 4 weekly.
  ```
  docker compose exec -T db pg_dump -U vsmart vsmart | gzip > backup_$(date +%F).sql.gz
  ```
- **Migrations on deploy:** `migrate` runs before swapping `api` (zero-downtime not
  required at this scale; a few seconds is fine).
- **Logs:** `docker compose logs -f api`; ship to a file/Loki later.
- **Secrets:** never commit `.env`; keep a copy in a password manager.
- **Firewall:** expose only 80/443; Postgres/Redis/MinIO stay on the internal Docker network.
- **Monitoring (later):** Uptime ping on `/api/v1/health`, Sentry for errors.

## CI/CD (later, simple)

GitHub Actions: on push to `main` → run tests → build image → `ssh` to VPS →
`git pull && docker compose up -d --build && migrate`. Keep it boring.

## Health & readiness

- `GET /api/v1/health` → `{status:"ok"}` (no auth) for Caddy/uptime checks.
- `GET /api/v1/health/ready` → checks DB + Redis reachable.
