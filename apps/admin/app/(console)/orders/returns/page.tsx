"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { ArrowLeft } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { ReturnDetailDialog } from "@/components/return-detail-dialog";
import { DataTable } from "@/components/data-table";
import { Button } from "@/components/ui/button";
import { StatusBadge } from "@/components/status-badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { inr, fmtDate, titleize } from "@/lib/utils";
import { ApiError, type PageMeta } from "@/lib/types";

interface ReturnRow {
  code: string;
  orderCode: string | null;
  customer: string | null;
  phone: string | null;
  reason: string;
  status: string;
  refundAmount: number;
  items: number;
  createdAt: string;
}

const STATUSES = ["requested", "approved", "picked", "rejected", "refunded"];
const norm = (v: string) => (v === "all" ? undefined : v);

interface ReturnAction {
  label: string;
  target: string;
  variant?: "default" | "outline" | "destructive";
  /** Terminal/irreversible transitions must be confirmed before firing. */
  confirm?: boolean;
}

// Next valid actions per status → [label, target, variant].
const ACTIONS: Record<string, ReturnAction[]> = {
  requested: [
    { label: "Approve", target: "approved" },
    { label: "Reject", target: "rejected", variant: "destructive", confirm: true },
  ],
  approved: [
    { label: "Mark Picked", target: "picked", variant: "outline" },
    { label: "Refund", target: "refunded", confirm: true },
  ],
  picked: [{ label: "Refund", target: "refunded", confirm: true }],
};

/** Plain-language consequence copy for the confirm dialog. */
function confirmCopy(row: ReturnRow, target: string): { title: string; description: string; confirmLabel: string } {
  if (target === "refunded") {
    return {
      title: `Refund ${inr(row.refundAmount)} for ${row.code}?`,
      description:
        `This reverses ${inr(row.refundAmount)} to ${row.customer || "the customer"}'s credit and puts ` +
        `${row.items} item${row.items === 1 ? "" : "s"} back into stock. This cannot be undone.`,
      confirmLabel: "Refund",
    };
  }
  return {
    title: `Reject return ${row.code}?`,
    description:
      `${row.customer || "The customer"} gets no refund and keeps the ${row.items} item` +
      `${row.items === 1 ? "" : "s"}. Rejection is final — the request cannot be reopened.`,
    confirmLabel: "Reject return",
  };
}

export default function ReturnsPage() {
  const router = useRouter();
  const [status, setStatus] = React.useState("all");
  const [pending, setPending] = React.useState<{ row: ReturnRow; target: string } | null>(null);
  const [reviewing, setReviewing] = React.useState<string | null>(null);

  const [page, setPage] = React.useState(1);
  // A filter change can't leave the operator stranded on a now-empty page.
  React.useEffect(() => { setPage(1); }, [status]);

  const filters = { status: norm(status) };
  const list = useQuery({
    queryKey: ["admin", "returns", filters, page],
    queryFn: () => api.getPaged<ReturnRow>("/admin/returns", { ...filters, page }),
    placeholderData: keepPreviousData,
  });
  const rows = list.data?.rows ?? [];
  const pageMeta = list.data?.meta as PageMeta | undefined;

  const transition = useApiMutation(
    (v: { code: string; status: string }) => api.post(`/admin/returns/${v.code}/status`, { status: v.status }),
    {
      invalidate: [["admin", "returns"]],
      successMessage: "Return updated.",
      onDone: () => setPending(null),
    }
  );

  const columns: ColumnDef<ReturnRow, unknown>[] = [
    {
      accessorKey: "code",
      header: "Return",
      cell: ({ row }) => (
        // Opens the evidence behind the decision. Approve/Reject used to be
        // clickable from this row with nothing but a reason word and an item
        // count on screen — no customer note, no photos.
        <button
          className="text-left"
          onClick={() => setReviewing(row.original.code)}
          title="Review this return"
        >
          <p className="font-mono text-xs font-medium text-primary hover:underline">{row.original.code}</p>
          <p className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt)}</p>
        </button>
      ),
    },
    {
      accessorKey: "orderCode",
      header: "Order",
      cell: ({ row }) => (
        <button className="font-mono text-xs text-primary hover:underline" onClick={() => row.original.orderCode && router.push(`/orders/${row.original.orderCode}`)}>
          {row.original.orderCode ?? "—"}
        </button>
      ),
    },
    {
      accessorKey: "customer",
      header: "Customer",
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="truncate font-medium">{row.original.customer || "—"}</p>
          <p className="font-mono text-xs text-muted-foreground">{row.original.phone}</p>
        </div>
      ),
    },
    { accessorKey: "reason", header: "Reason", cell: ({ row }) => <span className="text-sm">{row.original.reason}</span> },
    { accessorKey: "refundAmount", header: "Refund", cell: ({ row }) => <span className="font-medium">{inr(row.original.refundAmount)}</span> },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      id: "actions",
      header: "Actions",
      cell: ({ row }) => {
        const acts = ACTIONS[row.original.status] ?? [];
        if (acts.length === 0) return <span className="text-xs text-muted-foreground">{titleize(row.original.status)}</span>;
        return (
          <div className="flex gap-1.5">
            {acts.map((a) => (
              <Button
                key={a.target}
                size="sm"
                variant={a.variant ?? "default"}
                disabled={transition.isPending}
                onClick={() =>
                  a.confirm
                    ? setPending({ row: row.original, target: a.target })
                    : transition.mutate({ code: row.original.code, status: a.target })
                }
              >
                {a.label}
              </Button>
            ))}
          </div>
        );
      },
    },
  ];

  return (
    <>
      <Button variant="ghost" size="sm" className="-ml-2 w-fit" onClick={() => router.push("/orders")}>
        <ArrowLeft /> Orders
      </Button>
      <PageHeader title="Returns & Refunds" description="Review return requests and process refunds." />

      <DataTable
        columns={columns}
        data={rows}
        loading={list.isLoading}
        error={list.isError ? (list.error as ApiError)?.message ?? "Failed to load returns." : null}
        onRetry={() => list.refetch()}
        emptyMessage="No return requests."
        pageMeta={pageMeta}
        page={page}
        onPageChange={setPage}
        toolbar={
          <div className="flex items-center gap-2">
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger className="w-[160px]"><SelectValue placeholder="Status" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All Statuses</SelectItem>
                {STATUSES.map((s) => <SelectItem key={s} value={s}>{titleize(s)}</SelectItem>)}
              </SelectContent>
            </Select>
            <span className="ml-auto text-xs text-muted-foreground">{rows.length} returns</span>
          </div>
        }
      />

      {pending && (
        <ConfirmDialog
          open
          onOpenChange={(o) => !o && setPending(null)}
          {...confirmCopy(pending.row, pending.target)}
          destructive
          loading={transition.isPending}
          onConfirm={() => transition.mutate({ code: pending.row.code, status: pending.target })}
        />
      )}

      <ReturnDetailDialog code={reviewing} onClose={() => setReviewing(null)} />
    </>
  );
}
