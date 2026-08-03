"use client";

import * as React from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { toast } from "sonner";
import { inr, fmtDate, titleize } from "@/lib/utils";
import {
  AGENT_OWNED_STATUSES, NEXT_STATUS, STATUS_FILTERS,
  type BulkResult, type OrderRow,
} from "@/lib/orders";

export default function OrdersPage() {
  return (
    <RequirePerm perm="orders.view">
      <OrdersInner />
    </RequirePerm>
  );
}

function OrdersInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("orders.manage");
  const [status, setStatus] = React.useState("all");
  const [selected, setSelected] = React.useState<string[]>([]);
  const [bulkTo, setBulkTo] = React.useState<string | null>(null);

  const q = useQuery({
    queryKey: ["store", "orders", status],
    queryFn: () => api.get<OrderRow[]>("/store/orders", status === "all" ? {} : { status }),
  });

  // A selection carried across a filter change would act on rows no longer shown.
  React.useEffect(() => { setSelected([]); }, [status]);

  const bulk = useApiMutation<{ status: string }, BulkResult>(
    ({ status: s }) => api.post<BulkResult>("/store/orders/bulk-status", { status: s, codes: selected }),
    {
      invalidate: [["store", "orders"]],
      onDone: (res) => {
        setSelected([]);
        // Report what actually happened — a partial sweep is the normal case
        // when someone re-selects orders an agent has already taken.
        if (res.failedCount === 0) {
          toast.success(`${res.updatedCount} order${res.updatedCount === 1 ? "" : "s"} updated.`);
        } else {
          toast.warning(
            `${res.updatedCount} updated, ${res.failedCount} skipped — ` +
            `${res.failed.slice(0, 3).map((f) => f.code).join(", ")}` +
            `${res.failed.length > 3 ? "…" : ""}`,
          );
        }
      },
    },
  );

  const setStatusM = useApiMutation(
    ({ code, status }: { code: string; status: string }) => api.post(`/store/orders/${code}/status`, { status }),
    { invalidate: [["store", "orders"]], successMessage: "Order updated" }
  );

  const columns: ColumnDef<OrderRow, unknown>[] = [
    {
      header: "Order",
      accessorKey: "code",
      cell: ({ row }) => (
        <Link
          href={`/orders/${row.original.code}`}
          className="font-mono text-sm text-primary hover:underline"
        >
          {row.original.code}
        </Link>
      ),
    },
    {
      header: "Customer",
      cell: ({ row }) => (
        <div><div className="text-sm">{row.original.customer ?? "—"}</div>
          <div className="text-xs text-muted-foreground">{row.original.phone}</div></div>
      ),
    },
    { header: "Items", accessorKey: "items", cell: ({ row }) => <span className="text-sm">{row.original.items}</span> },
    { header: "Amount", cell: ({ row }) => <span className="font-medium">{inr(row.original.value)}</span> },
    { header: "Payment", cell: ({ row }) => <span className="text-sm">{titleize(row.original.paymentMethod)}</span> },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { header: "Placed", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.placedAt, true)}</span> },
    {
      header: "",
      id: "actions",
      cell: ({ row }) =>
        canManage &&
        !AGENT_OWNED_STATUSES.includes(row.original.status) &&
        !["cancelled", "returned"].includes(row.original.status) ? (
          <Select onValueChange={(s) => setStatusM.mutate({ code: row.original.code, status: s })}>
            <SelectTrigger className="h-8 w-[140px] text-xs"><SelectValue placeholder="Update…" /></SelectTrigger>
            <SelectContent>
              {NEXT_STATUS.map((s) => <SelectItem key={s} value={s}>{titleize(s)}</SelectItem>)}
            </SelectContent>
          </Select>
        ) : (
          AGENT_OWNED_STATUSES.includes(row.original.status) && (
            <span className="text-xs text-muted-foreground">With agent</span>
          )
        ),
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader title="Orders" description="Every order routed to your store." />
      <DataTable
        columns={columns}
        data={q.data ?? []}
        loading={q.isLoading}
        error={q.error ? "Couldn't load orders." : null}
        onRetry={() => q.refetch()}
        emptyMessage="No orders in this view."
        rowId={canManage ? (r) => r.code : undefined}
        selected={canManage ? selected : undefined}
        onSelectedChange={canManage ? setSelected : undefined}
        // Only rows the store can still act on are selectable, so select-all
        // can't quietly include orders the backend will refuse.
        selectableRow={(r) =>
          !AGENT_OWNED_STATUSES.includes(r.status) &&
          !["cancelled", "returned"].includes(r.status)}
        toolbar={
          <div className="space-y-2">
            <div className="flex flex-wrap gap-2">
              {STATUS_FILTERS.map((s) => (
                <button
                  key={s}
                  onClick={() => setStatus(s)}
                  className={`rounded-full px-3 py-1 text-xs font-medium transition-colors ${
                    status === s ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:bg-accent"
                  }`}
                >
                  {s === "all" ? "All" : titleize(s)}
                </button>
              ))}
            </div>
            {canManage && selected.length > 0 && (
              <div className="flex flex-wrap items-center gap-2 rounded-lg border bg-muted/40 p-2">
                <span className="text-xs font-medium">
                  {selected.length} selected
                </span>
                <Select value="" onValueChange={setBulkTo}>
                  <SelectTrigger className="ml-auto h-8 w-[190px] text-xs">
                    <SelectValue placeholder="Advance all to…" />
                  </SelectTrigger>
                  <SelectContent>
                    {NEXT_STATUS.map((s) => (
                      <SelectItem key={s} value={s}>{titleize(s)}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <Button variant="ghost" size="sm" onClick={() => setSelected([])}>
                  Clear
                </Button>
              </div>
            )}
          </div>
        }
      />

      <ConfirmDialog
        open={!!bulkTo}
        onOpenChange={(o) => !o && setBulkTo(null)}
        title={`Move ${selected.length} order${selected.length === 1 ? "" : "s"} to ${titleize(bulkTo ?? "")}?`}
        description={
          bulkTo === "cancelled"
            ? `This cancels ${selected.length} order${selected.length === 1 ? "" : "s"}, releases their stock and reverses any credit or payment taken. It can't be undone.`
            : `Each order is updated on its own — if any can no longer move, the rest still go through and you'll be told which were skipped.`
        }
        confirmLabel={bulkTo === "cancelled" ? "Cancel orders" : "Update orders"}
        destructive={bulkTo === "cancelled"}
        loading={bulk.isPending}
        onConfirm={() => {
          if (bulkTo) bulk.mutate({ status: bulkTo });
          setBulkTo(null);
        }}
      />
    </div>
  );
}
