# 04 · Roles & Permissions (RBAC)

Four roles, cumulative in trust but **not** strictly nested in scope — an agent is not a
"smaller admin"; agents have field powers customers/admins don't use day-to-day.

| Role | Trust | Primary surface |
|---|---|---|
| `customer` | self only | Flutter app |
| `agent` | assigned customers/areas | Flutter app (role-gated) / agent web |
| `admin` | all customers, ops | Web console (Django admin + JSON) |
| `superadmin` | everything + staff/config | Web console |

## Enforcement model

- **`role` column on `user`** drives DRF permission classes for the JSON API.
- **Django `Group` + `Permission`** back the `/admin/` site (admins get a curated subset;
  superadmin is Django `is_superuser`).
- **Object scoping**: customers and agents can only touch rows they own / are assigned to.
  Implemented as queryset filters in `get_queryset()` + object-level permission checks.
- **Sensitive actions** (staff management, credit limit changes, refunds, KYC final
  approval) require the higher role **and** write an `audit_log` row.

DRF permission classes (in `core/permissions.py`):
`IsCustomer`, `IsAgent`, `IsAdmin`, `IsSuperAdmin`, `IsOwner`, `IsAssignedAgent`.

## Permission matrix

✅ allowed · 🔒 own/assigned only · — not allowed

| Capability | customer | agent | admin | superadmin |
|---|:--:|:--:|:--:|:--:|
| Browse catalog, place orders | ✅ | ✅ | ✅ | ✅ |
| View **own** orders/credit/cart | 🔒 | 🔒 | ✅ | ✅ |
| Use & repay own credit | 🔒 | — | — | — |
| Submit own KYC | 🔒 | — | — | — |
| **Review/verify KYC** | — | 🔒 | ✅ | ✅ |
| **Collect cash** repayments | — | 🔒 | ✅ | ✅ |
| **Fulfil/deliver** assigned orders | — | 🔒 | ✅ | ✅ |
| See another customer's data | — | 🔒(assigned) | ✅ | ✅ |
| Manage catalog / offers / coupons | — | — | ✅ | ✅ |
| Update order status / assign agent | — | — | ✅ | ✅ |
| Adjust credit limit / freeze account | — | — | ✅ | ✅ |
| Issue refunds | — | — | ✅ | ✅ |
| Broadcast notifications | — | — | ✅ | ✅ |
| Reports / dashboards | — | — | ✅ | ✅ |
| **Create/disable admins & agents** | — | — | — | ✅ |
| Assign roles / change another's role | — | — | — | ✅ |
| Global config (fees, cycle, gateways) | — | — | view | ✅ |
| Access raw audit log | — | — | ✅(read) | ✅ |

## Notes

- **Agent scope** is defined by explicit assignments (KYC queue, deliveries,
  collections) via `ZoneAgent`/`DeliveryTask`/etc. An agent never sees the
  full customer base — only assigned/in-area records. (`AgentProfile.
  assigned_pincodes` exists on the model but nothing currently reads it —
  `delivery.services.candidate_agents()` scopes by `ZoneAgent`, not this
  field. Don't treat it as load-bearing until something actually enforces it.)
- **Admin vs superadmin**: the single line that separates them is **staff & role
  management** and **global configuration**. Everything operational is shared. Keep the
  number of superadmins tiny.
- **Self-service guard**: a customer can never read/write another user's resources;
  enforced centrally, not per-view, to avoid IDOR bugs.
- **Privilege escalation**: only superadmin can set `role`; the field is read-only in all
  customer/admin serializers and changing it always audits.

## First-run bootstrap

`createsuperuser` creates the first **superadmin**. From the admin console they create
admins and agents (agents also get an `agent_profile`). No self-signup for staff roles.
