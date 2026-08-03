"use client";

import * as React from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { ChevronLeft, Search, Share2, UserPlus } from "lucide-react";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { StatCard } from "@/components/stat-card";
import { type PageMeta } from "@/lib/types";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";

interface Referrer {
  userId: string;
  name: string;
  phone: string;
  invited: number;
  completed: number;
  pending: number;
  rewardsPaid: number;
}

interface Referral {
  id: string;
  code: string;
  status: string;
  reward: number;
  referrerId: string;
  referrerName: string;
  referrerPhone: string;
  refereeId: string | null;
  refereeName: string;
  refereePhone: string;
  createdAt: string;
}

interface ReferrerDetail {
  userId: string;
  name: string;
  phone: string;
  invited: number;
  completed: number;
  invitees: Referral[];
}

interface Summary {
  total: number;
  completed: number;
  pending: number;
  expired: number;
  rewardsPaid: number;
  conversionRate: number;
  referrers: number;
}

const STATUSES = [
  { value: "all", label: "All statuses" },
  { value: "completed", label: "Completed" },
  { value: "pending", label: "Pending" },
  { value: "expired", label: "Expired" },
];

function money(n: number | string | null | undefined) {
  const v = Number(n ?? 0);
  return `₹${v.toLocaleString("en-IN", { maximumFractionDigits: 2 })}`;
}

function fmtDate(s: string) {
  return s ? new Date(s).toLocaleDateString("en-IN", {
    day: "2-digit", month: "short", year: "numeric",
  }) : "—";
}

/** The people one referrer actually brought in. */
function ReferrerDrilldown({ userId, onBack }: { userId: string; onBack: () => void }) {
  const query = useQuery({
    queryKey: ["admin", "referrer", userId],
    queryFn: () => api.get<ReferrerDetail>(`/admin/referrers/${userId}`),
  });
  const data = query.data;

  const columns: ColumnDef<Referral, unknown>[] = [
    {
      id: "referee", header: "Invited",
      cell: ({ row }) => (
        <div className="flex flex-col">
          {/* referee is SET_NULL: a closed account leaves the row, not a hole. */}
          <span className="font-medium">{row.original.refereeName || "Account closed"}</span>
          <span className="text-xs text-muted-foreground">
            {row.original.refereePhone || "—"}
          </span>
        </div>
      ),
    },
    { accessorKey: "code", header: "Code" },
    {
      accessorKey: "status", header: "Status",
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      id: "reward", header: "Reward",
      cell: ({ row }) => (
        <span className="tabular-nums">
          {row.original.status === "completed" ? money(row.original.reward) : "—"}
        </span>
      ),
    },
    {
      accessorKey: "createdAt", header: "Invited on",
      cell: ({ row }) => (
        <span className="text-muted-foreground">{fmtDate(row.original.createdAt)}</span>
      ),
    },
  ];

  return (
    <div className="space-y-4">
      <Button variant="ghost" size="sm" onClick={onBack} className="-ml-2">
        <ChevronLeft className="size-4" /> All referrers
      </Button>
      <PageHeader
        title={data?.name || "Referrer"}
        description={
          data
            ? `${data.phone} · invited ${data.invited}, ${data.completed} converted`
            : undefined
        }
      />
      <DataTable
        columns={columns}
        data={data?.invitees ?? []}
        loading={query.isLoading}
        emptyMessage="This customer hasn't invited anyone yet."
      />
    </div>
  );
}

export default function ReferralsPage() {
  const [tab, setTab] = React.useState<"referrers" | "referrals">("referrers");
  const [status, setStatus] = React.useState("all");
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [page, setPage] = React.useState(1);
  const [drilldown, setDrilldown] = React.useState<string | null>(null);

  React.useEffect(() => {
    const t = setTimeout(() => { setQ(search.trim()); setPage(1); }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const summary = useQuery({
    queryKey: ["admin", "referrals", "summary"],
    queryFn: () => api.get<Summary>("/admin/referrals/summary"),
  });

  const referrers = useQuery({
    queryKey: ["admin", "referrers", q, page],
    queryFn: () => api.getPaged<Referrer>("/admin/referrers", {
      search: q || undefined, page,
    }),
    placeholderData: keepPreviousData,
    enabled: tab === "referrers" && !drilldown,
  });

  const referrals = useQuery({
    queryKey: ["admin", "referrals", status, q, page],
    queryFn: () => api.getPaged<Referral>("/admin/referrals", {
      status: status === "all" ? undefined : status,
      search: q || undefined,
      page,
    }),
    placeholderData: keepPreviousData,
    enabled: tab === "referrals" && !drilldown,
  });

  if (drilldown) {
    return <ReferrerDrilldown userId={drilldown} onBack={() => setDrilldown(null)} />;
  }

  const referrerColumns: ColumnDef<Referrer, unknown>[] = [
    {
      id: "user", header: "Referrer",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span className="font-medium">{row.original.name || "—"}</span>
          <span className="text-xs text-muted-foreground">{row.original.phone}</span>
        </div>
      ),
    },
    {
      accessorKey: "invited", header: "Invited",
      cell: ({ row }) => <span className="tabular-nums">{row.original.invited}</span>,
    },
    {
      accessorKey: "completed", header: "Converted",
      cell: ({ row }) => (
        <span className="tabular-nums font-medium text-[var(--color-success)]">
          {row.original.completed}
        </span>
      ),
    },
    {
      accessorKey: "pending", header: "Pending",
      cell: ({ row }) => (
        <span className="tabular-nums text-muted-foreground">{row.original.pending}</span>
      ),
    },
    {
      id: "rewardsPaid", header: "Rewards paid",
      cell: ({ row }) => (
        <span className="tabular-nums">{money(row.original.rewardsPaid)}</span>
      ),
    },
    {
      id: "actions", header: "",
      cell: ({ row }) => (
        <Button variant="outline" size="sm" onClick={() => setDrilldown(row.original.userId)}>
          View invitees
        </Button>
      ),
    },
  ];

  const referralColumns: ColumnDef<Referral, unknown>[] = [
    {
      id: "referrer", header: "Referrer",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span className="font-medium">{row.original.referrerName || "—"}</span>
          <span className="text-xs text-muted-foreground">{row.original.referrerPhone}</span>
        </div>
      ),
    },
    {
      id: "referee", header: "Invited",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span>{row.original.refereeName || "Not yet joined"}</span>
          <span className="text-xs text-muted-foreground">
            {row.original.refereePhone || "—"}
          </span>
        </div>
      ),
    },
    { accessorKey: "code", header: "Code" },
    {
      accessorKey: "status", header: "Status",
      cell: ({ row }) => <StatusBadge status={row.original.status} />,
    },
    {
      accessorKey: "createdAt", header: "Created",
      cell: ({ row }) => (
        <span className="text-muted-foreground">{fmtDate(row.original.createdAt)}</span>
      ),
    },
  ];

  const s = summary.data;
  const meta = tab === "referrers" ? referrers.data?.meta : referrals.data?.meta;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Referrals"
        description="Who invited whom, how many converted, and what the scheme paid out."
      />

      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard label="Referrers" value={s?.referrers ?? "—"}
          icon={<Share2 className="size-4 text-muted-foreground" />} />
        <StatCard label="Invites sent" value={s?.total ?? "—"}
          icon={<UserPlus className="size-4 text-muted-foreground" />} />
        <StatCard
          label="Converted"
          value={s ? `${s.completed} (${s.conversionRate}%)` : "—"}
        />
        {/* Both sides get a voucher, so this is already doubled server-side. */}
        <StatCard label="Rewards paid" value={s ? money(s.rewardsPaid) : "—"} />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <div className="inline-flex rounded-md border p-0.5">
          {(["referrers", "referrals"] as const).map((t) => (
            <Button
              key={t}
              size="sm"
              variant={tab === t ? "secondary" : "ghost"}
              onClick={() => { setTab(t); setPage(1); }}
            >
              {t === "referrers" ? "By referrer" : "All referrals"}
            </Button>
          ))}
        </div>

        {tab === "referrals" && (
          <Select value={status} onValueChange={(v) => { setStatus(v); setPage(1); }}>
            <SelectTrigger className="w-[180px]"><SelectValue /></SelectTrigger>
            <SelectContent>
              {STATUSES.map((o) => (
                <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        )}

        <div className="relative ml-auto w-full sm:w-64">
          <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Name, phone or code"
            className="pl-8"
          />
        </div>
      </div>

      {tab === "referrers" ? (
        <DataTable
          columns={referrerColumns}
          data={referrers.data?.rows ?? []}
          loading={referrers.isLoading}
          emptyMessage="Nobody has invited anyone yet."
          pageMeta={meta as PageMeta | undefined}
          page={page}
          onPageChange={setPage}
        />
      ) : (
        <DataTable
          columns={referralColumns}
          data={referrals.data?.rows ?? []}
          loading={referrals.isLoading}
          emptyMessage="No referrals match this filter."
          pageMeta={meta as PageMeta | undefined}
          page={page}
          onPageChange={setPage}
        />
      )}
    </div>
  );
}
