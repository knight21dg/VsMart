"use client";

import * as React from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Award, Coins, Search, TrendingDown, TrendingUp } from "lucide-react";
import { api } from "@/lib/api/client";
import { type PageMeta } from "@/lib/types";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { StatCard } from "@/components/stat-card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";

interface Entry {
  id: string;
  userId: string;
  userName: string;
  userPhone: string;
  type: string;
  points: number;
  balanceAfter: number;
  note: string;
  refType: string;
  refId: string;
  createdAt: string;
}

interface Member {
  userId: string;
  name: string;
  phone: string;
  lifetimePoints: number;
  earningEvents: number;
  tier: string;
}

interface Summary {
  pointsEarned: number;
  pointsRedeemed: number;
  pointsExpired: number;
  pointsAdjusted: number;
  pointsOutstanding: number;
  members: number;
}

const TYPES = [
  { value: "all", label: "All movements" },
  { value: "earn", label: "Earned" },
  { value: "redeem", label: "Redeemed" },
  { value: "adjust", label: "Adjusted" },
  { value: "expire", label: "Expired" },
];

const TIER_TONE: Record<string, string> = {
  Gold: "bg-[var(--color-warning)]/15 text-[var(--color-warning)]",
  Silver: "bg-muted text-muted-foreground",
  Bronze: "bg-[var(--color-brand)]/10 text-[var(--color-brand)]",
};

function num(n: number | null | undefined) {
  return Number(n ?? 0).toLocaleString("en-IN");
}

function fmtDate(s: string) {
  return s ? new Date(s).toLocaleString("en-IN", {
    day: "2-digit", month: "short", year: "numeric",
    hour: "2-digit", minute: "2-digit",
  }) : "—";
}

export default function LoyaltyPage() {
  const [tab, setTab] = React.useState<"ledger" | "members">("ledger");
  const [type, setType] = React.useState("all");
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [page, setPage] = React.useState(1);

  React.useEffect(() => {
    const t = setTimeout(() => { setQ(search.trim()); setPage(1); }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const summary = useQuery({
    queryKey: ["admin", "loyalty", "summary"],
    queryFn: () => api.get<Summary>("/admin/loyalty/summary"),
  });

  const ledger = useQuery({
    queryKey: ["admin", "loyalty", "ledger", type, q, page],
    queryFn: () => api.getPaged<Entry>("/admin/loyalty/ledger", {
      type: type === "all" ? undefined : type,
      search: q || undefined,
      page,
    }),
    placeholderData: keepPreviousData,
    enabled: tab === "ledger",
  });

  const members = useQuery({
    queryKey: ["admin", "loyalty", "members"],
    queryFn: () => api.get<Member[]>("/admin/loyalty/members", { limit: 50 }),
    enabled: tab === "members",
  });

  const ledgerColumns: ColumnDef<Entry, unknown>[] = [
    {
      id: "user", header: "Customer",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span className="font-medium">{row.original.userName || "—"}</span>
          <span className="text-xs text-muted-foreground">{row.original.userPhone}</span>
        </div>
      ),
    },
    {
      accessorKey: "type", header: "Movement",
      cell: ({ row }) => (
        <Badge variant="outline" className="capitalize">{row.original.type}</Badge>
      ),
    },
    {
      accessorKey: "points", header: "Points",
      cell: ({ row }) => {
        // Stored signed: earn +, redeem/expire −. Show the sign, it's the whole point.
        const p = row.original.points;
        return (
          <span
            className={`tabular-nums font-medium ${
              p >= 0 ? "text-[var(--color-success)]" : "text-destructive"
            }`}
          >
            {p >= 0 ? "+" : ""}{num(p)}
          </span>
        );
      },
    },
    {
      accessorKey: "balanceAfter", header: "Balance after",
      cell: ({ row }) => (
        <span className="tabular-nums text-muted-foreground">
          {num(row.original.balanceAfter)}
        </span>
      ),
    },
    {
      accessorKey: "note", header: "Note",
      cell: ({ row }) => (
        <span className="text-xs text-muted-foreground">{row.original.note || "—"}</span>
      ),
    },
    {
      accessorKey: "createdAt", header: "When",
      cell: ({ row }) => (
        <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt)}</span>
      ),
    },
  ];

  const memberColumns: ColumnDef<Member, unknown>[] = [
    {
      id: "user", header: "Customer",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span className="font-medium">{row.original.name || "—"}</span>
          <span className="text-xs text-muted-foreground">{row.original.phone}</span>
        </div>
      ),
    },
    {
      accessorKey: "tier", header: "Tier",
      cell: ({ row }) => (
        <span
          className={`rounded-full px-2 py-0.5 text-xs font-medium ${
            TIER_TONE[row.original.tier] ?? "bg-muted text-muted-foreground"
          }`}
        >
          {row.original.tier}
        </span>
      ),
    },
    {
      accessorKey: "lifetimePoints", header: "Lifetime earned",
      cell: ({ row }) => (
        <span className="tabular-nums font-medium">{num(row.original.lifetimePoints)}</span>
      ),
    },
    {
      accessorKey: "earningEvents", header: "Earning events",
      cell: ({ row }) => (
        <span className="tabular-nums text-muted-foreground">
          {num(row.original.earningEvents)}
        </span>
      ),
    },
  ];

  const s = summary.data;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Loyalty"
        description="Points earned, redeemed and still outstanding. The ledger is append-only — corrections are adjustment entries, never edits."
      />

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Earned" hint="Lifetime points granted"
          value={s ? num(s.pointsEarned) : "—"}
          icon={<TrendingUp className="size-4 text-[var(--color-success)]" />}
          loading={summary.isLoading}
        />
        <StatCard
          label="Redeemed" hint="Points burned for vouchers"
          value={s ? num(s.pointsRedeemed) : "—"}
          icon={<TrendingDown className="size-4 text-destructive" />}
          loading={summary.isLoading}
        />
        <StatCard
          label="Outstanding" hint="Still redeemable — a real liability"
          value={s ? num(s.pointsOutstanding) : "—"}
          icon={<Coins className="size-4 text-[var(--color-warning)]" />}
          loading={summary.isLoading}
        />
        <StatCard
          label="Members" hint="Customers with any points history"
          value={s ? num(s.members) : "—"}
          icon={<Award className="size-4 text-muted-foreground" />}
          loading={summary.isLoading}
        />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="inline-flex rounded-md border p-0.5">
          {(["ledger", "members"] as const).map((t) => (
            <Button
              key={t}
              size="sm"
              variant={tab === t ? "secondary" : "ghost"}
              onClick={() => { setTab(t); setPage(1); }}
            >
              {t === "ledger" ? "Points ledger" : "Top members"}
            </Button>
          ))}
        </div>

        {tab === "ledger" && (
          <>
            <Select value={type} onValueChange={(v) => { setType(v); setPage(1); }}>
              <SelectTrigger className="w-[180px]"><SelectValue /></SelectTrigger>
              <SelectContent>
                {TYPES.map((o) => (
                  <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="relative ml-auto w-full sm:w-64">
              <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Name, phone, note or order"
                className="pl-9"
              />
            </div>
          </>
        )}
      </div>

      {tab === "ledger" ? (
        <DataTable
          columns={ledgerColumns}
          data={ledger.data?.rows ?? []}
          loading={ledger.isLoading}
          emptyMessage="No points movements yet."
          pageMeta={ledger.data?.meta as PageMeta | undefined}
          page={page}
          onPageChange={setPage}
        />
      ) : (
        <DataTable
          columns={memberColumns}
          data={members.data ?? []}
          loading={members.isLoading}
          emptyMessage="Nobody has earned points yet."
        />
      )}
    </div>
  );
}
