"use client";

import * as React from "react";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Gift, Search, Ticket, Wallet } from "lucide-react";
import { api } from "@/lib/api/client";
import { type PageMeta } from "@/lib/types";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { StatCard } from "@/components/stat-card";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";

interface Redemption {
  id: string;
  userId: string;
  userName: string;
  userPhone: string;
  couponCode: string;
  discountType: string;
  isPersonal: boolean;
  orderCode: string;
  amount: number;
  createdAt: string;
}

interface Outstanding {
  issued: number;
  spent: number;
  outstanding: number;
  outstandingValue: number;
}

const KINDS = [
  { value: "all", label: "All coupons" },
  { value: "personal", label: "Personal vouchers" },
  { value: "public", label: "Public campaign codes" },
];

function money(n: number | string | null | undefined) {
  return `₹${Number(n ?? 0).toLocaleString("en-IN", { maximumFractionDigits: 2 })}`;
}

function fmtDate(s: string) {
  return s ? new Date(s).toLocaleString("en-IN", {
    day: "2-digit", month: "short", year: "numeric",
    hour: "2-digit", minute: "2-digit",
  }) : "—";
}

export default function RedemptionsPage() {
  const [kind, setKind] = React.useState("all");
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [page, setPage] = React.useState(1);

  React.useEffect(() => {
    const t = setTimeout(() => { setQ(search.trim()); setPage(1); }, 300);
    return () => clearTimeout(t);
  }, [search]);

  const outstanding = useQuery({
    queryKey: ["admin", "redemptions", "outstanding"],
    queryFn: () => api.get<Outstanding>("/admin/redemptions/outstanding"),
  });

  const query = useQuery({
    queryKey: ["admin", "redemptions", kind, q, page],
    queryFn: () => api.getPaged<Redemption>("/admin/redemptions", {
      kind: kind === "all" ? undefined : kind,
      search: q || undefined,
      page,
    }),
    placeholderData: keepPreviousData,
  });

  const columns: ColumnDef<Redemption, unknown>[] = [
    {
      accessorKey: "couponCode", header: "Coupon",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span className="font-medium">{row.original.couponCode}</span>
          {/* Personal = minted for one customer by loyalty or a referral, and
              worthless to anyone else. Public = a marketing campaign code. */}
          <Badge variant="outline" className="mt-0.5 w-fit text-[10px]">
            {row.original.isPersonal ? "Personal voucher" : "Public code"}
          </Badge>
        </div>
      ),
    },
    {
      id: "user", header: "Redeemed by",
      cell: ({ row }) => (
        <div className="flex flex-col">
          <span>{row.original.userName || "—"}</span>
          <span className="text-xs text-muted-foreground">{row.original.userPhone}</span>
        </div>
      ),
    },
    {
      accessorKey: "orderCode", header: "Order",
      cell: ({ row }) => (
        <span className="font-mono text-xs">{row.original.orderCode || "—"}</span>
      ),
    },
    {
      accessorKey: "amount", header: "Discount given",
      cell: ({ row }) => (
        <span className="tabular-nums font-medium">{money(row.original.amount)}</span>
      ),
    },
    {
      accessorKey: "createdAt", header: "When",
      cell: ({ row }) => (
        <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt)}</span>
      ),
    },
  ];

  const o = outstanding.data;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Redemptions"
        description="Coupons actually spent. Redeeming points mints a voucher — it only costs the business once someone uses it."
      />

      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <StatCard
          label="Vouchers issued" hint="Personal vouchers minted to date"
          value={o ? String(o.issued) : "—"}
          icon={<Ticket className="size-4 text-muted-foreground" />}
          loading={outstanding.isLoading}
        />
        <StatCard
          label="Spent" hint="Personal vouchers actually used"
          value={o ? String(o.spent) : "—"}
          icon={<Gift className="size-4 text-[var(--color-success)]" />}
          loading={outstanding.isLoading}
        />
        <StatCard
          label="Outstanding" hint="Issued but not yet spent"
          value={o ? String(o.outstanding) : "—"}
          icon={<Wallet className="size-4 text-[var(--color-warning)]" />}
          loading={outstanding.isLoading}
        />
        <StatCard
          label="Outstanding value"
          hint="Flat vouchers only — a percent code's cost depends on the basket"
          value={o ? money(o.outstandingValue) : "—"}
          loading={outstanding.isLoading}
        />
      </div>

      <div className="flex flex-wrap items-center gap-2">
        <Select value={kind} onValueChange={(v) => { setKind(v); setPage(1); }}>
          <SelectTrigger className="w-[220px]"><SelectValue /></SelectTrigger>
          <SelectContent>
            {KINDS.map((k) => (
              <SelectItem key={k.value} value={k.value}>{k.label}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <div className="relative ml-auto w-full sm:w-72">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
          <Input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Coupon, customer or order"
            className="pl-9"
          />
        </div>
      </div>

      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        emptyMessage="No coupons have been redeemed yet."
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
      />
    </div>
  );
}
