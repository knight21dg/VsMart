"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Search, ClipboardList, Undo2 } from "lucide-react";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { DataTable } from "@/components/data-table";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { StatusBadge } from "@/components/status-badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { inr, fmtDate, titleize } from "@/lib/utils";
import { ApiError, type PageMeta } from "@/lib/types";

interface OrderDash {
  ordersToday: number;
  revenueToday: number;
  pending: number;
  packed: number;
  outForDelivery: number;
  deliveredToday: number;
  cancelledToday: number;
  averageOrderValue: number;
  creditOrders: number;
  codOrders: number;
  onlineOrders: number;
}
interface OrderRow {
  code: string;
  placedAt: string;
  customer: string | null;
  phone: string | null;
  store: string | null;
  zone: string | null;
  items: number;
  value: number;
  paymentMethod: string;
  paymentStatus: string;
  status: string;
  deliveryStatus: string | null;
  agent: string | null;
}

const STATUSES = [
  "draft", "placed", "pending", "confirmed", "packed", "ready_for_dispatch",
  "out_for_delivery", "delivered", "cancelled", "rejected", "returned",
  "partially_returned", "failed_delivery",
];
const METHODS = ["cod", "upi", "card", "netbanking", "credit"];
const SORTS = [
  { value: "newest", label: "Newest" },
  { value: "oldest", label: "Oldest" },
  { value: "highest_value", label: "Highest Value" },
  { value: "lowest_value", label: "Lowest Value" },
  { value: "pending_first", label: "Pending First" },
  { value: "cancelled_first", label: "Cancelled First" },
];

function Filter({ value, onChange, placeholder, options }: { value: string; onChange: (v: string) => void; placeholder: string; options: { value: string; label: string }[] }) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className="w-[150px]"><SelectValue placeholder={placeholder} /></SelectTrigger>
      <SelectContent>
        <SelectItem value="all">{placeholder}</SelectItem>
        {options.map((o) => <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>)}
      </SelectContent>
    </Select>
  );
}

const norm = (v: string) => (v === "all" ? undefined : v);

export default function OrdersPage() {
  const router = useRouter();
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [status, setStatus] = React.useState("all");
  const [method, setMethod] = React.useState("all");
  const [sort, setSort] = React.useState("newest");
  const [page, setPage] = React.useState(1);

  React.useEffect(() => {
    const t = setTimeout(() => setQ(search.trim()), 300);
    return () => clearTimeout(t);
  }, [search]);

  // Any filter/sort change must return to page 1 — staying on page N of a
  // now-shorter result set would show an empty table. Adjusted DURING render
  // (React's "reset state when a value changes" pattern) because this project
  // lints setState-inside-an-effect as an error.
  const filterKey = `${q}|${status}|${method}|${sort}`;
  const [prevFilterKey, setPrevFilterKey] = React.useState(filterKey);
  if (prevFilterKey !== filterKey) {
    setPrevFilterKey(filterKey);
    setPage(1);
  }

  const dash = useQuery({ queryKey: ["admin", "orders", "dashboard"], queryFn: () => api.get<OrderDash>("/admin/orders/dashboard") });
  const filters = { q: q || undefined, status: norm(status), payment_method: norm(method), sort };
  const list = useQuery({
    // Paged: the old `limit: 200` made every order past 200 unreachable.
    queryKey: ["admin", "orders", filters, page],
    queryFn: () => api.getPaged<OrderRow>("/admin/orders", { ...filters, page }),
    placeholderData: keepPreviousData,
  });

  const d = dash.data;
  const rows = list.data?.rows ?? [];
  const meta = list.data?.meta as PageMeta | undefined;

  const columns: ColumnDef<OrderRow, unknown>[] = [
    {
      accessorKey: "code",
      header: "Order",
      cell: ({ row }) => (
        <div>
          <p className="font-mono text-xs font-medium">{row.original.code}</p>
          <p className="text-xs text-muted-foreground">{fmtDate(row.original.placedAt, true)}</p>
        </div>
      ),
    },
    {
      accessorKey: "customer",
      header: "Customer",
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="truncate font-medium">{row.original.customer || "—"}</p>
          <p className="font-mono text-xs text-muted-foreground">{row.original.phone}</p>
        </div>
      ),
    },
    {
      accessorKey: "store",
      header: "Store / Zone",
      cell: ({ row }) => (
        <div className="text-xs">
          <p>{row.original.store || "—"}</p>
          <p className="text-muted-foreground">{row.original.zone || "—"}</p>
        </div>
      ),
    },
    { accessorKey: "items", header: "Items", cell: ({ row }) => <span className="tabular-nums">{row.original.items}</span> },
    { accessorKey: "value", header: "Value", cell: ({ row }) => <span className="font-medium">{inr(row.original.value)}</span> },
    {
      accessorKey: "paymentMethod",
      header: "Payment",
      cell: ({ row }) => (
        <div className="space-y-0.5">
          <p className="text-xs font-medium uppercase">{row.original.paymentMethod}</p>
          <StatusBadge status={row.original.paymentStatus} />
        </div>
      ),
    },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
    { accessorKey: "agent", header: "Agent", cell: ({ row }) => <span className="text-sm">{row.original.agent || "—"}</span> },
  ];

  return (
    <>
      <PageHeader
        title="Orders"
        description="All VS Mart orders across stores and zones."
        actions={
          <div className="flex gap-2">
            <Button variant="outline" onClick={() => router.push("/orders/returns")}>
              <Undo2 /> Returns
            </Button>
            <Button variant="outline" onClick={() => router.push("/orders/dispatch")}>
              <ClipboardList /> Packing & Dispatch
            </Button>
          </div>
        }
      />

      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard label="Orders Today" value={d?.ordersToday ?? 0} loading={dash.isLoading} />
        <StatCard label="Revenue Today" value={inr(d?.revenueToday ?? 0)} accent="green" loading={dash.isLoading} />
        <StatCard label="Pending" value={d?.pending ?? 0} accent="gold" loading={dash.isLoading} />
        <StatCard label="Out for Delivery" value={d?.outForDelivery ?? 0} loading={dash.isLoading} />
        <StatCard label="Delivered Today" value={d?.deliveredToday ?? 0} accent="green" loading={dash.isLoading} />
        <StatCard label="Cancelled Today" value={d?.cancelledToday ?? 0} accent="red" loading={dash.isLoading} />
        <StatCard label="Avg Order Value" value={inr(d?.averageOrderValue ?? 0)} loading={dash.isLoading} />
        <StatCard
          label="Credit / COD / Online"
          value={`${d?.creditOrders ?? 0} / ${d?.codOrders ?? 0} / ${d?.onlineOrders ?? 0}`}
          loading={dash.isLoading}
        />
      </div>

      <DataTable
        columns={columns}
        data={rows}
        loading={list.isLoading}
        error={list.isError ? (list.error as ApiError)?.message ?? "Failed to load orders." : null}
        onRetry={() => list.refetch()}
        onRowClick={(row) => router.push(`/orders/${row.code}`)}
        emptyMessage="No orders match your filters."
        pageMeta={meta}
        page={page}
        onPageChange={setPage}
        toolbar={
          <div className="flex flex-wrap items-center gap-2">
            <div className="relative min-w-[200px] flex-1">
              <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search order code, customer, phone…" className="pl-9" />
            </div>
            <Filter value={status} onChange={setStatus} placeholder="Status" options={STATUSES.map((s) => ({ value: s, label: titleize(s) }))} />
            <Filter value={method} onChange={setMethod} placeholder="Payment" options={METHODS.map((m) => ({ value: m, label: m.toUpperCase() }))} />
            <Select value={sort} onValueChange={setSort}>
              <SelectTrigger className="w-[150px]"><SelectValue placeholder="Sort By" /></SelectTrigger>
              <SelectContent>{SORTS.map((s) => <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>)}</SelectContent>
            </Select>
            {/* Real total from the paginator — the old "200+" was the hard cap, not a count. */}
            <span className="ml-auto text-xs text-muted-foreground">
              {(meta?.total ?? rows.length).toLocaleString("en-IN")} orders
            </span>
          </div>
        }
      />
    </>
  );
}
