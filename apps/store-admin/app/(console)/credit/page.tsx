"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import type { ColumnDef } from "@tanstack/react-table";
import { Loader2 } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { useStore } from "@/lib/store/store-context";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { RequirePerm } from "@/components/permission-gate";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { inr } from "@/lib/utils";

interface CreditRow {
  customerId: string; name: string; phone: string; creditLimit: number;
  outstanding: number; available: number; vsScore: number; status: string;
}

export default function CreditPage() {
  return (
    <RequirePerm perm="credit.view">
      <CreditInner />
    </RequirePerm>
  );
}

function CreditInner() {
  const { hasPerm } = useStore();
  const canManage = hasPerm("credit.manage");
  const [editing, setEditing] = React.useState<CreditRow | null>(null);

  const q = useQuery({ queryKey: ["store", "credit"], queryFn: () => api.get<CreditRow[]>("/store/credit") });

  const columns: ColumnDef<CreditRow, unknown>[] = [
    {
      header: "Customer",
      cell: ({ row }) => <div><div className="font-medium">{row.original.name}</div><div className="text-xs text-muted-foreground">{row.original.phone}</div></div>,
    },
    { header: "Limit", cell: ({ row }) => <span className="text-sm">{inr(row.original.creditLimit)}</span> },
    { header: "Outstanding", cell: ({ row }) => <span className={row.original.outstanding > 0 ? "font-medium text-destructive" : "text-muted-foreground"}>{inr(row.original.outstanding)}</span> },
    { header: "Available", cell: ({ row }) => <span className="text-sm">{inr(row.original.available)}</span> },
    { header: "VS Score", accessorKey: "vsScore" },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    {
      header: "", id: "actions",
      cell: ({ row }) => canManage ? <Button variant="outline" size="sm" onClick={() => setEditing(row.original)}>Manage</Button> : null,
    },
  ];

  return (
    <div className="space-y-5">
      <PageHeader title="Credit" description="VS Credit limits and outstanding for your store's customers." />
      <DataTable columns={columns} data={q.data ?? []} loading={q.isLoading} error={q.error ? "Couldn't load credit." : null} onRetry={() => q.refetch()} emptyMessage="No credit customers yet." />
      {editing && <CreditDialog row={editing} onClose={() => setEditing(null)} />}
    </div>
  );
}

function CreditDialog({ row, onClose }: { row: CreditRow; onClose: () => void }) {
  const [limit, setLimit] = React.useState(String(row.creditLimit));
  const [status, setStatus] = React.useState(row.status);

  const m = useApiMutation(
    (body: unknown) => api.post(`/store/credit/${row.customerId}`, body),
    { invalidate: [["store", "credit"]], successMessage: "Credit updated", onDone: onClose }
  );

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader><DialogTitle>Credit — {row.name}</DialogTitle></DialogHeader>
        <div className="space-y-3">
          <div className="space-y-1.5">
            <Label>Credit limit (₹)</Label>
            <Input inputMode="numeric" value={limit} onChange={(e) => setLimit(e.target.value)} />
          </div>
          <div className="space-y-1.5">
            <Label>Status</Label>
            <Select value={status} onValueChange={setStatus}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="active">Active</SelectItem>
                <SelectItem value="frozen">Frozen</SelectItem>
                <SelectItem value="closed">Closed</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={m.isPending}>Cancel</Button>
          <Button onClick={() => m.mutate({ creditLimit: Number(limit), status })} disabled={m.isPending}>
            {m.isPending && <Loader2 className="size-4 animate-spin" />} Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
