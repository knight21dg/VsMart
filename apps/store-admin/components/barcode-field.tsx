"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, Check, ScanLine } from "lucide-react";
import { api } from "@/lib/api/hooks";
import { Input } from "@/components/ui/input";

export interface BarcodeOwner {
  found: boolean;
  code: string;
  productId?: string;
  productName?: string;
  variantLabel?: string | null;
  carried?: boolean;
  ownedByAnotherStore?: boolean;
}

/**
 * Scan-or-type a barcode. A USB/bluetooth retail scanner acts as a keyboard, so
 * focusing this field and scanning just types the digits (+ Enter) — no driver
 * needed.
 *
 * The code is the product's UNIQUE key, so we look it up as you scan and warn the
 * moment it already belongs to something. `selfProductId` is the product being
 * edited: its own code must not report as a clash.
 */
export function BarcodeField({
  value,
  onChange,
  selfProductId,
  onOwnerChange,
  placeholder = "Scan or type the barcode",
  autoFocus = false,
}: {
  value: string;
  onChange: (v: string) => void;
  selfProductId?: string;
  onOwnerChange?: (owner: BarcodeOwner | null) => void;
  placeholder?: string;
  autoFocus?: boolean;
}) {
  // Debounce so a scanner burst fires one lookup, not one per character.
  const [debounced, setDebounced] = React.useState(value);
  React.useEffect(() => {
    const t = setTimeout(() => setDebounced(value.trim()), 300);
    return () => clearTimeout(t);
  }, [value]);

  const q = useQuery({
    queryKey: ["store", "barcode", debounced],
    queryFn: () => api.get<BarcodeOwner>(`/store/barcode?code=${encodeURIComponent(debounced)}`),
    enabled: debounced.length >= 4,
  });

  // A hit on the product we're editing is our own code, not a duplicate.
  const owner = q.data ?? null;
  const clash =
    owner?.found && owner.productId && owner.productId !== selfProductId
      ? owner
      : null;

  React.useEffect(() => {
    onOwnerChange?.(clash);
  }, [clash, onOwnerChange]);

  return (
    <div className="space-y-1.5">
      <div className="relative">
        <ScanLine className="pointer-events-none absolute left-2.5 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          className="pl-8 font-mono"
          value={value}
          autoFocus={autoFocus}
          placeholder={placeholder}
          onChange={(e) => onChange(e.target.value.trim())}
          // Scanners send Enter at the end of a scan — don't let it submit the form.
          onKeyDown={(e) => {
            if (e.key === "Enter") e.preventDefault();
          }}
        />
      </div>
      {clash ? (
        <p className="flex items-start gap-1.5 text-xs text-[var(--color-danger)]">
          <AlertTriangle className="mt-0.5 size-3.5 shrink-0" />
          <span>
            Already used by <strong>{clash.productName}</strong>
            {clash.variantLabel ? ` (${clash.variantLabel})` : ""}
            {clash.ownedByAnotherStore
              ? " — another store's private product."
              : clash.carried
                ? " — you already sell this item."
                : ""}
          </span>
        </p>
      ) : debounced.length >= 4 && owner && !owner.found ? (
        <p className="flex items-center gap-1.5 text-xs text-[var(--color-success)]">
          <Check className="size-3.5" /> Barcode is free.
        </p>
      ) : (
        <p className="text-xs text-muted-foreground">
          Leave blank and we generate a scannable in-store code automatically.
        </p>
      )}
    </div>
  );
}
