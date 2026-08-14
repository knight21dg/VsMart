"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, FileText, TriangleAlert } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { AuthImage } from "@/components/auth-image";
import { ErrorState, LoadingState } from "@/components/states";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { downloadPdf } from "@/lib/pdf";
import { inr, fmtDate, titleize } from "@/lib/utils";
import { ConfirmDialog } from "@/components/confirm-dialog";
import {
  AGENT_OWNED_STATUSES,
  NEXT_STATUS,
  TERMINAL_STATUSES,
  TERMINAL_STATUS_COPY,
  type OrderDetail,
} from "@/lib/orders";

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="mt-0.5 text-sm font-medium">{children}</div>
    </div>
  );
}

function Row({ label, value, bold = false }: { label: string; value: string; bold?: boolean }) {
  return (
    <div className={`flex justify-between gap-6 ${bold ? "border-t pt-2 font-bold" : ""}`}>
      <span className={bold ? "" : "text-muted-foreground"}>{label}</span>
      <span>{value}</span>
    </div>
  );
}

export default function StoreOrderDetailPage() {
  return (
    <RequirePerm perm="orders.view">
      <OrderDetailInner />
    </RequirePerm>
  );
}

function OrderDetailInner() {
  // Next 16 passes `params` as a Promise to server components, but this is a
  // client page — useParams() reads the segment synchronously, matching the
  // convention already used by inventory/products/[id]/edit.
  const { code } = useParams<{ code: string }>();
  const router = useRouter();
  const { hasPerm } = useStore();
  const canManage = hasPerm("orders.manage");

  // Same cache key the orders list drawer used, so navigating from the list
  // reuses an already-fetched order instead of refetching it.
  const detailQ = useQuery({
    queryKey: ["store", "orders", "detail", code],
    queryFn: () => api.get<OrderDetail>(`/store/orders/${code}`),
  });

  // Cancelling and rejecting are irreversible and move real money (a prepaid
  // order is refunded through the gateway), so they are confirmed rather than
  // fired straight off a dropdown selection.
  const [confirming, setConfirming] = React.useState<string | null>(null);

  const setStatusM = useApiMutation(
    ({ status }: { status: string }) => api.post(`/store/orders/${code}/status`, { status }),
    {
      invalidate: [["store", "orders"], ["store", "orders", "detail", code]],
      successMessage: "Order updated",
      onDone: () => setConfirming(null),
    },
  );

  function chooseStatus(status: string) {
    if (TERMINAL_STATUSES.includes(status)) setConfirming(status);
    else setStatusM.mutate({ status });
  }

  const d = detailQ.data;

  if (detailQ.isLoading) return <LoadingState label="Loading order…" />;
  if (detailQ.error || !d) {
    return (
      <ErrorState
        message="Couldn't load this order. It may belong to another store."
        onRetry={() => detailQ.refetch()}
      />
    );
  }

  const closable =
    !AGENT_OWNED_STATUSES.includes(d.header.status) &&
    !["cancelled", "returned"].includes(d.header.status);
  const withAgent = AGENT_OWNED_STATUSES.includes(d.header.status);

  return (
    <div className="space-y-5">
      <Button variant="ghost" size="sm" className="-ml-2" onClick={() => router.back()}>
        <ArrowLeft className="mr-1.5 size-4" />
        Back
      </Button>

      <PageHeader
        title={`Order ${d.header.code}`}
        description={[
          fmtDate(d.header.placedAt, true),
          d.header.store,
          d.header.zone,
          d.header.source,
        ]
          .filter(Boolean)
          .join(" · ")}
        actions={
          <div className="flex items-center gap-2">
            {canManage && closable && (
              <Select value="" onValueChange={chooseStatus} disabled={setStatusM.isPending}>
                <SelectTrigger className="h-9 w-[170px] text-xs">
                  <SelectValue placeholder="Advance status…" />
                </SelectTrigger>
                <SelectContent>
                  {NEXT_STATUS.map((s) => (
                    <SelectItem key={s} value={s}>{titleize(s)}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            )}
            <Button
              variant="outline"
              size="sm"
              onClick={() => downloadPdf(`/store/orders/${code}/invoice`, `invoice-${code}.pdf`)}
            >
              <FileText className="mr-2 size-4" />
              Invoice
            </Button>
          </div>
        }
      />

      {/* Status strip */}
      <div className="rounded-xl border bg-card p-5">
        <div className="mb-4 flex flex-wrap items-center gap-2">
          <StatusBadge status={d.header.status} />
          <StatusBadge status={d.header.paymentStatus} />
          {d.header.deliveryStatus && <StatusBadge status={d.header.deliveryStatus} />}
          <span className="ml-auto rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
            {d.header.customerType}
          </span>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <Field label="Placed">{fmtDate(d.header.placedAt, true)}</Field>
          <Field label="Source">{titleize(d.header.source)}</Field>
          <Field label="Created by">{d.header.createdBy || "—"}</Field>
          <Field label="Est. delivery">
            {d.header.estimatedDelivery ? fmtDate(d.header.estimatedDelivery, true) : "—"}
          </Field>
        </div>
        {(d.exceptions?.length ?? 0) > 0 && (
          <div className="mt-4 flex flex-wrap gap-2">
            {d.exceptions.map((x, i) => (
              <span
                key={i}
                className="inline-flex items-center gap-1 rounded-full border border-amber-300 bg-amber-50 px-2.5 py-1 text-xs text-amber-800"
              >
                <TriangleAlert className="size-3" />
                {x}
              </span>
            ))}
          </div>
        )}
        {withAgent && (
          <p className="mt-4 rounded-lg border bg-muted/40 p-3 text-xs text-muted-foreground">
            With the delivery agent now — they take it from here (out for delivery
            → arrived → OTP + photo → delivered).
          </p>
        )}
      </div>

      {/* Customer / Payment / Delivery */}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card>
          <CardHeader><CardTitle>Customer</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <Field label="Name">{d.customer.name ?? "—"}</Field>
            <Field label="Phone">{d.customer.phone ?? "—"}</Field>
            {d.customer.address && (
              <Field label="Address">
                {d.customer.address}
                {d.customer.pincode ? ` · ${d.customer.pincode}` : ""}
              </Field>
            )}
            {d.customer.vsScore != null && <Field label="VS Score">{d.customer.vsScore}</Field>}
            {d.customer.outstanding > 0 && (
              <Field label="Outstanding">{inr(d.customer.outstanding)}</Field>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Payment</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <Field label="Method">{titleize(d.payment.method)}</Field>
            <Field label="Status">{titleize(d.payment.status)}</Field>
            {d.payment.creditUsed > 0 && <Field label="On credit">{inr(d.payment.creditUsed)}</Field>}
            {d.payment.creditPlan && <Field label="Plan">{d.payment.creditPlan}</Field>}
            {d.payment.creditDueDate && (
              <Field label="Credit due">{fmtDate(d.payment.creditDueDate)}</Field>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader><CardTitle>Delivery</CardTitle></CardHeader>
          <CardContent className="space-y-3">
            <Field label="Agent">{d.delivery.agent ?? "Unassigned"}</Field>
            {d.delivery.status && <Field label="Status">{titleize(d.delivery.status)}</Field>}
            {d.delivery.distanceKm != null && (
              <Field label="Distance">{`${d.delivery.distanceKm} km`}</Field>
            )}
            {d.delivery.deliveredAt && (
              <Field label="Delivered">{fmtDate(d.delivery.deliveredAt, true)}</Field>
            )}
            {d.delivery.otp && (
              <div className="flex items-center justify-between rounded-md border border-amber-300 bg-amber-50 px-3 py-2">
                <div>
                  <p className="text-xs font-medium text-amber-800">Delivery OTP</p>
                  <p className="text-xs text-amber-700">
                    Only share this with the customer if they&apos;re having trouble
                    with the agent.
                  </p>
                </div>
                <span className="font-mono text-lg font-bold tracking-widest text-amber-900">
                  {d.delivery.otp}
                </span>
              </div>
            )}
            {d.delivery.photoUrl && (
              <div>
                <p className="mb-1.5 text-xs uppercase tracking-wide text-muted-foreground">
                  Confirmation photo
                </p>
                <AuthImage
                  path={d.delivery.photoUrl}
                  alt="Delivery confirmation"
                  className="h-48 w-full rounded-md border object-cover"
                />
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Credit + inventory impact */}
      <div className="grid gap-4 lg:grid-cols-2">
        {d.credit?.isCredit && (
          <Card>
            <CardHeader><CardTitle>Credit</CardTitle></CardHeader>
            <CardContent className="space-y-2 text-sm">
              {d.credit.creditUsed != null && (
                <Row label="Credit used" value={inr(d.credit.creditUsed)} />
              )}
              {d.credit.availableLimit != null && (
                <Row label="Available limit" value={inr(d.credit.availableLimit)} />
              )}
              {d.credit.outstandingBefore != null && (
                <Row label="Outstanding before" value={inr(d.credit.outstandingBefore)} />
              )}
              {d.credit.outstandingAfter != null && (
                <Row label="Outstanding after" value={inr(d.credit.outstandingAfter)} />
              )}
              {d.credit.dueDate && <Row label="Due date" value={fmtDate(d.credit.dueDate)} />}
              {d.credit.collectionStatus && (
                <Row label="Collection" value={titleize(d.credit.collectionStatus)} />
              )}
            </CardContent>
          </Card>
        )}

        {(d.inventoryImpact?.length ?? 0) > 0 && (
          <Card>
            <CardHeader><CardTitle>Inventory impact</CardTitle></CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead>Product</TableHead>
                    <TableHead className="text-right">Ordered</TableHead>
                    <TableHead className="text-right">Before</TableHead>
                    <TableHead className="text-right">Remaining</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {d.inventoryImpact.map((r, i) => (
                    <TableRow key={i}>
                      <TableCell className="font-medium">{r.name}</TableCell>
                      <TableCell className="text-right tabular-nums">{r.ordered}</TableCell>
                      <TableCell className="text-right tabular-nums">{r.before ?? "—"}</TableCell>
                      <TableCell className="text-right tabular-nums">{r.remaining ?? "—"}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        )}
      </div>

      {/* Items + bill */}
      <Card>
        <CardHeader><CardTitle>Items ({d.items.length})</CardTitle></CardHeader>
        <CardContent className="space-y-4">
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
              {d.items.map((it, i) => (
                <TableRow key={i}>
                  <TableCell>
                    <div className="font-medium">{it.name}</div>
                    {it.brand && (
                      <div className="text-xs text-muted-foreground">{it.brand}</div>
                    )}
                  </TableCell>
                  <TableCell className="text-right tabular-nums">{it.quantity}</TableCell>
                  <TableCell className="text-right">{inr(it.mrp)}</TableCell>
                  <TableCell className="text-right">{inr(it.price)}</TableCell>
                  <TableCell className="text-right">
                    {it.discount > 0 ? `− ${inr(it.discount)}` : "—"}
                  </TableCell>
                  <TableCell className="text-right font-medium">{inr(it.total)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>

          <div className="ml-auto w-full max-w-xs space-y-2 text-sm">
            <Row label="Subtotal" value={inr(d.totals.subtotal)} />
            {d.totals.discount > 0 && <Row label="Discount" value={`− ${inr(d.totals.discount)}`} />}
            <Row label="GST" value={inr(d.totals.gst)} />
            {d.totals.deliveryFee > 0 && <Row label="Delivery" value={inr(d.totals.deliveryFee)} />}
            {d.totals.platformFee > 0 && <Row label="Platform fee" value={inr(d.totals.platformFee)} />}
            <Row label="Total" value={inr(d.totals.total)} bold />
          </div>
        </CardContent>
      </Card>

      {/* Timeline */}
      {d.timeline.length > 0 && (
        <Card>
          <CardHeader><CardTitle>Timeline</CardTitle></CardHeader>
          <CardContent>
            <ol className="space-y-3">
              {d.timeline.map((e, i) => (
                <li key={i} className="flex gap-3">
                  <div className="mt-1.5 size-2 shrink-0 rounded-full bg-primary" />
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium">{titleize(e.status)}</p>
                    <p className="text-xs text-muted-foreground">
                      {fmtDate(e.at, true)}
                      {e.by ? ` · ${e.by}` : ""}
                      {e.note ? ` · ${e.note}` : ""}
                    </p>
                  </div>
                </li>
              ))}
            </ol>
          </CardContent>
        </Card>
      )}

      <ConfirmDialog
        open={confirming !== null}
        onOpenChange={(o) => !o && setConfirming(null)}
        title={confirming ? TERMINAL_STATUS_COPY[confirming]?.title ?? "Are you sure?" : ""}
        description={confirming ? TERMINAL_STATUS_COPY[confirming]?.body : undefined}
        confirmLabel={confirming ? titleize(confirming) : "Confirm"}
        destructive
        loading={setStatusM.isPending}
        onConfirm={() => confirming && setStatusM.mutate({ status: confirming })}
      />
    </div>
  );
}
