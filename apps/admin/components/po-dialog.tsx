"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Loader2 } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { inr } from "@/lib/utils";

interface Supplier { id: string; name: string }

interface ProductHit { id: string; name: string; brand: string; price: number }
interface Warehouse { id: string; name: string }
export interface POLine { productId: string; name: string; quantity: string; unitCost: string }

/**
 * Raise a purchase order.
 *
 * Until now the console could only *read* purchase orders, so the only way to
 * bring stock in was a free-text inventory adjustment carrying no supplier and
 * no cost — which poisons weighted-average cost and therefore COGS and GMROI on
 * the Finance page. The backend has always accepted this payload.
 *
 * Note PO lines are product-level: `PurchaseOrderItem` has no `variant` field,
 * unlike GRN lines. The pack is chosen at goods-receipt time, not at ordering.
 */
export function PODialog({
  prefill, prefillWarehouse, onClose,
}: {
  prefill?: POLine[] | null;
  /** Warehouse to deliver to — set when raising a PO from a reorder row, which
   *  already knows which store is short. */
  prefillWarehouse?: string | null;
  onClose: () => void;
}) {
  const [supplierId, setSupplierId] = React.useState("");
  const [warehouse, setWarehouse] = React.useState(prefillWarehouse ?? "");
  const [expectedAt, setExpectedAt] = React.useState("");
  const [lines, setLines] = React.useState<POLine[]>(prefill ?? []);
  const [search, setSearch] = React.useState("");

  const suppliers = useQuery({
    queryKey: ["inventory", "suppliers", "all"],
    queryFn: () => api.getPaged<Supplier>("/inventory/suppliers"),
  });
  const warehouses = useQuery({
    queryKey: ["inventory", "warehouses"],
    queryFn: () => api.get<Warehouse[]>("/inventory/warehouses"),
  });
  const hits = useQuery({
    queryKey: ["catalog", "products", search],
    queryFn: () => api.getPaged<ProductHit>("/admin/catalog/products", { q: search }),
    enabled: search.trim().length >= 2,
  });

  // Default to the only warehouse when there's just one — most installs have a
  // single one and making the operator pick it adds nothing.
  React.useEffect(() => {
    const all = warehouses.data ?? [];
    if (all.length === 1 && !warehouse) setWarehouse(all[0].id);
  }, [warehouses.data, warehouse]);

  function addLine(p: ProductHit) {
    setSearch("");
    setLines((prev) =>
      prev.some((l) => l.productId === p.id)
        ? prev
        : [...prev, { productId: p.id, name: p.name, quantity: "1", unitCost: "" }]);
  }
  function setLine(i: number, patch: Partial<POLine>) {
    setLines((prev) => prev.map((l, x) => (x === i ? { ...l, ...patch } : l)));
  }

  const parsed = lines.map((l) => ({
    ...l, q: Number(l.quantity), c: Number(l.unitCost),
  }));
  const total = parsed.reduce(
    (sum, l) => sum + (Number.isFinite(l.q) && Number.isFinite(l.c) ? l.q * l.c : 0), 0);
  const linesValid =
    parsed.length > 0 &&
    parsed.every((l) => Number.isInteger(l.q) && l.q >= 1 && Number.isFinite(l.c) && l.c >= 0
      && l.unitCost.trim() !== "");
  const valid = !!warehouse && linesValid;

  const save = useApiMutation<void>(
    () => api.post("/inventory/purchase-orders", {
      supplierId: supplierId || null,
      warehouse,
      expectedAt: expectedAt || null,
      items: parsed.map((l) => ({
        productId: l.productId, quantity: l.q, unitCost: l.unitCost,
      })),
    }),
    {
      invalidate: [["inventory", "po"]],
      successMessage: "Purchase order raised",
      onDone: onClose,
    },
  );

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
        <DialogHeader><DialogTitle>New purchase order</DialogTitle></DialogHeader>

        <div className="space-y-4 py-1">
          <div className="grid gap-3 sm:grid-cols-3">
            <div className="space-y-1.5">
              <Label>Supplier</Label>
              <Select value={supplierId} onValueChange={setSupplierId}>
                <SelectTrigger><SelectValue placeholder="Optional" /></SelectTrigger>
                <SelectContent>
                  {(suppliers.data?.rows ?? []).map((s) => (
                    <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Deliver to</Label>
              <Select value={warehouse} onValueChange={setWarehouse}>
                <SelectTrigger><SelectValue placeholder="Select store" /></SelectTrigger>
                <SelectContent>
                  {(warehouses.data ?? []).map((w) => (
                    <SelectItem key={w.id} value={w.id}>{w.name}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Expected</Label>
              <Input type="date" value={expectedAt} onChange={(e) => setExpectedAt(e.target.value)} />
            </div>
          </div>

          <div className="space-y-1.5">
            <Label>Add products</Label>
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search the catalog by name…"
            />
            {search.trim().length >= 2 && (
              <div className="max-h-40 overflow-y-auto rounded-md border">
                {hits.isLoading && <p className="p-3 text-xs text-muted-foreground">Searching…</p>}
                {!hits.isLoading && (hits.data?.rows ?? []).length === 0 && (
                  <p className="p-3 text-xs text-muted-foreground">No products match.</p>
                )}
                {(hits.data?.rows ?? []).map((p) => (
                  <button
                    key={p.id}
                    type="button"
                    onClick={() => addLine(p)}
                    className="flex w-full items-center justify-between px-3 py-2 text-left text-sm hover:bg-accent"
                  >
                    <span>{p.name}</span>
                    <span className="text-xs text-muted-foreground">{p.brand}</span>
                  </button>
                ))}
              </div>
            )}
          </div>

          {lines.length > 0 && (
            <div className="space-y-2 rounded-md border p-3">
              {lines.map((l, i) => (
                <div key={l.productId} className="grid grid-cols-[1fr_5rem_6rem_2rem] items-center gap-2">
                  <span className="truncate text-sm font-medium">{l.name}</span>
                  <Input
                    inputMode="numeric" placeholder="Qty" value={l.quantity}
                    onChange={(e) => setLine(i, { quantity: e.target.value })}
                  />
                  <Input
                    inputMode="decimal" placeholder="Unit cost" value={l.unitCost}
                    onChange={(e) => setLine(i, { unitCost: e.target.value })}
                  />
                  <Button
                    variant="ghost" size="sm"
                    onClick={() => setLines((prev) => prev.filter((_, x) => x !== i))}
                  >
                    ×
                  </Button>
                </div>
              ))}
              <div className="flex justify-between border-t pt-2 text-sm font-semibold">
                <span>Total</span><span>{inr(total)}</span>
              </div>
              {!linesValid && (
                <p className="text-xs text-muted-foreground">
                  Every line needs a whole quantity of 1 or more and a unit cost —
                  cost drives weighted-average valuation, so it can&apos;t be left blank.
                </p>
              )}
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={save.isPending}>Cancel</Button>
          <Button onClick={() => save.mutate()} disabled={!valid || save.isPending}>
            {save.isPending && <Loader2 className="size-4 animate-spin" />} Raise PO
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

