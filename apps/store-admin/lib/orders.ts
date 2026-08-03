// Shared order types + store-side status rules, used by the orders list and the
// order detail page so the two can't drift apart.

export interface OrderRow {
  code: string;
  placedAt: string;
  customer: string | null;
  phone: string | null;
  items: number;
  value: number;
  paymentMethod: string;
  paymentStatus: string;
  status: string;
  deliveryStatus: string | null;
  agent: string | null;
}

/** Shape of `orders.admin_service.order_detail()` as the camelCase envelope delivers it. */
export interface OrderDetail {
  header: {
    code: string; placedAt: string; store: string | null; zone: string | null;
    status: string; paymentStatus: string; deliveryStatus: string | null;
    estimatedDelivery: string | null; source: string; createdBy: string; customerType: string;
  };
  customer: {
    id: string | null; name: string | null; phone: string | null;
    address: string | null; pincode: string | null; vsScore: number | null;
    outstanding: number; since: string | null;
  };
  items: { name: string; brand: string; quantity: number; mrp: number; price: number; discount: number; total: number }[];
  totals: { subtotal: number; discount: number; gst: number; deliveryFee: number; platformFee: number; total: number };
  payment: { method: string; status: string; creditUsed: number; creditPlan: string | null; creditDueDate: string | null };
  credit: {
    isCredit: boolean; creditUsed?: number; availableLimit?: number;
    outstandingBefore?: number | null; outstandingAfter?: number | null;
    dueDate?: string | null; collectionStatus?: string;
  };
  delivery: {
    agent: string | null; agentId: string | null; status: string | null;
    assignedAt: string | null; pickedUpAt: string | null; outForDeliveryAt: string | null;
    deliveredAt: string | null; distanceKm: number | null; eta: string | null;
    otp: string; photoUrl: string | null;
  };
  inventoryImpact: { name: string; ordered: number; before: number | null; remaining: number | null }[];
  exceptions: string[];
  timeline: { status: string; note: string | null; at: string; by: string | null }[];
}

/** Per-order outcomes from POST /store/orders/bulk-status. */
export interface BulkResult {
  status: string;
  updated: string[];
  failed: { code: string; error: string }[];
  updatedCount: number;
  failedCount: number;
}

export const STATUS_FILTERS = [
  "all", "placed", "confirmed", "packed", "ready_for_dispatch",
  "out_for_delivery", "delivered", "cancelled", "returned",
];

// A store can only stage an order for pickup. From "ready for dispatch" on,
// the assigned agent owns the state machine (out for delivery → reached →
// OTP + photo → delivered) — the backend rejects anything past this list
// (storeops.views.StoreOrderStatusView.ALLOWED_STATUSES).
export const NEXT_STATUS = ["confirmed", "packed", "ready_for_dispatch", "cancelled"];

// Once here, only the agent can move it further — no status picker for the store.
export const AGENT_OWNED_STATUSES = ["out_for_delivery", "reached", "delivered", "failed_delivery"];
