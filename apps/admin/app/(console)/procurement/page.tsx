"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Loader2, Plus, Truck } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { DataTable } from "@/components/data-table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { PayablesTab } from "@/components/payables-tab";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { StatusBadge, BoolBadge } from "@/components/status-badge";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { PODialog } from "@/components/po-dialog";
import type { PageMeta } from "@/lib/types";
import { fmtDate, inr } from "@/lib/utils";

interface Supplier { id: string; name: string; gstin: string; phone: string; email: string; address: string; isActive: boolean }
interface POItem { id: string; productId: string; quantity: number; receivedQuantity: number; unitCost: number }
interface PurchaseOrder { id: string; supplierName: string; supplierId: string | null; warehouseId: string; status: string; expectedAt: string | null; subtotal: number; tax: number; total: number; receivedAt: string | null; items: POItem[] }
interface GRNItem { id: string; productId: string; quantity: number; unitCost: number; batchNo: string; expiryDate: string }
interface GRN { id: string; purchaseOrderId: string; supplierId: string; warehouseId: string; reference: string; status: string; totalCost: number; postedAt: string | null; items: GRNItem[] }

export default function ProcurementPage() {
  const [tab, setTab] = React.useState("suppliers");
  return (
    <>
      <PageHeader title="Procurement" description="Suppliers, purchase orders and goods receipts." />
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="suppliers">Suppliers</TabsTrigger>
          <TabsTrigger value="po">Purchase Orders</TabsTrigger>
          <TabsTrigger value="grn">Goods Receipts</TabsTrigger>
          <TabsTrigger value="ap">Payables</TabsTrigger>
        </TabsList>
        <TabsContent value="suppliers"><SuppliersTab active={tab === "suppliers"} /></TabsContent>
        <TabsContent value="po"><POTab active={tab === "po"} /></TabsContent>
        <TabsContent value="grn"><GRNTab active={tab === "grn"} /></TabsContent>
        <TabsContent value="ap"><PayablesTab active={tab === "ap"} /></TabsContent>
      </Tabs>
    </>
  );
}

function SuppliersTab({ active }: { active: boolean }) {
  const [open, setOpen] = React.useState(false);
  const [form, setForm] = React.useState<Partial<Supplier>>({});
  const [page, setPage] = React.useState(1);
  const query = useQuery({ queryKey: ["inventory", "suppliers", page], queryFn: () => api.getPaged<Supplier>("/inventory/suppliers", { page }), enabled: active });
  const save = useApiMutation((body: Partial<Supplier>) => api.post("/inventory/suppliers", body), {
    invalidate: [["inventory", "suppliers"]],
    successMessage: "Supplier added.",
    onDone: () => setOpen(false),
  });

  const columns: ColumnDef<Supplier, unknown>[] = [
    { accessorKey: "name", header: "Supplier", cell: ({ row }) => <span className="font-medium">{row.original.name}</span> },
    { accessorKey: "gstin", header: "GSTIN", cell: ({ row }) => <span className="font-mono text-xs">{row.original.gstin || "—"}</span> },
    { accessorKey: "phone", header: "Phone" },
    { accessorKey: "email", header: "Email", cell: ({ row }) => <span className="text-muted-foreground">{row.original.email || "—"}</span> },
    { accessorKey: "isActive", header: "Active", cell: ({ row }) => <BoolBadge value={row.original.isActive} /> },
  ];

  return (
    <>
      <div className="mb-3 flex justify-end">
        <Button onClick={() => { setForm({}); setOpen(true); }}><Plus /> New Supplier</Button>
      </div>
      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load suppliers." : null}
        onRetry={() => query.refetch()}
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
        emptyMessage="No suppliers yet."
      />
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle className="flex items-center gap-2"><Truck className="size-4" /> New Supplier</DialogTitle></DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2 space-y-1.5"><Label>Name</Label><Input value={form.name ?? ""} onChange={(e) => setForm({ ...form, name: e.target.value })} /></div>
            <div className="space-y-1.5"><Label>GSTIN</Label><Input value={form.gstin ?? ""} onChange={(e) => setForm({ ...form, gstin: e.target.value })} /></div>
            <div className="space-y-1.5"><Label>Phone</Label><Input value={form.phone ?? ""} onChange={(e) => setForm({ ...form, phone: e.target.value })} /></div>
            <div className="col-span-2 space-y-1.5"><Label>Email</Label><Input value={form.email ?? ""} onChange={(e) => setForm({ ...form, email: e.target.value })} /></div>
            <div className="col-span-2 space-y-1.5"><Label>Address</Label><Input value={form.address ?? ""} onChange={(e) => setForm({ ...form, address: e.target.value })} /></div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setOpen(false)} disabled={save.isPending}>Cancel</Button>
            <Button onClick={() => save.mutate(form)} disabled={save.isPending || !form.name}>
              {save.isPending && <Loader2 className="size-4 animate-spin" />} Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}

function POTab({ active }: { active: boolean }) {
  const [view, setView] = React.useState<PurchaseOrder | null>(null);
  const [creating, setCreating] = React.useState(false);
  const [page, setPage] = React.useState(1);
  const query = useQuery({ queryKey: ["inventory", "po", page], queryFn: () => api.getPaged<PurchaseOrder>("/inventory/purchase-orders", { page }), enabled: active });
  const columns: ColumnDef<PurchaseOrder, unknown>[] = [
    { accessorKey: "id", header: "PO", cell: ({ row }) => <span className="font-mono text-xs">#{row.original.id}</span> },
    { accessorKey: "supplierName", header: "Supplier", cell: ({ row }) => <span className="font-medium">{row.original.supplierName || "—"}</span> },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { accessorKey: "total", header: "Total", cell: ({ row }) => inr(row.original.total) },
    { accessorKey: "receivedAt", header: "Received", cell: ({ row }) => fmtDate(row.original.receivedAt, true) },
  ];
  return (
    <>
      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load purchase orders." : null}
        onRetry={() => query.refetch()}
        onRowClick={setView}
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
        emptyMessage="No purchase orders."
        toolbar={
          <Button size="sm" onClick={() => setCreating(true)}>
            <Plus className="size-4" /> New purchase order
          </Button>
        }
      />
      {creating && <PODialog onClose={() => setCreating(false)} />}
      <Dialog open={!!view} onOpenChange={(o) => !o && setView(null)}>
        <DialogContent className="max-w-xl">
          <DialogHeader><DialogTitle>PO #{view?.id} — {view?.supplierName}</DialogTitle></DialogHeader>
          <div className="space-y-1 text-sm">
            {(view?.items ?? []).map((it) => (
              <div key={it.id} className="flex items-center justify-between border-b py-2">
                <span className="font-mono text-xs">Product #{it.productId}</span>
                <span>{it.receivedQuantity}/{it.quantity} recvd</span>
                <span className="font-medium">{inr(it.unitCost)}</span>
              </div>
            ))}
            <div className="flex justify-between pt-3 font-semibold">
              <span>Total</span><span>{inr(view?.total ?? 0)}</span>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  );
}

function GRNTab({ active }: { active: boolean }) {
  const [view, setView] = React.useState<GRN | null>(null);
  const [toPost, setToPost] = React.useState<GRN | null>(null);
  const [page, setPage] = React.useState(1);
  const query = useQuery({ queryKey: ["inventory", "grn", page], queryFn: () => api.getPaged<GRN>("/inventory/grn", { page }), enabled: active });
  const post = useApiMutation((id: string) => api.post(`/inventory/grn/${id}/post`), {
    invalidate: [["inventory", "grn"], ["inventory", "stock"], ["admin", "inventory"]],
    successMessage: "GRN posted to stock.",
    onDone: () => setToPost(null),
  });
  const columns: ColumnDef<GRN, unknown>[] = [
    { accessorKey: "id", header: "GRN", cell: ({ row }) => <span className="font-mono text-xs">#{row.original.id}</span> },
    { accessorKey: "reference", header: "Reference" },
    { accessorKey: "purchaseOrderId", header: "PO", cell: ({ row }) => <span className="font-mono text-xs">#{row.original.purchaseOrderId}</span> },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { accessorKey: "totalCost", header: "Cost", cell: ({ row }) => inr(row.original.totalCost) },
    {
      id: "actions",
      header: "",
      cell: ({ row }) => (
        <div className="flex justify-end gap-2">
          <Button variant="ghost" size="sm" onClick={() => setView(row.original)}>Items</Button>
          {row.original.status === "draft" && (
            <Button size="sm" disabled={post.isPending} onClick={() => setToPost(row.original)}>
              {post.isPending && <Loader2 className="size-4 animate-spin" />} Post
            </Button>
          )}
        </div>
      ),
    },
  ];
  return (
    <>
      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load goods receipts." : null}
        onRetry={() => query.refetch()}
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
        emptyMessage="No goods receipts."
      />
      <Dialog open={!!view} onOpenChange={(o) => !o && setView(null)}>
        <DialogContent className="max-w-xl">
          <DialogHeader><DialogTitle>GRN #{view?.id} — {view?.reference}</DialogTitle></DialogHeader>
          <div className="space-y-1 text-sm">
            {(view?.items ?? []).map((it) => (
              <div key={it.id} className="flex items-center justify-between border-b py-2">
                <span className="font-mono text-xs">Product #{it.productId}</span>
                <span>{it.quantity} units</span>
                <span className="text-muted-foreground">{it.batchNo || "—"}</span>
                <span className="font-medium">{inr(it.unitCost)}</span>
              </div>
            ))}
          </div>
        </DialogContent>
      </Dialog>
      {toPost && (
        <ConfirmDialog
          open
          onOpenChange={(o) => !o && setToPost(null)}
          title={`Post GRN #${toPost.id} to stock?`}
          description={
            `This adds ${(toPost.items ?? []).reduce((n, it) => n + it.quantity, 0)} units across ` +
            `${(toPost.items ?? []).length} line${(toPost.items ?? []).length === 1 ? "" : "s"} into warehouse stock and ` +
            `books ${inr(toPost.totalCost)} of supplier payable. Stock ledger entries are append-only — posting cannot ` +
            `be undone, only corrected with an adjustment.`
          }
          confirmLabel="Post to stock"
          loading={post.isPending}
          onConfirm={() => post.mutate(toPost.id)}
        />
      )}
    </>
  );
}
