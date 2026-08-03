# Real-time delivery (WebSockets)

Live agent GPS + delivery status are pushed over WebSockets (Django Channels), on
top of the existing REST polling which stays as the initial load + fallback. The
poll is the source of truth; the socket just moves riders smoothly in between.

## Channels

| Path | Audience | Auth | Receives |
|------|----------|------|----------|
| `ws/orders/<id-or-code>/tracking` | Customer (order owner) or admin | JWT `?token=` | `{type:"tracking", data:{orderCode,status,agentName,latitude,longitude,eta}}` — initial snapshot + every agent ping/status change |
| `ws/admin/delivery/command-center` | admin / superadmin | JWT `?token=` | `{type:"dispatch", data:{id,orderCode,status,agent,latitude,longitude,eta,destLat,destLng}}` — every active delivery update |

A non-owner / non-admin / unauthenticated handshake is closed with code 4403.

## How it's wired

- **Auth:** `core/ws_auth.JWTAuthMiddleware` decodes the SimpleJWT access token from
  `?token=` (or the `Sec-WebSocket-Protocol` subprotocol) and sets `scope["user"]`.
- **Consumers:** `delivery/consumers.py` (`OrderTrackingConsumer`, `DispatchConsumer`);
  routes in `delivery/ws_routing.py`; mounted in `config/asgi.py` via a
  `ProtocolTypeRouter` (HTTP → Django, WebSocket → JWT middleware → consumers).
- **Broadcast:** `delivery/realtime.broadcast(task)` (best-effort — never breaks the
  delivery flow) is called from `delivery/services.py` at the single state-machine
  transition point (`_transition`) and on every GPS ping (`_update_order_tracking`).
  It `group_send`s to `order_<code>` and `dispatch`.
- **Channel layer:** in-memory in dev/test (no Redis); `channels_redis` over
  `REDIS_URL` in prod (`config/settings/prod.py`) so events fan out across workers.

## Frontends

- **Admin** (`apps/admin`): `lib/realtime/use-delivery-socket.ts` hook (reconnect +
  backoff + JWT). The command-center page merges live deltas over the 15s poll, drops
  terminal-status riders, and shows a "Live / Reconnecting…" indicator.
- **Customer** (`apps/user_app`): `liveTrackingProvider` (StreamProvider, `web_socket_channel`)
  streams the agent position; the tracking map prefers it over the 12s-polled coords.

## Deployment

- Served via **ASGI/Daphne** (`Dockerfile` CMD `daphne … config.asgi:application`) so one
  process handles HTTP + WS. Caddy's `reverse_proxy backend:8000` forwards the WS
  Upgrade transparently — no Caddyfile change. Redis is already in the compose stack.

## Verify

`scripts/smoke_ws.py` (in-memory layer, no Redis) — 10 assertions: customer connect +
snapshot, live position push to customer + dispatch board, ETA present, and RBAC
(non-admin / stranger / unauthenticated all rejected).

```
.venv/Scripts/python.exe scripts/smoke_ws.py
```
