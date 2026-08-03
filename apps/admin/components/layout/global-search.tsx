"use client";

import * as React from "react";
import Link from "next/link";
import { Search, Package, ShoppingBag, Store, User } from "lucide-react";
import { useQuery } from "@tanstack/react-query";
import { api } from "@/lib/api/client";

type ResultType = "order" | "customer" | "product" | "store";

interface SearchResult {
  type: ResultType;
  id: string;
  label: string;
  sublabel: string;
  /** Admin route for this entity — resolved server-side. */
  href: string;
}

/** Render order + section heading + icon per entity type. */
const GROUPS: { type: ResultType; heading: string; Icon: typeof Search }[] = [
  { type: "order", heading: "Orders", Icon: ShoppingBag },
  { type: "customer", heading: "Customers", Icon: User },
  { type: "product", heading: "Products", Icon: Package },
  { type: "store", heading: "Stores", Icon: Store },
];

export function GlobalSearch() {
  const [q, setQ] = React.useState("");
  const [debounced, setDebounced] = React.useState("");
  const [open, setOpen] = React.useState(false);
  const ref = React.useRef<HTMLDivElement>(null);

  React.useEffect(() => {
    const t = setTimeout(() => setDebounced(q.trim()), 250);
    return () => clearTimeout(t);
  }, [q]);

  React.useEffect(() => {
    function onClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  const { data, isFetching } = useQuery({
    queryKey: ["global-search", debounced],
    queryFn: () => api.get<{ results: SearchResult[] }>("/search/global", { q: debounced }),
    enabled: debounced.length >= 2,
  });

  const results = data?.results ?? [];
  const grouped = GROUPS.map((g) => ({
    ...g,
    rows: results.filter((r) => r.type === g.type),
  })).filter((g) => g.rows.length > 0);

  // Navigating away should leave the dropdown closed and the box empty, so the
  // stale query isn't sitting there when the operator lands on the record.
  function dismiss() {
    setOpen(false);
    setQ("");
    setDebounced("");
  }

  return (
    <div ref={ref} className="relative w-full max-w-md">
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
        <input
          value={q}
          onChange={(e) => {
            setQ(e.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          onKeyDown={(e) => {
            if (e.key === "Escape") setOpen(false);
          }}
          placeholder="Search orders, customers, products, stores…"
          className="h-9 w-full rounded-md border border-input bg-background pl-9 pr-3 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-ring"
        />
      </div>
      {open && debounced.length >= 2 && (
        <div className="absolute z-50 mt-1.5 w-full overflow-hidden rounded-lg border bg-popover shadow-lg">
          {isFetching ? (
            <p className="px-3 py-3 text-sm text-muted-foreground">Searching…</p>
          ) : grouped.length === 0 ? (
            <p className="px-3 py-3 text-sm text-muted-foreground">
              No orders, customers, products or stores match “{debounced}”.
            </p>
          ) : (
            <ul className="max-h-96 overflow-y-auto py-1 scrollbar-thin">
              {grouped.map(({ type, heading, Icon, rows }) => (
                <li key={type}>
                  <p className="px-3 pb-1 pt-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                    {heading}
                  </p>
                  <ul>
                    {rows.map((r) => (
                      <li key={`${r.type}:${r.id}`}>
                        <Link
                          href={r.href}
                          onClick={dismiss}
                          className="flex items-center gap-3 px-3 py-2 text-sm hover:bg-accent"
                        >
                          <Icon className="size-4 shrink-0 text-muted-foreground" />
                          <span className="min-w-0 flex-1">
                            <span className="block truncate">{r.label}</span>
                            {r.sublabel && (
                              <span className="block truncate text-xs text-muted-foreground">
                                {r.sublabel}
                              </span>
                            )}
                          </span>
                        </Link>
                      </li>
                    ))}
                  </ul>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}
