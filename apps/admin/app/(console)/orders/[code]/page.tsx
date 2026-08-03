"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, ExternalLink, FileText, TriangleAlert, ChevronDown } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { getAccessToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import { LoadingState, ErrorState } from "@/components/states";
import { ProductLink } from "@/components/product-link";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { inr, fmtDate, titleize } from "@/lib/utils";

interface OrderDetail {
  header: { code: string; placedAt: string; store: string | null; zone: string | null; status: string; paymentStatus: string; deliveryStatus: string | null; estimatedDelivery: string | null; source: string; createdBy: string; customerType: string };
  customer: { id: string | null; name: string | null; phone: string | null; address: string | null; pincode: string | null; vsScore: number | null; outstanding: number; since: string | null };
  items: { name: string; brand: string; quantity: number; mrp: number; price: number; discount: number; total: number }[];
  totals: { subtotal: number; discount: number; gst: number; deliveryFee: number; platformFee: number; total: number };
  payment: { method: string; status: string; creditUsed: number; creditPlan: string | null; creditDueDate: string | null };
  credit: { isCredit: boolean; creditUsed?: number; availableLimit?: number; outstandingBefore?: number | null; outstandingAfter?: number | null; dueDate?: string | null; collectionStatus?: string };
  delivery: { agent: string | null; agentId: string | null; status: string | null; assignedAt: string | null; pickedUpAt: string | null; outForDeliveryAt: string | null; deliveredAt: string | null; distanceKm: number | null; eta: string | null; otp: string };
  inventoryImpact: { name: string; ordered: number; before: number | null; remaining: number | null }[];
  exceptions: string[];
  timeline: { status: string; note: string; at: string; by: string | null }[];
}

// No "delivered" here — only the assigned agent's own OTP + photo
// verification can complete a delivery (delivery.services.complete_delivery).
// The backend rejects it from this raw status endpoint outright.
const ADVANCE = ["confirmed", "packed", "ready_for_dispatch", "out_for_delivery", "cancelled", "rejected", "failed_delivery"];

// Order exceptions → the lifecycle state they drive + an audit note.
// "returned"/"partially_returned" are NOT here — those go through the
// Returns & Refunds flow (see the Exception menu's separate "Damaged
// Product" entry below), which actually processes the refund and stock
// reversal; the backend rejects a raw status write of "returned" now.
const EXCEPTIONS: { label: string; status: string }[] = [
  { label: "Item Out of Stock", status: "cancelled" },
  { label: "Customer Not Reachable", status: "failed_delivery" },
  { label: "Customer Requested Cancellation", status: "cancelled" },
  { label: "Delivery Failed", status: "failed_delivery" },
  { label: "Wrong Address", status: "failed_delivery" },
];

async function downloadInvoice(code: string) {
  const res = await fetch(api.buildUrl(`/admin/orders/${code}/invoice`), {
    headers: { Authorization: `Bearer ${getAccessToken() ?? ""}` },
  });
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `invoice-${code}.pdf`;
  a.click();
  URL.revokeObjectURL(url);
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="mt-0.5 text-sm font-medium">{children}</div>
    </div>
  );
}

export default function OrderDetailPage() {
  const { code } = useParams<{ code: string }>();
  const router = useRouter();
  const [newStatus, setNewStatus] = React.useState("");

  const query = useQuery({
    queryKey: ["admin", "orders", code],
    queryFn: () => api.get<OrderDetail>(`/admin/orders/${code}`),
  });
  const o = query.data;

  const setStatus = useApiMutation(
    (v: { status: string; note?: string }) => api.post(`/admin/orders/${code}/status`, v),
    { invalidate: [["admin", "orders", code], ["admin", "orders"]], successMessage: "Order updated." }
  );

  return (
    <>
      <Button variant="ghost" size="sm" className="-ml-2 w-fit" onClick={() => router.back()}>
        <ArrowLeft /> Back
      </Button>

      {query.isLoading ? (
        <LoadingState />
      ) : query.isError || !o ? (
        <ErrorState message="Couldn't load this order." onRetry={() => query.refetch()} />
      ) : (
        <>
          <PageHeader
            title={`Order ${o.header.code}`}
            description={`${fmtDate(o.header.placedAt, true)} · ${o.header.store ?? "—"} · ${o.header.zone ?? "—"}`}
            actions={
              <div className="flex flex-wrap items-center gap-2">
                <Select value={newStatus} onValueChange={(v) => { setNewStatus(v); setStatus.mutate({ status: v }); }}>
                  <SelectTrigger className="w-[170px]"><SelectValue placeholder="Advance status…" /></SelectTrigger>
                  <SelectContent>
                    {ADVANCE.map((s) => <SelectItem key={s} value={s}>{titleize(s)}</SelectItem>)}
                  </SelectContent>
                </Select>
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button variant="outline"><TriangleAlert /> Exception <ChevronDown /></Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    {EXCEPTIONS.map((ex) => (
                      <DropdownMenuItem key={ex.label} onSelect={() => setStatus.mutate({ status: ex.status, note: `Exception: ${ex.label}` })}>
                        {ex.label}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuContent>
                </DropdownMenu>
                <Button variant="outline" onClick={() => downloadInvoice(o.header.code)}>
                  <FileText /> Invoice
                </Button>
              </div>
            }
          />

          {/* Status strip + exception badges */}
          <div className="space-y-4 rounded-xl border bg-card p-5">
            <div className="grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-6">
              <Field label="Order Status"><StatusBadge status={o.header.status} /></Field>
              <Field label="Payment"><StatusBadge status={o.header.paymentStatus} /></Field>
              <Field label="Delivery"><StatusBadge status={o.header.deliveryStatus ?? "—"} /></Field>
              <Field label="Source">{o.header.source}</Field>
              <Field label="Customer">{o.header.customerType}</Field>
              <Field label="Est. Delivery">{o.header.estimatedDelivery ? fmtDate(o.header.estimatedDelivery, true) : "—"}</Field>
            </div>
            <div className="flex flex-wrap gap-2">
              {o.exceptions.map((ex) => (
                <span
                  key={ex}
                  className={
                    "inline-flex items-center rounded-full px-3 py-1 text-xs font-medium " +
                    (ex === "No Exceptions"
                      ? "bg-[color-mix(in_oklab,var(--color-success)_15%,transparent)] text-[var(--color-success)]"
                      : "bg-destructive/10 text-destructive")
                  }
                >
                  {ex}
                </span>
              ))}
            </div>
          </div>

          <div className="grid gap-4 lg:grid-cols-3">
            {/* Customer */}
            <Card>
              <CardHeader className="flex-row items-center justify-between">
                <CardTitle>Customer</CardTitle>
                {o.customer.id && (
                  <Button variant="ghost" size="sm" onClick={() => router.push(`/customers/${o.customer.id}`)}>
                    Customer 360 <ExternalLink />
                  </Button>
                )}
              </CardHeader>
              <CardContent className="grid grid-cols-2 gap-4">
                <Field label="Name">{o.customer.name || "—"}</Field>
                <Field label="Phone">{o.customer.phone || "—"}</Field>
                <Field label="Address"><span className="font-normal">{o.customer.address || "—"}</span></Field>
                <Field label="VS Score">{o.customer.vsScore ?? "—"}</Field>
                <Field label="Outstanding">{inr(o.customer.outstanding)}</Field>
                <Field label="Since">{fmtDate(o.customer.since)}</Field>
              </CardContent>
            </Card>

            {/* Payment */}
            <Card>
              <CardHeader><CardTitle>Payment</CardTitle></CardHeader>
              <CardContent className="grid grid-cols-2 gap-4">
                <Field label="Method"><span className="uppercase">{o.payment.method}</span></Field>
                <Field label="Status"><StatusBadge status={o.payment.status} /></Field>
                {o.payment.creditUsed > 0 && <Field label="Credit Used">{inr(o.payment.creditUsed)}</Field>}
                {o.payment.creditPlan && <Field label="Plan">{titleize(o.payment.creditPlan)}</Field>}
                {o.payment.creditDueDate && <Field label="Due Date">{fmtDate(o.payment.creditDueDate)}</Field>}
              </CardContent>
            </Card>

            {/* Delivery */}
            <Card>
              <CardHeader><CardTitle>Delivery</CardTitle></CardHeader>
              <CardContent className="grid grid-cols-2 gap-4">
                <Field label="Agent">{o.delivery.agent || "Unassigned"}</Field>
                <Field label="Status"><StatusBadge status={o.delivery.status ?? "—"} /></Field>
                <Field label="Assigned">{o.delivery.assignedAt ? fmtDate(o.delivery.assignedAt, true) : "—"}</Field>
                <Field label="Picked Up">{o.delivery.pickedUpAt ? fmtDate(o.delivery.pickedUpAt, true) : "—"}</Field>
                <Field label="Out for Delivery">{o.delivery.outForDeliveryAt ? fmtDate(o.delivery.outForDeliveryAt, true) : "—"}</Field>
                <Field label="Delivered">{o.delivery.deliveredAt ? fmtDate(o.delivery.deliveredAt, true) : "—"}</Field>
                <Field label="Distance">{o.delivery.distanceKm != null ? `${o.delivery.distanceKm} km` : "—"}</Field>
                <Field label="ETA">{o.delivery.eta ? fmtDate(o.delivery.eta, true) : "—"}</Field>
                {o.delivery.otp && (
                  <div className="col-span-2 mt-1 flex items-center justify-between rounded-md border border-amber-300 bg-amber-50 px-3 py-2">
                    <div>
                      <p className="text-xs font-medium text-amber-800">Delivery OTP</p>
                      <p className="text-xs text-amber-700">
                        For support escalations only — share with the customer if they&apos;re
                        having trouble with the agent.
                      </p>
                    </div>
                    <span className="font-mono text-lg font-bold tracking-widest text-amber-900">
                      {o.delivery.otp}
                    </span>
                  </div>
                )}
              </CardContent>
            </Card>
          </div>

          {/* Credit (credit orders only) + Inventory Impact */}
          <div className="grid gap-4 lg:grid-cols-2">
            {o.credit.isCredit && (
              <Card>
                <CardHeader><CardTitle>Credit Information</CardTitle></CardHeader>
                <CardContent className="grid grid-cols-2 gap-4">
                  <Field label="Credit Used">{inr(o.credit.creditUsed ?? 0)}</Field>
                  <Field label="Available Limit">{inr(o.credit.availableLimit ?? 0)}</Field>
                  <Field label="Outstanding Before">{o.credit.outstandingBefore != null ? inr(o.credit.outstandingBefore) : "—"}</Field>
                  <Field label="Outstanding After">{o.credit.outstandingAfter != null ? inr(o.credit.outstandingAfter) : "—"}</Field>
                  <Field label="Due Date">{o.credit.dueDate ? fmtDate(o.credit.dueDate) : "—"}</Field>
                  <Field label="Collection"><StatusBadge status={o.credit.collectionStatus} /></Field>
                </CardContent>
              </Card>
            )}

            <Card className={o.credit.isCredit ? "" : "lg:col-span-2"}>
              <CardHeader><CardTitle>Inventory Impact</CardTitle></CardHeader>
              <CardContent>
                {o.inventoryImpact.length === 0 ? (
                  <p className="text-sm text-muted-foreground">No tracked-stock items on this order.</p>
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow className="hover:bg-transparent">
                        <TableHead>Product</TableHead>
                        <TableHead className="text-right">Before</TableHead>
                        <TableHead className="text-right">Ordered</TableHead>
                        <TableHead className="text-right">Remaining</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {o.inventoryImpact.map((r, i) => (
                        <TableRow key={i} className="hover:bg-transparent">
                          {/* `/admin/orders/<code>` only serialises the item NAME
                              (an OrderItem snapshot) — no product id — so this
                              renders as plain text until the API carries one. */}
                          <TableCell><ProductLink name={r.name} className="font-medium" /></TableCell>
                          <TableCell className="text-right tabular-nums">{r.before ?? "—"}</TableCell>
                          <TableCell className="text-right tabular-nums">{r.ordered}</TableCell>
                          <TableCell className="text-right tabular-nums font-medium">{r.remaining ?? "—"}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                )}
              </CardContent>
            </Card>
          </div>

          {/* Items + totals */}
          <Card>
            <CardHeader><CardTitle>Items</CardTitle></CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead>Product</TableHead>
                    <TableHead className="text-right">Qty</TableHead>
                    <TableHead className="text-right">MRP</TableHead>
                    <TableHead className="text-right">Price</TableHead>
                    <TableHead className="text-right">Discount</TableHead>
                    <TableHead className="text-right">Total</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {o.items.map((it, i) => (
                    <TableRow key={i} className="hover:bg-transparent">
                      <TableCell>
                        {/* Same here — OrderItem carries a name snapshot only. */}
                        <p><ProductLink name={it.name} className="font-medium" /></p>
                        {it.brand && <p className="text-xs text-muted-foreground">{it.brand}</p>}
                      </TableCell>
                      <TableCell className="text-right tabular-nums">{it.quantity}</TableCell>
                      <TableCell className="text-right tabular-nums">{inr(it.mrp)}</TableCell>
                      <TableCell className="text-right tabular-nums">{inr(it.price)}</TableCell>
                      <TableCell className="text-right tabular-nums text-muted-foreground">{inr(it.discount)}</TableCell>
                      <TableCell className="text-right font-medium tabular-nums">{inr(it.total)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
              <div className="mt-4 ml-auto max-w-xs space-y-1.5 text-sm">
                <Row label="Subtotal" value={inr(o.totals.subtotal)} />
                <Row label="Discount" value={`− ${inr(o.totals.discount)}`} />
                <Row label="GST" value={inr(o.totals.gst)} />
                <Row label="Delivery" value={inr(o.totals.deliveryFee)} />
                <Row label="Platform Fee" value={inr(o.totals.platformFee)} />
                <div className="border-t pt-1.5">
                  <Row label="Grand Total" value={inr(o.totals.total)} bold />
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Timeline */}
          <Card>
            <CardHeader><CardTitle>Timeline</CardTitle></CardHeader>
            <CardContent>
              {o.timeline.length === 0 ? (
                <p className="text-sm text-muted-foreground">No events.</p>
              ) : (
                <ol className="relative space-y-4 border-l pl-6">
                  {o.timeline.map((e, i) => (
                    <li key={i} className="relative">
                      <span className="absolute -left-[1.65rem] top-1 size-3 rounded-full border-2 border-card bg-primary" />
                      <div className="flex items-center justify-between gap-2">
                        <span className="text-sm font-medium">{titleize(e.status)}</span>
                        <span className="text-xs text-muted-foreground">{fmtDate(e.at, true)}</span>
                      </div>
                      {e.note && <p className="text-xs text-muted-foreground">{e.note}{e.by ? ` · ${e.by}` : ""}</p>}
                    </li>
                  ))}
                </ol>
              )}
            </CardContent>
          </Card>
        </>
      )}
    </>
  );
}

function Row({ label, value, bold }: { label: string; value: string; bold?: boolean }) {
  return (
    <div className={"flex items-center justify-between " + (bold ? "font-bold" : "text-muted-foreground")}>
      <span>{label}</span>
      <span className={bold ? "" : "text-foreground"}>{value}</span>
    </div>
  );
}
