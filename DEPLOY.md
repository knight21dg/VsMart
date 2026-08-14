# VS Mart — Production Deployment (Docker Compose + Caddy)

One VPS runs the whole web stack behind Caddy (automatic HTTPS via Let's Encrypt):

| Hostname               | Service           | Container      |
|------------------------|-------------------|----------------|
| `thevsmart.com`, `www` | Marketing/landing | `landing`      |
| `admin.thevsmart.com`  | Super-admin console | `admin`      |
| `store.thevsmart.com`  | Store-admin console | `store-admin` |
| `api.thevsmart.com`    | Django REST API   | `backend`      |

The customer (`user_app`) and agent (`agent_app`) **mobile apps** also talk to
`https://api.thevsmart.com/api/v1`.

Supporting services: `db` (Postgres 16), `redis` (cache + OTP store), `caddy` (TLS + reverse proxy).
Caddy serves `/static/*` and `/media/*` directly from shared volumes; everything else proxies to gunicorn.

---

## 0. Before you start — security

- **Rotate the VPS password now.** It was shared in plaintext; treat it as compromised.
- **Use SSH keys, disable password login.** From your machine:
  ```bash
  ssh-copy-id root@187.127.153.152          # or paste your public key into ~/.ssh/authorized_keys
  # then in /etc/ssh/sshd_config: PasswordAuthentication no  &&  systemctl restart ssh
  ```
- `OTP_DEV_BYPASS_CODE=123456` in `.env` is a **demo login backdoor** (any phone, OTP `123456`).
  It's kept intentionally per requirement — blank it out the day you go fully live with real users.
- `/media/*` (KYC documents, delivery photos) is served as **public URLs**. Fine for launch; before
  handling real customer KYC at scale, move to object storage with signed URLs (`prod.py` has the
  `django-storages` hook commented in).

---

## 1. DNS (do this first — cert issuance needs it)

Create **A records** pointing every hostname at the VPS:

| Type | Name    | Value             |
|------|---------|-------------------|
| A    | `@`     | `187.127.153.152` |
| A    | `www`   | `187.127.153.152` |
| A    | `admin` | `187.127.153.152` |
| A    | `store` | `187.127.153.152` |
| A    | `api`   | `187.127.153.152` |

Verify before continuing (each must return the IP):
```bash
for h in thevsmart.com www.thevsmart.com admin.thevsmart.com store.thevsmart.com api.thevsmart.com; do
  echo "$h -> $(dig +short $h)"
done
```

---

## 2. Provision the server (Ubuntu 22.04/24.04 assumed)

```bash
ssh root@187.127.153.152

# Firewall: SSH + HTTP + HTTPS only
ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw --force enable

# Docker Engine + Compose plugin
curl -fsSL https://get.docker.com | sh
docker --version && docker compose version

# (Recommended) ~2 GB RAM VPS: add swap so the 3 Next.js builds don't OOM
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
```

---

## 3. Get the code + configure

```bash
# Copy the repo to the server (git clone, or rsync/scp from your machine):
#   rsync -az --exclude node_modules --exclude .venv --exclude build ./VSMart/ root@187.127.153.152:/opt/vsmart/
cd /opt/vsmart      # repo root: where docker-compose.yml lives

cp .env.example .env
# Generate a real Django secret:
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
nano .env           # fill: SECRET_KEY, POSTGRES_PASSWORD + matching DATABASE_URL,
                    # ACME_EMAIL, and any real keys (Razorpay, MSG91, FCM, Sentry).
```

`.env` essentials that must be correct:
- `DATABASE_URL` password **must match** `POSTGRES_PASSWORD`.
- `ALLOWED_HOSTS=api.thevsmart.com`, `CSRF_TRUSTED_ORIGINS=https://api.thevsmart.com`.
- `CORS_ALLOWED_ORIGINS` lists the three web origins (already filled in the example).
- `ADMIN_API_BASE_URL=https://api.thevsmart.com/api/v1` (baked into the console JS at build).

---

## 4. Build + launch

```bash
docker compose config          # validate compose + .env interpolation
docker compose up -d --build    # builds 4 images, starts everything

docker compose ps               # all services Up; db healthy
docker compose logs -f caddy    # watch certs issue (one per hostname)
docker compose logs backend     # migrate + collectstatic ran in the entrypoint
```

First boot: Caddy obtains a Let's Encrypt cert for each hostname (needs DNS + ports 80/443 open).
The backend entrypoint runs `migrate` and `collectstatic` automatically.

### Migrations run on container boot — don't race them

Because the entrypoint migrates, running `migrate` by hand straight after
`docker compose up -d backend` races the startup migration and can fail with a
**misleading** error even though the migration succeeded:

```
django.db.utils.ProgrammingError: column "..." of relation "..." already exists
```

That is the boot migration having already applied it — not a broken migration.
**Check the recorded state before concluding anything failed:**

```bash
docker compose exec -T backend python manage.py showmigrations <app> | tail -5
# [X] 0010_...  -> applied; nothing to do, the error was the race.
# [ ] 0010_...  -> genuinely not applied; investigate before re-running.
```

A normal deploy needs no manual `migrate` at all — `docker compose up -d backend`
is enough. Run it by hand only when you have a reason to, and check
`showmigrations` first.

---

## 5. Post-deploy

```bash
# Django admin superuser
docker compose exec backend python manage.py createsuperuser

# OPTIONAL demo data (customer +919000000007 / OTP 123456 across all modules)
docker compose exec backend python manage.py seed_app
```

Smoke-test:
```bash
curl -i https://api.thevsmart.com/api/v1/health      # or any public GET
# Open: https://thevsmart.com  https://admin.thevsmart.com  https://store.thevsmart.com
# Admin login uses staff/superuser; store-admin uses seeded staff (9100000001-4 / OTP 123456).
```

---

## 6. Mobile app builds (point at prod)

Both apps read the API base from a build-time define; `--dart-define` wins over the in-code default.

```bash
# Customer app
cd apps/user_app
flutter build apk --release --dart-define=API_BASE_URL=https://api.thevsmart.com/api/v1

# Agent app
cd apps/agent_app
flutter build apk --release --dart-define=API_BASE_URL=https://api.thevsmart.com/api/v1
```

The `user_app` **prod flavor** already defaults to `https://api.thevsmart.com/api/v1` (see
`lib/app/config/app_config.dart`). For the Android NDK/minSdk requirements (Firebase), see the
project's Android build notes. The Google Maps API key still needs to be set in `user_app`'s
`AndroidManifest.xml` for order tracking.

---

## 7. Operations

> ### ⚠️ Shipping from Windows — use `git archive`, never a tar of the working tree
>
> `core.autocrlf=true` checks files out with **CRLF**. The repository stores LF,
> so the files are fine *in git* and wrong *on disk*. Ship the working tree and
> the container gets `#!/bin/sh\r`, the kernel looks for an interpreter named
> `/bin/sh\r`, and the backend crash-loops with:
>
> ```
> exec /app/docker-entrypoint.sh: no such file or directory
> ```
>
> — on a file that plainly exists. This took the API down for ~8 minutes during
> the 2026-08-09 deploy. `.gitattributes` now pins `eol=lf` on every file Linux
> executes or parses, and `git archive` exports **repository** content (already
> LF) rather than the working tree:
>
> ```bash
> # From the repo root — LF-correct by construction:
> git archive --format=tar HEAD apps/backend apps/admin apps/store-admin \
>   | ssh root@187.127.153.152 'cd /opt/vsmart && tar -xf -'
> ```
>
> If you ever do copy the working tree, check before building:
> `find apps -name '*.sh' -o -name 'Dockerfile*' | xargs file | grep CRLF`

```bash
# Redeploy after a code change
git pull   # or: git archive (see the CRLF warning above)
docker compose up -d --build

# Logs / restart / shell
docker compose logs -f <service>
docker compose restart backend
docker compose exec backend python manage.py shell

# Database backup / restore
docker compose exec db pg_dump -U vsmart vsmart > backup_$(date +%F).sql
cat backup.sql | docker compose exec -T db psql -U vsmart vsmart

# Stop everything (volumes/data persist)
docker compose down
```

### Notes & follow-ups
- **Static/media** persist in the `static`/`media` named volumes; `pgdata` holds the database. Back these up.
- **OTP/SMS**: leave `SMS_PROVIDER` blank to log OTPs in `backend` logs; set MSG91 keys for real SMS.
- **Razorpay**: payments run in mock mode until `RAZORPAY_KEY_ID/SECRET` are set; configure the
  webhook to `https://api.thevsmart.com/...` and set `RAZORPAY_WEBHOOK_SECRET`.
- **Resources**: building 3 Next.js apps is memory-hungry — the swap in step 2 prevents OOM on small VPSs.
  To avoid building on the box, build images in CI and `docker compose pull` instead.
