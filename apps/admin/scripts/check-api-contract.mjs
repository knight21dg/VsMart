/**
 * Cross-check what the console READS against what the API actually EMITS.
 *
 * The console reads response fields by name. Responses are rendered through
 * `EnvelopeJSONRenderer`, which camelCases every key — including keys that are
 * data rather than field names. Nothing verified that the names the console
 * reads are names the API emits, so `pins["today_deals"]` read `undefined`
 * forever and two home rails silently rendered empty.
 *
 * Feed it the output of `apps/backend/scripts/admin_contract_dump.py`:
 *
 *   node scripts/check-api-contract.mjs ../backend/scripts/admin_contract.json
 *
 * Reports, per endpoint, every field an interface declares that never appears
 * anywhere in that endpoint's real response. Some hits are legitimate (a type
 * shared with a POST body, an optional field absent on an empty row), so this
 * produces a triage list, not a verdict.
 */
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";

// Second argument sweeps another app's source (the store panel) against its own
// dump; defaults to this console.
const ROOT =
  process.argv[3] ||
  new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1");
const contractPath = process.argv[2];
if (!contractPath) {
  console.error("usage: node scripts/check-api-contract.mjs <admin_contract.json>");
  process.exit(2);
}
const contract = JSON.parse(readFileSync(contractPath, "utf8"));

/** Every key segment the endpoint really emits, e.g. `[].productName` -> productName. */
const emitted = new Map();
for (const [path, record] of Object.entries(contract.endpoints)) {
  const names = new Set();
  for (const keyPath of record.keys ?? []) {
    for (const seg of keyPath.split(".")) names.add(seg.replace(/\[\]$/, ""));
  }
  emitted.set(normalise(path), { names, status: record.status, empty: record.empty });
}

/** `/admin/zones/${id}` and `admin/zones/<pk>` have to compare equal. */
function normalise(p) {
  return p
    .replace(/\$\{[^}]*\}/g, "*")
    .replace(/<[^>]*>/g, "*")
    .replace(/\/+$/, "")
    .replace(/^\/?/, "/");
}

function walk(dir, out = []) {
  for (const entry of readdirSync(dir)) {
    if (entry === "node_modules" || entry === ".next" || entry === "scripts") continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) walk(full, out);
    else if (/\.tsx?$/.test(entry)) out.push(full);
  }
  return out;
}

/** `interface Foo { a: string; b: number }` -> Map<Foo, [a, b]> */
function parseInterfaces(src) {
  const found = new Map();
  const re = /\binterface\s+(\w+)\s*\{/g;
  let m;
  while ((m = re.exec(src))) {
    let depth = 1;
    let i = re.lastIndex;
    for (; i < src.length && depth > 0; i++) {
      if (src[i] === "{") depth++;
      else if (src[i] === "}") depth--;
    }
    const body = src.slice(re.lastIndex, i - 1);
    const fields = [];
    // Only top-level members: a nested object literal's own keys are matched
    // against the same flat name set, which is what we want anyway.
    for (const fm of body.matchAll(/(?:^|[;,{\n])\s*(\w+)\s*\??\s*:/g)) fields.push(fm[1]);
    found.set(m[1], fields);
  }
  return found;
}

/** `api.getPaged<Zone>("/admin/zones")` -> {path, type} */
function parseCalls(src) {
  const calls = [];
  const re = /api\.(get|getPaged|getWithMeta)<([^>]+)>\(\s*[`"']([^`"']+)[`"']/g;
  let m;
  while ((m = re.exec(src))) calls.push({ method: m[1], type: m[2].trim(), path: m[3] });
  return calls;
}

/**
 * Fields the dump can't observe, each checked against the API source by hand.
 * A finding that isn't listed here is unexamined — keep this list short and
 * keep the reason, or the report degrades into noise nobody reads.
 */
const ACCEPTED = {
  "/admin/delivery/command-center": {
    fields: ["zone"],
    reason: "inside `zones[]`, which the reference data leaves empty; admin_views.py:188 emits {zone, active}",
  },
  "/admin/catalog/products/*/variants": {
    fields: ["unallocated"],
    reason: "only returned when ?warehouse= is supplied (admin_views.py:263); the dump calls it without one",
  },
  "/admin/orders/*": {
    fields: ["availableLimit", "outstandingBefore", "outstandingAfter", "dueDate",
             "collectionStatus", "note", "at", "by"],
    reason: "credit block is credit-orders-only and timeline[] is empty for a fresh order; admin_service.py:274 emits all of them",
  },
  "/admin/procurement/payables": {
    fields: ["supplierId", "supplier", "invoices"],
    reason: "inside `bySupplier[]`, empty with no unpaid invoice; ap_services.py:148 emits them",
  },
  "/admin/returns/*": {
    fields: ["quantity", "amount", "acceptedQuantity", "acceptedAmount",
             "settledQuantity", "settledAmount"],
    reason: "inside `items[]`, empty for a return with no lines",
  },
  "/admin/collections/metrics": {
    fields: ["agentId", "name", "collected", "zone", "pending"],
    reason: "inside `agentPerformance[]`/`byZone[]`, empty with no collections; admin_views.py:138 emits them",
  },

  // ── store panel ──
  "/store/customers/*": {
    fields: ["creditLimit", "availableCredit", "usedCredit", "overdue",
             "nextDueDate", "repaymentRate", "latePayments", "missedPayments"],
    reason: "credit block only present when the customer has an account (hasAccount=false here); extra_views.py:671 emits them",
  },
  "/store/inventory/products/*": {
    fields: ["id", "label", "priceDelta", "hasOwnImage", "onHand", "available",
             "reorderLevel", "inStock"],
    reason: "per-variant fields inside `variants[]`, empty for a single-SKU product; catalog_views.py:71 documents the shape",
  },
  "/store/dashboard": {
    fields: ["batchNo", "expiryDate", "daysLeft", "expired", "actor", "action", "at"],
    reason: "inside `expiryAlerts[]` / the audit feed, both empty in the reference data",
  },
  "/store/pos/session": {
    fields: ["id", "status", "openingCash", "cashier", "drawer"],
    reason: "`session` is null with no till open, so its members are unobservable",
  },
  "/store/returns/*": {
    fields: ["quantity", "amount", "acceptedQuantity", "acceptedAmount",
             "settledQuantity", "settledAmount", "source", "url", "capturedAt"],
    reason: "inside `items[]` / `evidence[]`, empty for a return with no lines",
  },
};

function accepted(path, missing) {
  const entry = ACCEPTED[normalise(path)];
  if (!entry) return null;
  const unexplained = missing.filter((f) => !entry.fields.includes(f));
  return unexplained.length ? null : entry;
}

const findings = [];
const known = [];
const unmapped = [];
for (const file of walk(ROOT)) {
  const src = readFileSync(file, "utf8");
  if (!src.includes("api.")) continue;
  const interfaces = parseInterfaces(src);
  for (const call of parseCalls(src)) {
    const key = normalise(call.path);
    const record = emitted.get(key);
    if (!record) {
      unmapped.push({ file: relative(ROOT, file), path: call.path });
      continue;
    }
    if (record.empty || record.names.size === 0) continue; // nothing observed to compare
    const fields = interfaces.get(call.type.replace(/\[\]$/, ""));
    if (!fields || fields.length === 0) continue; // inline / primitive generic
    const missing = fields.filter((f) => !record.names.has(f));
    if (!missing.length) continue;
    const excuse = accepted(call.path, missing);
    const entry = { file: relative(ROOT, file), path: call.path, type: call.type, missing };
    if (excuse) known.push({ ...entry, reason: excuse.reason });
    else findings.push(entry);
  }
}

for (const f of findings) {
  console.log(`${f.file}\n  ${f.path}  (${f.type})\n  never emitted: ${f.missing.join(", ")}\n`);
}
console.log(`--- ${findings.length} UNEXPLAINED (fields the API never emits)`);
console.log(`--- ${known.length} explained (nested-in-empty / conditional, each checked against the API source)`);
console.log(`--- ${unmapped.length} calls with no dumped endpoint (not covered by the dump)`);
if (process.env.SHOW_KNOWN) {
  for (const k of known) console.log(`    ${k.path}: ${k.missing.join(", ")}\n      ${k.reason}`);
}
process.exitCode = findings.length ? 1 : 0;
if (process.env.SHOW_UNMAPPED) {
  for (const u of unmapped) console.log(`    ${u.path}   (${u.file})`);
}
