// GET /api/account/orders — the signed-in customer's order history.
//
// Proxies the API's paginated `/orders`; the customer scoping happens there
// (the queryset filters on the token's user), so this route only forwards the
// page cursor.

import { jsonError, jsonOk } from "../../../lib/route-utils";
import { authedFetch } from "../../../lib/session";
import type { Order } from "../../../lib/types";

export const dynamic = "force-dynamic";

export async function GET(req: Request) {
  const url = new URL(req.url);
  const page = Number(url.searchParams.get("page") ?? "1");
  const safePage = Number.isFinite(page) && page >= 1 ? Math.floor(page) : 1;

  const res = await authedFetch<Order[]>(`/orders?page=${safePage}&page_size=10`);

  if (!res.ok) {
    return jsonError(res.message, res.status === 0 ? 502 : res.status || 400, {
      code: res.code,
    });
  }

  return jsonOk({ orders: res.data ?? [], meta: res.meta ?? null });
}
