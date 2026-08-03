"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Play, Trash2 } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { Button } from "@/components/ui/button";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { inr, fmtDate } from "@/lib/utils";

interface DraftRow {
  id: string; label: string; customerName: string | null;
  itemCount: number; total: number | null; createdAt: string;
}

export default function POSDraftsPage() {
  return (
    <RequirePerm perm="pos.operate">
      <Inner />
    </RequirePerm>
  );
}

function Inner() {
  const router = useRouter();
  const q = useQuery({ queryKey: ["store", "pos", "drafts"], queryFn: () => api.get<DraftRow[]>("/store/pos/drafts") });
  const [toDelete, setToDelete] = React.useState<DraftRow | null>(null);

  const del = useApiMutation((id: string) => api.del(`/store/pos/drafts/${id}`), {
    invalidate: [["store", "pos", "drafts"]], successMessage: "Draft discarded", onDone: () => setToDelete(null),
  });

  const columns: ColumnDef<DraftRow, unknown>[] = [
    { header: "Label", cell: ({ row }) => <span className="font-medium">{row.original.label || "Untitled"}</span> },
    { header: "Customer", cell: ({ row }) => <span className="text-muted-foreground">{row.original.customerName || "Walk-in"}</span> },
    { header: "Items", accessorKey: "itemCount", cell: ({ row }) => <span className="tabular-nums">{row.original.itemCount}</span> },
    { header: "Total", cell: ({ row }) => (row.original.total != null ? inr(row.original.total) : "—") },
    { header: "Saved", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt, true)}</span> },
    {
      header: "", id: "actions",
      cell: ({ row }) => (
        <div className="flex justify-end gap-1">
          <Button size="sm" onClick={() => router.push(`/pos?resume=${row.original.id}`)}>
            <Play className="size-3.5" /> Resume
          </Button>
          <Button variant="ghost" size="icon" className="text-destructive" onClick={() => setToDelete(row.original)}>
            <Trash2 className="size-4" />
          </Button>
        </div>
      ),
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader title="POS Drafts" description="Parked carts you can resume at the counter." />
      <DataTable
        columns={columns}
        data={q.data ?? []}
        loading={q.isLoading}
        error={q.error ? "Couldn't load drafts." : null}
        onRetry={() => q.refetch()}
        emptyMessage="No parked carts. Use Draft at the POS to save one."
      />
      <ConfirmDialog
        open={!!toDelete}
        onOpenChange={(o) => !o && setToDelete(null)}
        title="Discard this draft?"
        description="The parked cart will be permanently removed."
        confirmLabel="Discard"
        destructive
        loading={del.isPending}
        onConfirm={() => toDelete && del.mutate(toDelete.id)}
      />
    </div>
  );
}
