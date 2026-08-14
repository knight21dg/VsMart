"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { ArrowDown, ArrowUp, Plus, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { LoadingState, ErrorState } from "@/components/states";
import { inr } from "@/lib/utils";

interface HomeFeature {
  id: string;
  section: string;
  productId: number | string;
  productName: string;
  productImageUrl: string | null;
  productPrice: string | number;
  productIsActive: boolean;
  productOriginStoreName: string | null;
  sortOrder: number;
  isActive: boolean;
}

interface ProductHit {
  id: number | string;
  name: string;
  price: number;
  isActive: boolean;
  /** Null for a company-wide product; the owning store's name otherwise. */
  originStoreName: string | null;
}

interface HomeSectionMeta {
  key: string;
  label: string;
  fallbackSort: string;
  limit: number;
}

/** One rail's pins. A list keyed by a `section` *value* — see the API note: a
 *  dict keyed by section code gets camelCased on the wire and stops matching. */
interface HomeSectionPins {
  section: string;
  label: string;
  items: HomeFeature[];
}

/** How each rail behaves when nobody has curated it. Shown on every card so the
 *  operator knows what they are overriding rather than pinning blind. */
const FALLBACK_COPY: Record<string, string> = {
  discount: "biggest discount first",
  popular: "most reviewed first",
  rating: "best rated first",
  top_selling: "most units sold first",
};

/**
 * Curate the customer app's home rails.
 *
 * The rails were hardcoded `/products?sort=...` calls inside the Flutter app, so
 * nothing in the console could influence the front page — the gap the QA report
 * records as "Today Deals and Popular Products can't be managed from
 * Admin/Store". Pinning is additive: a rail with no pins keeps its algorithmic
 * order, which is why each card states that order explicitly.
 */
export function HomeScreenTab({ active }: { active: boolean }) {
  const sections = useQuery({
    queryKey: ["mkt", "home", "sections"],
    queryFn: () => api.get<HomeSectionMeta[]>("/home/sections"),
    enabled: active,
  });
  const pins = useQuery({
    queryKey: ["mkt", "home", "pins"],
    queryFn: () => api.get<HomeSectionPins[]>("/admin/catalog/home-sections"),
    enabled: active,
  });
  const pinsBySection = React.useMemo(
    () => new Map((pins.data ?? []).map((p) => [p.section, p.items])),
    [pins.data],
  );

  if (sections.isLoading || pins.isLoading) return <LoadingState />;
  if (sections.isError || pins.isError) {
    return (
      <ErrorState
        message="Couldn't load the home screen sections."
        onRetry={() => {
          sections.refetch();
          pins.refetch();
        }}
      />
    );
  }

  return (
    <div className="grid gap-4 xl:grid-cols-2">
      {(sections.data ?? []).map((s) => (
        <HomeRailCard key={s.key} meta={s} rows={pinsBySection.get(s.key) ?? []} />
      ))}
    </div>
  );
}

function HomeRailCard({ meta, rows }: { meta: HomeSectionMeta; rows: HomeFeature[] }) {
  const [adding, setAdding] = React.useState(false);
  const invalidate = [["mkt", "home", "pins"]];
  const fallback = FALLBACK_COPY[meta.fallbackSort] ?? meta.fallbackSort;

  const pin = useApiMutation(
    (productId: number | string) =>
      api.post("/admin/catalog/home-sections", { section: meta.key, productId }),
    { invalidate, successMessage: "Added to the rail.", onDone: () => setAdding(false) },
  );
  const unpin = useApiMutation(
    (id: string) => api.delWithMessage(`/admin/catalog/home-sections/${id}`),
    { invalidate, onDone: (res) => toast.success(res.message || "Removed from the rail.") },
  );
  // One call carries the whole new order. Applying it as N separate PATCHes
  // would leave the rail visibly scrambled if one of them failed partway.
  const reorder = useApiMutation(
    (ids: string[]) =>
      api.post("/admin/catalog/home-sections/reorder", { section: meta.key, ids }),
    { invalidate },
  );

  function move(index: number, delta: number) {
    const next = [...rows];
    const target = index + delta;
    if (target < 0 || target >= next.length) return;
    [next[index], next[target]] = [next[target], next[index]];
    reorder.mutate(next.map((r) => r.id));
  }

  const busy = pin.isPending || unpin.isPending || reorder.isPending;

  return (
    <Card>
      <CardHeader className="py-3">
        <div className="flex items-center justify-between gap-2">
          <CardTitle className="text-sm">{meta.label}</CardTitle>
          <Button size="sm" variant="outline" disabled={busy} onClick={() => setAdding(true)}>
            <Plus className="size-4" /> Feature a product
          </Button>
        </div>
      </CardHeader>
      <CardContent className="space-y-3">
        {rows.length === 0 ? (
          <p className="rounded-md border border-dashed px-3 py-6 text-center text-sm text-muted-foreground">
            Not curated — this rail shows <span className="font-medium">{fallback}</span>{" "}
            automatically. Feature a product to take control of it.
          </p>
        ) : (
          <ul className="divide-y">
            {rows.map((r, i) => (
              <li key={r.id} className="flex items-center gap-3 py-2">
                <span className="w-5 shrink-0 text-xs tabular-nums text-muted-foreground">
                  {i + 1}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{r.productName}</p>
                  <p className="text-xs text-muted-foreground">
                    {inr(r.productPrice)}
                    {r.productOriginStoreName && (
                      <span className="ml-2">
                        Shown only to {r.productOriginStoreName} customers
                      </span>
                    )}
                    {!r.productIsActive && (
                      <span className="ml-2 text-destructive">
                        Archived — hidden from customers
                      </span>
                    )}
                  </p>
                </div>
                <div className="flex shrink-0 items-center gap-0.5">
                  <Button
                    variant="ghost"
                    size="icon"
                    disabled={busy || i === 0}
                    title="Move up"
                    onClick={() => move(i, -1)}
                  >
                    <ArrowUp className="size-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    disabled={busy || i === rows.length - 1}
                    title="Move down"
                    onClick={() => move(i, 1)}
                  >
                    <ArrowDown className="size-4" />
                  </Button>
                  <Button
                    variant="ghost"
                    size="icon"
                    disabled={busy}
                    title="Remove from this rail"
                    onClick={() => unpin.mutate(r.id)}
                  >
                    <Trash2 className="size-4 text-destructive" />
                  </Button>
                </div>
              </li>
            ))}
          </ul>
        )}
        <p className="text-xs text-muted-foreground">
          {rows.length > 0
            ? `Showing these ${rows.length} first, then topping up to ${meta.limit} with ${fallback}.`
            : `Holds up to ${meta.limit} products.`}
        </p>
      </CardContent>

      <ProductPickerDialog
        open={adding}
        title={`Feature a product in ${meta.label}`}
        pending={pin.isPending}
        pinnedIds={rows.map((r) => String(r.productId))}
        onClose={() => setAdding(false)}
        onPick={(id) => pin.mutate(id)}
      />
    </Card>
  );
}

/**
 * Search-and-pick one product. Debounced so it doesn't fire per keystroke.
 *
 * The search deliberately does NOT filter to live products. The API refuses to
 * feature an archived one — rightly, it would put an unbuyable card on the home
 * screen — but hiding those matches meant a search for a product the operator
 * could see in Catalog came back "No live products match", with nothing to say
 * whether it was archived, misspelled or store-private. Archived matches are
 * listed and blocked *with the reason*, so the next step is obvious.
 */
function ProductPickerDialog({
  open,
  title,
  pending,
  pinnedIds,
  onClose,
  onPick,
}: {
  open: boolean;
  title: string;
  pending: boolean;
  pinnedIds: string[];
  onClose: () => void;
  onPick: (productId: number | string) => void;
}) {
  const [query, setQuery] = React.useState("");
  const [q, setQ] = React.useState("");
  React.useEffect(() => {
    const t = setTimeout(() => setQ(query.trim()), 250);
    return () => clearTimeout(t);
  }, [query]);
  React.useEffect(() => {
    if (!open) setQuery("");
  }, [open]);

  const products = useQuery({
    queryKey: ["mkt", "home", "product-search", q],
    // `scope=all` — store-added products are in the customer catalog and already
    // show up in these rails, so they have to be curatable. A pin is intersected
    // with the serving store's catalog on read, so pinning one can only ever
    // surface it to that store's customers.
    queryFn: () =>
      api.getPaged<ProductHit>("/admin/catalog/products", { q, scope: "all" }),
    enabled: open && q.length >= 2,
  });
  const hits = products.data?.rows ?? [];
  // Live products first — the ones that can actually be picked shouldn't be
  // pushed off the visible list by archived ones that can't.
  const rows = [...hits].sort((a, b) => Number(b.isActive) - Number(a.isActive)).slice(0, 8);
  const pinned = new Set(pinnedIds);

  function blockedReason(p: ProductHit): string | null {
    if (!p.isActive) return "Archived — restore it in Catalog first";
    if (pinned.has(String(p.id))) return "Already on this rail";
    return null;
  }

  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
        </DialogHeader>
        <Input
          autoFocus
          placeholder="Search products by name, brand or SKU…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <div className="max-h-72 overflow-y-auto">
          {q.length < 2 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">
              Type at least 2 characters to search.
            </p>
          ) : products.isLoading ? (
            <p className="py-6 text-center text-sm text-muted-foreground">Searching…</p>
          ) : products.isError ? (
            <p className="py-6 text-center text-sm text-destructive">
              Couldn&apos;t search the catalog. Try again.
            </p>
          ) : rows.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">
              No product matches “{q}”.
            </p>
          ) : (
            rows.map((p) => {
              const blocked = blockedReason(p);
              return (
                <button
                  key={p.id}
                  type="button"
                  disabled={pending || blocked !== null}
                  title={blocked ?? undefined}
                  className="flex w-full items-center justify-between gap-3 rounded px-2 py-2 text-left text-sm hover:bg-accent disabled:pointer-events-none disabled:opacity-60"
                  onClick={() => onPick(p.id)}
                >
                  <span className="min-w-0 truncate">
                    {p.name}
                    {p.originStoreName && (
                      <span className="ml-2 text-xs text-muted-foreground">
                        {p.originStoreName} only
                      </span>
                    )}
                  </span>
                  <span className="shrink-0 text-xs text-muted-foreground">
                    {blocked ? (
                      <span className="text-destructive">{blocked}</span>
                    ) : (
                      inr(p.price)
                    )}
                  </span>
                </button>
              );
            })
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
