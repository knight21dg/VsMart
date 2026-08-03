"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { ClipboardCheck, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { InvNav } from "@/components/inventory/inv-nav";
import { PageHeader } from "@/components/page-header";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { DataTable } from "@/components/data-table";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { AuditRow } from "@/lib/inventory";
import { fmtDate } from "@/lib/utils";

interface InvProduct { id: string; name: string }
interface Warehouse { id: string; name: string; code: string }

export default function AuditPage() {
  const [open, setOpen] = React.useState(false);
  const [product, setProduct] = React.useState("");
  const [warehouse, setWarehouse] = React.useState("");
  const [counted, setCounted] = React.useState("");
  const [reason, setReason] = React.useState("");
  const [confirming, setConfirming] = React.useState(false);

  const audit = useQuery({ queryKey: ["inv", "audit"], queryFn: () => api.get<AuditRow[]>("/inventory/audit") });
  const products = useQuery({ queryKey: ["admin", "inventory", "all"], queryFn: () => api.getPaged<InvProduct>("/admin/inventory", { page_size: 100 }), enabled: open });
  const warehouses = useQuery({ queryKey: ["inventory", "warehouses"], queryFn: () => api.getPaged<Warehouse>("/inventory/warehouses"), enabled: open });

  const count = useApiMutation(
    (body: Record<string, unknown>) => api.post<{ systemCount: number; physicalCount: number; variance: number }>("/inventory/physical-count", body),
    {
      invalidate: [["inv", "audit"], ["inv"], ["admin", "inventory"]],
      onDone: (d) => {
        toast.success(`Recorded. Variance ${d.variance > 0 ? "+" : ""}${d.variance} (system ${d.systemCount} → counted ${d.physicalCount}).`);
        setConfirming(false);
        setOpen(false);
        setCounted("");
        setReason("");
      },
    }
  );

  const productName = (products.data?.rows ?? []).find((p) => p.id === product)?.name ?? "";
  const selectedWarehouse = (warehouses.data?.rows ?? []).find((w) => w.id === warehouse);
  const warehouseName = selectedWarehouse ? `${selectedWarehouse.name} (${selectedWarehouse.code})` : "";

  const columns: ColumnDef<AuditRow, unknown>[] = [
    { accessorKey: "createdAt", header: "Time", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt, true)}</span> },
    { accessorKey: "product", header: "Product", cell: ({ row }) => <span className="font-medium">{row.original.product}</span> },
    {
      id: "previous",
      header: "From",
      cell: ({ row }) => <span className="tabular-nums text-muted-foreground">{row.original.newCount - row.original.delta}</span>,
    },
    {
      accessorKey: "newCount",
      header: "To (New Count)",
      cell: ({ row }) => {
        const up = row.original.delta >= 0;
        return (
          <span className={"font-medium tabular-nums " + (up ? "text-[var(--color-success)]" : "text-destructive")}>
            {row.original.newCount}
            <span className="ml-1.5 text-xs font-normal">({row.original.delta > 0 ? "+" : ""}{row.original.delta})</span>
          </span>
        );
      },
    },
    { accessorKey: "reason", header: "Reason", cell: ({ row }) => <span className="text-muted-foreground">{row.original.reason || "—"}</span> },
    { accessorKey: "by", header: "By", cell: ({ row }) => <Badge variant="secondary">{row.original.by}</Badge> },
  ];

  return (
    <>
      <PageHeader
        title="Inventory Audit"
        description="Every stock adjustment, append-only — and physical-count reconciliation."
        actions={<Button onClick={() => setOpen(true)}><ClipboardCheck /> Physical Count</Button>}
      />
      <InvNav />
      <DataTable
        columns={columns}
        data={audit.data ?? []}
        loading={audit.isLoading}
        error={audit.isError ? "Failed to load audit trail." : null}
        onRetry={() => audit.refetch()}
        emptyMessage="No adjustments recorded."
      />

      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader><DialogTitle className="flex items-center gap-2"><ClipboardCheck className="size-4" /> Physical Count</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label>Product</Label>
              <Select value={product} onValueChange={setProduct}>
                <SelectTrigger><SelectValue placeholder="Select product" /></SelectTrigger>
                <SelectContent>
                  {(products.data?.rows ?? []).map((p) => <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Warehouse</Label>
              <Select value={warehouse} onValueChange={setWarehouse}>
                <SelectTrigger><SelectValue placeholder="Select warehouse" /></SelectTrigger>
                <SelectContent>
                  {(warehouses.data?.rows ?? []).map((w) => <SelectItem key={w.id} value={w.id}>{w.name} ({w.code})</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5"><Label>Counted quantity</Label><Input type="number" value={counted} onChange={(e) => setCounted(e.target.value)} /></div>
            <div className="space-y-1.5"><Label>Reason</Label><Input value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Cycle count / shrinkage / correction" /></div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setOpen(false)} disabled={count.isPending}>Cancel</Button>
            <Button
              disabled={count.isPending || !product || !warehouse || counted === ""}
              onClick={() => setConfirming(true)}
            >
              {count.isPending && <Loader2 className="size-4 animate-spin" />} Record count
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title={`Set on-hand to ${counted} units?`}
        description={
          `A physical count overwrites stock with an absolute value — it does not add to it. ` +
          `${productName || "This product"} at ${warehouseName || "the selected warehouse"} will be set to exactly ` +
          `${counted} units and the difference posted as a variance adjustment. The audit ledger is append-only, ` +
          `so a wrong number can only be corrected by another count.`
        }
        confirmLabel="Record count"
        destructive
        loading={count.isPending}
        onConfirm={() => count.mutate({ product: Number(product), warehouse: Number(warehouse), counted: Number(counted), reason })}
      />
    </>
  );
}
