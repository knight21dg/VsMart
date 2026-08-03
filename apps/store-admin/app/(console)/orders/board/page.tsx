"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { Loader2 } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { ErrorState, LoadingState } from "@/components/states";
import { Button } from "@/components/ui/button";
import { fmtDate, inr, titleize } from "@/lib/utils";

interface BoardLine { name: string; unit: string; quantity: number }
interface BoardOrder {
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
  lines: BoardLine[];
}
interface Queues {
  toPack: BoardOrder[];
  packed: BoardOrder[];
  readyForDispatch: BoardOrder[];
  outForDelivery: BoardOrder[];
  counts: { toPack: number; packed: number; readyForDispatch: number; outForDelivery: number };
}

/**
 * Each column and the single action that moves a card out of it. The store's
 * authority ends at ready_for_dispatch — everything after that belongs to the
 * assigned agent's own state machine, so the last column has no action.
 */
const COLUMNS: {
  key: keyof Queues["counts"];
  title: string;
  hint: string;
  advanceTo?: string;
  actionLabel?: string;
}[] = [
  { key: "toPack", title: "To pack", hint: "New orders waiting to be picked", advanceTo: "packed", actionLabel: "Mark packed" },
  { key: "packed", title: "Packed", hint: "Picked and bagged", advanceTo: "ready_for_dispatch", actionLabel: "Ready for pickup" },
  { key: "readyForDispatch", title: "Ready for dispatch", hint: "Waiting for an agent to collect" },
  { key: "outForDelivery", title: "Out for delivery", hint: "With the agent now" },
];

export default function PackingBoardPage() {
  return (
    <RequirePerm perm="orders.view">
      <BoardInner />
    </RequirePerm>
  );
}

function BoardInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("orders.manage");

  const q = useQuery({
    queryKey: ["store", "orders", "queues"],
    queryFn: () => api.get<Queues>("/store/orders/queues"),
    // The board is a live shop-floor view; a packer leaves it open all morning.
    refetchInterval: 30_000,
  });

  const advance = useApiMutation<{ code: string; status: string }>(
    ({ code, status }) => api.post(`/store/orders/${code}/status`, { status }),
    {
      invalidate: [["store", "orders"]],
      successMessage: "Order updated",
    },
  );

  if (q.isLoading) return <LoadingState label="Loading the board…" />;
  if (q.error || !q.data) {
    return <ErrorState message="Couldn't load the packing board." onRetry={() => q.refetch()} />;
  }

  const d = q.data;

  return (
    <div className="space-y-5">
      <PageHeader
        title="Packing Board"
        description="Every order on the floor, with what to pull off the shelf."
      />

      <div className="grid gap-4 lg:grid-cols-4">
        {COLUMNS.map((col) => {
          const orders = d[col.key as keyof Queues] as BoardOrder[];
          return (
            <section key={col.key} className="space-y-3">
              <div className="rounded-lg border bg-muted/40 px-3 py-2">
                <div className="flex items-center justify-between">
                  <h2 className="text-sm font-semibold">{col.title}</h2>
                  <span className="rounded-full bg-background px-2 py-0.5 text-xs font-medium">
                    {d.counts[col.key]}
                  </span>
                </div>
                <p className="text-xs text-muted-foreground">{col.hint}</p>
              </div>

              {orders.length === 0 ? (
                <p className="rounded-lg border border-dashed px-3 py-6 text-center text-xs text-muted-foreground">
                  Nothing here.
                </p>
              ) : (
                orders.map((o) => (
                  <OrderCard
                    key={o.code}
                    order={o}
                    action={
                      canManage && col.advanceTo
                        ? {
                            label: col.actionLabel!,
                            pending: advance.isPending,
                            onClick: () => advance.mutate({ code: o.code, status: col.advanceTo! }),
                          }
                        : null
                    }
                  />
                ))
              )}
            </section>
          );
        })}
      </div>
    </div>
  );
}

function OrderCard({
  order, action,
}: {
  order: BoardOrder;
  action: { label: string; pending: boolean; onClick: () => void } | null;
}) {
  const unpaid = order.paymentStatus !== "paid" && order.paymentMethod !== "cod";

  return (
    <div className="space-y-2 rounded-lg border bg-card p-3">
      <div className="flex items-start justify-between gap-2">
        <Link href={`/orders/${order.code}`} className="font-mono text-xs text-primary hover:underline">
          {order.code}
        </Link>
        <span className="text-xs font-semibold">{inr(order.value)}</span>
      </div>

      <div className="text-xs">
        <p className="font-medium">{order.customer ?? "—"}</p>
        <p className="text-muted-foreground">{fmtDate(order.placedAt, true)}</p>
      </div>

      {/* The pick list — the reason this board exists. Without it a packer had
          to open every order to find out what to pull. */}
      <ul className="space-y-0.5 rounded-md bg-muted/50 p-2 text-xs">
        {order.lines.map((l, i) => (
          <li key={i} className="flex items-baseline justify-between gap-2">
            <span className="truncate">
              {l.name}
              {l.unit && <span className="text-muted-foreground"> · {l.unit}</span>}
            </span>
            <span className="shrink-0 font-semibold tabular-nums">×{l.quantity}</span>
          </li>
        ))}
        {order.lines.length === 0 && (
          <li className="text-muted-foreground">{order.items} item(s)</li>
        )}
      </ul>

      <div className="flex flex-wrap items-center gap-1.5">
        <span className="text-xs text-muted-foreground">{titleize(order.paymentMethod)}</span>
        {/* Staff were packing unpaid orders blind — paymentStatus was returned
            by the API and never shown anywhere. */}
        {unpaid && <StatusBadge status={order.paymentStatus} />}
        {order.agent && (
          <span className="ml-auto text-xs text-muted-foreground">{order.agent}</span>
        )}
      </div>

      {action && (
        <Button
          size="sm"
          variant="outline"
          className="w-full"
          disabled={action.pending}
          onClick={action.onClick}
        >
          {action.pending && <Loader2 className="size-3.5 animate-spin" />} {action.label}
        </Button>
      )}
    </div>
  );
}
