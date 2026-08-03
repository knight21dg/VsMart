import { openDB, type DBSchema, type IDBPDatabase } from "idb";

/** A sellable variant option of a product (e.g. size/weight). */
export interface ProductVariantOption {
  id: string;
  label: string;
  priceDelta: number;
  price: number;
  /** This pack's OWN available count — each variant is stocked separately. */
  available: number;
  inStock: boolean;
  imageUrl?: string;
}

/** A product cached locally so the POS can search/scan + bill through an outage. */
export interface CachedProduct {
  productId: string;
  name: string;
  brand: string;
  unit: string;
  price: number;
  mrp: number;
  available: number;
  barcode: string;
  imageUrl?: string;
  variants?: ProductVariantOption[];
}

export type QueuedStatus = "pending" | "conflict";

/** A sale rung up (often while offline) and queued for idempotent sync. `id` is
 * the client-generated idempotency key — stable across retries so the backend
 * dedupes replays. */
export interface QueuedSale {
  id: string;
  createdAt: number;
  items: { productId: string; variantId?: string; name: string; qty: number; price: number }[];
  payment: { method: string; amount: number };
  customerId?: string;
  customerName?: string;
  /**
   * The coupon the cashier applied, if any. This is what makes the sale sync at
   * the price the customer actually paid: without it the replay posted at FULL
   * price while the drawer only held the discounted cash — a permanent till
   * variance on every offline coupon sale. Only the CODE is replayed; the server
   * recomputes the discount itself and never trusts a client amount.
   */
  couponCode?: string;
  /** The discount as shown on the till when the sale was rung up. Display and
   * audit only — see `couponCode` for what actually goes to the server. */
  discount?: number;
  total: number;
  status: QueuedStatus;
  error?: string;
}

interface POSDB extends DBSchema {
  catalog: { key: string; value: CachedProduct };
  outbox: { key: string; value: QueuedSale; indexes: { "by-status": QueuedStatus } };
  meta: { key: string; value: unknown };
}

const DB_NAME = "vsmart-pos";
const DB_VERSION = 1;

let _db: Promise<IDBPDatabase<POSDB>> | null = null;

/** Open (once) the POS IndexedDB. Returns null where IndexedDB is unavailable
 * (SSR / private-mode fallback) so every caller degrades gracefully. */
function db(): Promise<IDBPDatabase<POSDB>> | null {
  if (typeof window === "undefined" || typeof indexedDB === "undefined") return null;
  _db ??= openDB<POSDB>(DB_NAME, DB_VERSION, {
    upgrade(d) {
      if (!d.objectStoreNames.contains("catalog")) {
        d.createObjectStore("catalog", { keyPath: "productId" });
      }
      if (!d.objectStoreNames.contains("outbox")) {
        const store = d.createObjectStore("outbox", { keyPath: "id" });
        store.createIndex("by-status", "status");
      }
      if (!d.objectStoreNames.contains("meta")) {
        d.createObjectStore("meta");
      }
    },
  });
  return _db;
}

// ── Catalog cache ───────────────────────────────────────────────────────────

/** Replace the cached catalog wholesale with a fresh server snapshot. */
export async function saveCatalog(products: CachedProduct[]): Promise<void> {
  const d = await db();
  if (!d) return;
  const tx = d.transaction(["catalog", "meta"], "readwrite");
  await tx.objectStore("catalog").clear();
  for (const p of products) await tx.objectStore("catalog").put(p);
  await tx.objectStore("meta").put(Date.now(), "catalogSyncedAt");
  await tx.done;
}

export async function getCachedCatalog(): Promise<CachedProduct[]> {
  const d = await db();
  if (!d) return [];
  return d.getAll("catalog");
}

export async function catalogSyncedAt(): Promise<number | null> {
  const d = await db();
  if (!d) return null;
  return ((await d.get("meta", "catalogSyncedAt")) as number | undefined) ?? null;
}

/** Search the cached catalog by name / brand / exact barcode (offline parity
 * with the server's /store/pos/search). */
export async function searchCached(query: string): Promise<CachedProduct[]> {
  const all = await getCachedCatalog();
  const q = query.trim().toLowerCase();
  if (!q) return all.slice(0, 30);
  return all
    .filter(
      (p) =>
        p.name.toLowerCase().includes(q) ||
        (p.brand ?? "").toLowerCase().includes(q) ||
        p.barcode === query.trim(),
    )
    .slice(0, 30);
}

/** Optimistically adjust cached on-hand stock (e.g. decrement after an offline
 * sale) so the same items aren't visibly over-sold before the next sync. */
export async function adjustCachedStock(
  items: { productId: string; qty: number }[],
): Promise<void> {
  const d = await db();
  if (!d) return;
  const tx = d.transaction("catalog", "readwrite");
  for (const { productId, qty } of items) {
    const p = await tx.store.get(productId);
    if (p) await tx.store.put({ ...p, available: p.available - qty });
  }
  await tx.done;
}

// ── Sale outbox ─────────────────────────────────────────────────────────────

/** Build a new queued sale. Kept here (a plain module) so the impure
 * `crypto.randomUUID()` + `Date.now()` calls stay out of the React render path.
 * `id` doubles as the idempotency key the backend dedupes replays on. */
export function newQueuedSale(
  input: Pick<
    QueuedSale,
    "items" | "payment" | "total" | "customerId" | "customerName" | "couponCode" | "discount"
  >,
): QueuedSale {
  return { ...input, id: crypto.randomUUID(), createdAt: Date.now(), status: "pending" };
}

export async function enqueueSale(sale: QueuedSale): Promise<void> {
  const d = await db();
  if (!d) return;
  await d.put("outbox", sale);
}

export async function listQueue(): Promise<QueuedSale[]> {
  const d = await db();
  if (!d) return [];
  const all = await d.getAll("outbox");
  return all.sort((a, b) => a.createdAt - b.createdAt);
}

export async function updateSale(sale: QueuedSale): Promise<void> {
  const d = await db();
  if (!d) return;
  await d.put("outbox", sale);
}

export async function removeSale(id: string): Promise<void> {
  const d = await db();
  if (!d) return;
  await d.delete("outbox", id);
}
