"use client";

import { Plus, Trash2 } from "lucide-react";
import { BarcodeField } from "@/components/barcode-field";
import { ImageUpload } from "@/components/image-upload";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export interface VariantRow {
  id?: string;
  label: string;
  priceDelta: string;
  /** Per-pack MRP (blank = follow the product's MRP). */
  mrp?: string;
  /** This pack's own photo (blank = show the product photo). */
  imageUrl?: string;
  /** Scanned pack barcode — this variant's unique key. Blank = auto-generated. */
  barcode?: string;
  /** This pack's own stock. Each variant is counted separately. */
  openingStock?: string;
  reorderLevel?: string;
  /** Read-only, from the server: what's on the shelf now (edit mode). */
  onHand?: number;
}

/**
 * Edit a product's variants. Each variant is a separately-stocked, separately-priced
 * unit — its own price delta, MRP, photo, barcode AND its own stock. A 1kg and a
 * 500g are not one pool split by size; the shop counts each pack apart, so stock is
 * entered per row here, never once for the product.
 */
export function VariantsEditor({
  rows,
  onChange,
  selfProductId,
  editing,
}: {
  rows: VariantRow[];
  onChange: (r: VariantRow[]) => void;
  selfProductId?: string;
  /** In edit mode the current on-hand is shown and the field is a "set to" count. */
  editing?: boolean;
}) {
  const update = (i: number, patch: Partial<VariantRow>) =>
    onChange(rows.map((r, j) => (j === i ? { ...r, ...patch } : r)));
  const add = () =>
    onChange([...rows, { label: "", priceDelta: "", mrp: "", imageUrl: "", barcode: "", openingStock: "", reorderLevel: "" }]);

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <Label>Variants (optional)</Label>
        <Button type="button" variant="outline" size="sm" onClick={add}>
          <Plus className="size-3.5" /> Add variant
        </Button>
      </div>
      {rows.length === 0 && (
        <p className="text-xs text-muted-foreground">
          e.g. Small / Large / 1 kg — each is priced and <strong>stocked separately</strong>, with its own barcode.
        </p>
      )}
      {rows.map((r, i) => (
        <div key={i} className="space-y-2 rounded-md border p-2.5">
          <div className="flex items-start gap-2">
            <div className="shrink-0">
              <ImageUpload value={r.imageUrl ?? null} onChange={(url) => update(i, { imageUrl: url ?? "" })} />
            </div>
            <div className="flex-1 space-y-1.5">
              <div className="flex items-center gap-2">
                <Input placeholder="Label (e.g. 1 kg)" value={r.label} onChange={(e) => update(i, { label: e.target.value })} />
                <Button type="button" variant="ghost" size="icon" className="size-8 shrink-0 text-muted-foreground" onClick={() => onChange(rows.filter((_, j) => j !== i))}>
                  <Trash2 className="size-3.5" />
                </Button>
              </div>
              <div className="flex items-center gap-2">
                <div className="relative flex-1">
                  <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">+₹</span>
                  <Input className="pl-7" inputMode="decimal" placeholder="0" value={r.priceDelta} onChange={(e) => update(i, { priceDelta: e.target.value })} title="Amount this pack adds to the base price" />
                </div>
                <div className="relative flex-1">
                  <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-sm text-muted-foreground">MRP</span>
                  <Input className="pl-10" inputMode="decimal" placeholder="—" value={r.mrp ?? ""} onChange={(e) => update(i, { mrp: e.target.value })} title="This pack's MRP (blank follows the product)" />
                </div>
              </div>
            </div>
          </div>

          {/* Per-pack stock — the point of the whole change. */}
          <div className="grid grid-cols-2 gap-2">
            <div>
              <Label className="text-xs text-muted-foreground">
                {editing ? "Set stock" : "Opening stock"}
                {editing && typeof r.onHand === "number" && (
                  <span className="ml-1 font-normal">(now {r.onHand})</span>
                )}
              </Label>
              <Input inputMode="numeric" placeholder="0" value={r.openingStock ?? ""} onChange={(e) => update(i, { openingStock: e.target.value })} />
            </div>
            <div>
              <Label className="text-xs text-muted-foreground">Reorder at</Label>
              <Input inputMode="numeric" placeholder="0" value={r.reorderLevel ?? ""} onChange={(e) => update(i, { reorderLevel: e.target.value })} />
            </div>
          </div>

          <BarcodeField
            value={r.barcode ?? ""}
            onChange={(v) => update(i, { barcode: v })}
            selfProductId={selfProductId}
            placeholder="Scan this variant's barcode"
          />
        </div>
      ))}
    </div>
  );
}
