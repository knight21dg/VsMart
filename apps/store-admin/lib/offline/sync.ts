import { api } from "@/lib/api/client";
import { ApiError } from "@/lib/types";
import { listQueue, removeSale, updateSale, type QueuedSale } from "./db";

export interface SyncResult {
  synced: number;
  conflicts: number;
  failed: number;
}

/**
 * A sale already enqueued for sync, shaped exactly like the online checkout body
 * built in app/(console)/pos/page.tsx — items / payments / customerId /
 * couponCode. Keep the two in step: anything the till charges for online but
 * omits here is money the replay gets wrong.
 *
 * `couponCode` and not a discount amount: the backend re-resolves the coupon
 * against the recomputed subtotal and ignores any client-supplied figure
 * (storeops/pos_views.py StorePOSCheckoutView), so the code is the only thing
 * that can actually move the price. Dropping it meant the queued sale posted at
 * full price while the cashier had collected the discounted amount.
 */
function payloadFor(sale: QueuedSale) {
  return {
    items: sale.items.map((i) => ({ productId: i.productId, variantId: i.variantId, qty: i.qty })),
    payments: [sale.payment],
    customerId: sale.customerId,
    couponCode: sale.couponCode || undefined,
    note: `Offline sale @ ${new Date(sale.createdAt).toISOString()}`,
  };
}

/**
 * Replay queued offline sales to the backend, each with its stable
 * `Idempotency-Key` so a retry never double-posts inventory or payment.
 *
 * - 2xx → sale committed, drop from the outbox.
 * - 409 (pos_out_of_stock) → stock ran out before sync; mark `conflict` for the
 *   cashier to resolve (the cash was already taken physically). Don't retry.
 * - network error → stop the round and keep everything pending for next time.
 *
 * A coupon that lapsed between the sale and the sync also lands as a 400 →
 * `conflict`. That is the right outcome: the cashier reviews it rather than the
 * sale quietly reposting at full price.
 *
 * Already-`conflict` sales are skipped (await human resolution). Safe to call on
 * reconnect, on POS mount, and from a manual "Sync now" button.
 */
export async function syncOutbox(): Promise<SyncResult> {
  const queue = await listQueue();
  let synced = 0;
  let conflicts = 0;
  let failed = 0;

  for (const sale of queue) {
    if (sale.status === "conflict") {
      conflicts++;
      continue;
    }
    try {
      await api.post("/store/pos/checkout", payloadFor(sale), undefined, {
        headers: { "Idempotency-Key": sale.id },
      });
      await removeSale(sale.id);
      synced++;
    } catch (err) {
      if (err instanceof ApiError && err.status === 409) {
        await updateSale({
          ...sale,
          status: "conflict",
          error: err.message || "Out of stock at sync time",
        });
        conflicts++;
      } else if (err instanceof ApiError && err.status >= 400 && err.status < 500) {
        // A 4xx other than conflict (e.g. validation) won't fix itself on retry.
        await updateSale({ ...sale, status: "conflict", error: err.message });
        conflicts++;
      } else {
        // Network / 5xx — keep pending and stop this round; we're likely offline.
        failed++;
        break;
      }
    }
  }

  return { synced, conflicts, failed };
}
