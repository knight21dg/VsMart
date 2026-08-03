"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { ArrowRight, Loader2, Send, Wand2 } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { InvNav } from "@/components/inventory/inv-nav";
import { DataTable } from "@/components/data-table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { StatusBadge } from "@/components/status-badge";
import { ProductLink } from "@/components/product-link";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { titleize } from "@/lib/utils";

/**
 * Stock transfers — move stock between stores.
 *
 * The engine, the endpoints and even the rebalancing suggestions all existed and
 * had NO user interface: `/inventory/transfer-suggestions` computed where stock
 * was stranded and nobody could see it, and the only way to actually move stock
 * was a raw API call. Surplus sat in one store while another stocked out.
 *
 * A transfer posts two conserving ledger rows (out + in), so it's a real stock
 * movement, not an edit.
 */

interface Warehouse { id: string; name: string; code: string }
interface Transfer {
  id: string; product_id: string; from_warehouse_id: string;
  to_warehouse_id: string; quantity: number; status: string; note: string;
}
interface Suggestion {
  product_id: string; name: string;
  from_warehouse_id: string; from_warehouse: string;
  to_warehouse_id: string; to_warehouse: string;
  quantity: number; reason: string;
}
interface ProductHit { id: string; name: string }

export default function TransfersPage() {
  const [tab, setTab] = React.useState("suggested");
  const [prefill, setPrefill] = React.useState<Suggestion | null>(null);
  const [open, setOpen] = React.useState(false);

  const warehouses = useQuery({
    queryKey: ["inventory", "warehouses"],
    queryFn: () => api.get<Warehouse[]>("/inventory/warehouses"),
  });

  return (
    <>
      <PageHeader
        title="Stock Transfers"
        description="Move stock between stores — surplus at one, shortage at another."
        actions={<Button onClick={() => { setPrefill(null); setOpen(true); }}><Send className="size-4" /> New transfer</Button>}
      />
      <InvNav />
      <Tabs value={tab} onValueChange={setTab}>
        <TabsList>
          <TabsTrigger value="suggested">Suggested</TabsTrigger>
          <TabsTrigger value="history">History</TabsTrigger>
        </TabsList>
        <TabsContent value="suggested">
          <Suggested onTransfer={(s) => { setPrefill(s); setOpen(true); }} />
        </TabsContent>
        <TabsContent value="history">
          <History warehouses={warehouses.data ?? []} />
        </TabsContent>
      </Tabs>

      {open && (
        <TransferDialog
          warehouses={warehouses.data ?? []}
          prefill={prefill}
          onClose={() => setOpen(false)}
        />
      )}
    </>
  );
}

/* ── Suggestions: where stock is stranded ─────────────────────────────── */
function Suggested({ onTransfer }: { onTransfer: (s: Suggestion) => void }) {
  const q = useQuery({
    queryKey: ["inventory", "transfer-suggestions"],
    queryFn: () => api.get<{ suggestions: Suggestion[] }>("/inventory/transfer-suggestions"),
  });
  const rows = q.data?.suggestions ?? [];

  const columns: ColumnDef<Suggestion, unknown>[] = [
    { header: "Product", cell: ({ row }) => <ProductLink id={row.original.product_id} name={row.original.name} className="font-medium" /> },
    {
      header: "Move",
      cell: ({ row }) => (
        <span className="flex items-center gap-1.5 text-sm">
          {row.original.from_warehouse}
          <ArrowRight className="size-3.5 text-muted-foreground" />
          {row.original.to_warehouse}
        </span>
      ),
    },
    { header: "Qty", cell: ({ row }) => <span className="font-semibold tabular-nums">{row.original.quantity}</span> },
    { header: "Why", cell: ({ row }) => <span className="text-xs text-muted-foreground">{row.original.reason}</span> },
    {
      header: "", id: "actions",
      cell: ({ row }) => (
        <div className="flex justify-end">
          <Button size="sm" variant="outline" onClick={() => onTransfer(row.original)}>
            <Send className="size-3.5" /> Transfer
          </Button>
        </div>
      ),
    },
  ];

  return (
    <DataTable
      columns={columns}
      data={rows}
      loading={q.isLoading}
      error={q.isError ? "Couldn't load suggestions." : null}
      onRetry={() => q.refetch()}
      emptyMessage="Nothing to rebalance — no store has surplus another one needs."
    />
  );
}

/* ── History ──────────────────────────────────────────────────────────── */
function History({ warehouses }: { warehouses: Warehouse[] }) {
  const q = useQuery({
    queryKey: ["inventory", "transfers"],
    queryFn: () => api.get<Transfer[]>("/inventory/transfers"),
  });
  const [toComplete, setToComplete] = React.useState<Transfer | null>(null);
  const name = (id: string) =>
    warehouses.find((w) => w.id === id)?.name ?? `#${id}`;

  const complete = useApiMutation(
    (id: unknown) => api.post(`/inventory/transfers/${id}/complete`),
    {
      invalidate: [["inventory", "transfers"]],
      successMessage: "Transfer completed — stock moved",
      onDone: () => setToComplete(null),
    },
  );

  const columns: ColumnDef<Transfer, unknown>[] = [
    {
      header: "Move",
      cell: ({ row }) => (
        <span className="flex items-center gap-1.5 text-sm">
          {name(row.original.from_warehouse_id)}
          <ArrowRight className="size-3.5 text-muted-foreground" />
          {name(row.original.to_warehouse_id)}
        </span>
      ),
    },
    { header: "Qty", cell: ({ row }) => <span className="font-semibold tabular-nums">{row.original.quantity}</span> },
    { header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { header: "Note", cell: ({ row }) => <span className="text-xs text-muted-foreground">{row.original.note || "—"}</span> },
    {
      header: "", id: "actions",
      cell: ({ row }) => (
        <div className="flex justify-end">
          {/* Only a PENDING transfer still needs posting; completed ones already
              moved their two ledger rows. */}
          {row.original.status === "pending" && (
            <Button size="sm" variant="outline" disabled={complete.isPending}
                    onClick={() => setToComplete(row.original)}>
              Complete
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
        data={q.data ?? []}
        loading={q.isLoading}
        error={q.isError ? "Couldn't load transfers." : null}
        onRetry={() => q.refetch()}
        emptyMessage="No stock has been transferred yet."
      />
      {toComplete && (
        <ConfirmDialog
          open
          onOpenChange={(o) => !o && setToComplete(null)}
          title={`Move ${toComplete.quantity} units to ${name(toComplete.to_warehouse_id)}?`}
          description={
            `This posts the two stock-ledger rows now: ${toComplete.quantity} units leave ` +
            `${name(toComplete.from_warehouse_id)} and arrive at ${name(toComplete.to_warehouse_id)}. ` +
            `The ledger is append-only — undoing this needs a second transfer in the opposite direction.`
          }
          confirmLabel="Complete transfer"
          loading={complete.isPending}
          onConfirm={() => complete.mutate(toComplete.id)}
        />
      )}
    </>
  );
}

/* ── Create ───────────────────────────────────────────────────────────── */
function TransferDialog({
  warehouses, prefill, onClose,
}: { warehouses: Warehouse[]; prefill: Suggestion | null; onClose: () => void }) {
  const [productId, setProductId] = React.useState(prefill?.product_id ?? "");
  const [productName, setProductName] = React.useState(prefill?.name ?? "");
  const [from, setFrom] = React.useState(prefill?.from_warehouse_id ?? "");
  const [to, setTo] = React.useState(prefill?.to_warehouse_id ?? "");
  const [qty, setQty] = React.useState(String(prefill?.quantity ?? ""));
  const [note, setNote] = React.useState(prefill ? "Rebalance" : "");
  const [search, setSearch] = React.useState("");
  const [confirming, setConfirming] = React.useState(false);

  const hits = useQuery({
    queryKey: ["catalog", "products", search],
    queryFn: () => api.getPaged<ProductHit>("/admin/catalog/products", { q: search }),
    enabled: !prefill && search.trim().length >= 2,
  });

  const save = useApiMutation(
    () => api.post("/inventory/transfer", {
      product_id: productId,
      from_warehouse: from,
      to_warehouse: to,
      quantity: Number(qty),
      note: note.trim(),
    }),
    {
      invalidate: [["inventory", "transfers"], ["inventory", "transfer-suggestions"]],
      successMessage: "Stock transferred",
      onDone: onClose,
    },
  );

  const n = Number(qty);
  // The backend rejects same-source-and-destination; block it here too rather
  // than round-trip for it.
  const valid = productId && from && to && from !== to && Number.isFinite(n) && n > 0;

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader><DialogTitle>Transfer stock</DialogTitle></DialogHeader>
        <div className="space-y-3 py-1">
          {prefill ? (
            <div className="rounded-md border px-3 py-2 text-sm">
              <p className="font-medium">{productName}</p>
              <p className="text-xs text-muted-foreground">{prefill.reason}</p>
            </div>
          ) : (
            <div className="space-y-1.5">
              <Label>Product</Label>
              {productId ? (
                <div className="flex items-center justify-between rounded-md border px-3 py-2 text-sm">
                  <span className="font-medium">{productName}</span>
                  <Button variant="ghost" size="sm" onClick={() => { setProductId(""); setProductName(""); }}>
                    Change
                  </Button>
                </div>
              ) : (
                <>
                  <Input placeholder="Search the catalog…" value={search}
                         onChange={(e) => setSearch(e.target.value)} />
                  {hits.isFetching && <Loader2 className="size-4 animate-spin text-muted-foreground" />}
                  <div className="max-h-40 space-y-1 overflow-y-auto">
                    {(hits.data?.rows ?? []).map((p) => (
                      <button key={p.id} type="button"
                              className="w-full rounded-md border px-3 py-2 text-left text-sm hover:bg-muted"
                              onClick={() => { setProductId(p.id); setProductName(p.name); }}>
                        {p.name}
                      </button>
                    ))}
                  </div>
                </>
              )}
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <Label>From</Label>
              <Select value={from} onValueChange={setFrom}>
                <SelectTrigger><SelectValue placeholder="Source" /></SelectTrigger>
                <SelectContent>
                  {warehouses.map((w) => <SelectItem key={w.id} value={w.id}>{w.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>To</Label>
              <Select value={to} onValueChange={setTo}>
                <SelectTrigger><SelectValue placeholder="Destination" /></SelectTrigger>
                <SelectContent>
                  {warehouses.filter((w) => w.id !== from).map((w) => (
                    <SelectItem key={w.id} value={w.id}>{w.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
          </div>

          <div className="space-y-1.5">
            <Label>Quantity</Label>
            <Input inputMode="numeric" value={qty} onChange={(e) => setQty(e.target.value)} placeholder="0" />
          </div>
          <div className="space-y-1.5">
            <Label>Note</Label>
            <Input value={note} onChange={(e) => setNote(e.target.value)} placeholder="Why is this moving?" />
          </div>
          <p className="text-xs text-muted-foreground">
            Posts two ledger rows — out of {titleize(warehouses.find((w) => w.id === from)?.name ?? "source")},
            into {titleize(warehouses.find((w) => w.id === to)?.name ?? "destination")}. Stock is conserved.
          </p>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={save.isPending}>Cancel</Button>
          <Button disabled={!valid || save.isPending} onClick={() => setConfirming(true)}>
            {save.isPending ? <Loader2 className="size-4 animate-spin" /> : <Wand2 className="size-4" />}
            Transfer
          </Button>
        </DialogFooter>
      </DialogContent>
      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title={`Move ${n} units of ${productName || "this product"}?`}
        description={
          `${n} units leave ${warehouses.find((w) => w.id === from)?.name ?? "the source store"} and arrive at ` +
          `${warehouses.find((w) => w.id === to)?.name ?? "the destination store"} as soon as you confirm. ` +
          `Both stock-ledger rows post immediately and the ledger is append-only — reversing this needs a second ` +
          `transfer in the opposite direction.`
        }
        confirmLabel="Transfer stock"
        loading={save.isPending}
        onConfirm={() => save.mutate(undefined)}
      />
    </Dialog>
  );
}
