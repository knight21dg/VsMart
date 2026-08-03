"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { keepPreviousData, useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Search, Download, ChevronDown, Loader2 } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { getAccessToken } from "@/lib/auth/session";
import { DataTable } from "@/components/data-table";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { StatusBadge, BoolBadge } from "@/components/status-badge";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { inr } from "@/lib/utils";
import { ApiError, type PageMeta } from "@/lib/types";

export interface AdminCustomer {
  id: string;
  vsId?: string;
  phone: string;
  name: string;
  kycStatus?: string;
  vsScore?: number | null;
  outstanding?: number;
  risk?: string;
  active?: boolean;
  /** Credit account state: "active" | "frozen" | "closed", or null if no account. */
  creditStatus?: string | null;
}

interface NamedRef {
  id: string;
  name: string;
}

const SORTS: { value: string; label: string }[] = [
  { value: "newest", label: "Newest Customers" },
  { value: "oldest", label: "Oldest Customers" },
  { value: "highest_outstanding", label: "Highest Outstanding" },
  { value: "highest_vs_score", label: "Highest VS Score" },
  { value: "lowest_vs_score", label: "Lowest VS Score" },
  { value: "most_orders", label: "Most Orders" },
  { value: "highest_revenue", label: "Highest Revenue" },
  { value: "high_risk_first", label: "High Risk First" },
  { value: "low_risk_first", label: "Low Risk First" },
  { value: "recently_active", label: "Recently Active" },
  { value: "inactive", label: "Inactive Customers" },
];

const KYC_OPTS = ["not_started", "pending", "verified", "rejected"];
const RISK_OPTS = ["low", "medium", "high", "critical"];

/** A compact filter dropdown. "all" maps to no filter. */
function FilterSelect({
  value,
  onChange,
  placeholder,
  options,
  width = "w-[130px]",
}: {
  value: string;
  onChange: (v: string) => void;
  placeholder: string;
  options: { value: string; label: string }[];
  width?: string;
}) {
  return (
    <Select value={value} onValueChange={onChange}>
      <SelectTrigger className={width}>
        <SelectValue placeholder={placeholder} />
      </SelectTrigger>
      <SelectContent>
        <SelectItem value="all">{placeholder}</SelectItem>
        {options.map((o) => (
          <SelectItem key={o.value} value={o.value}>
            {o.label}
          </SelectItem>
        ))}
      </SelectContent>
    </Select>
  );
}

const cap = (s: string) => s.replace(/[_-]+/g, " ").replace(/\b\w/g, (c) => c.toUpperCase());
const norm = (v: string) => (v === "all" ? undefined : v);

async function downloadFile(path: string, params: Record<string, string | undefined>, filename: string) {
  const res = await fetch(api.buildUrl(path, params), {
    headers: { Authorization: `Bearer ${getAccessToken() ?? ""}` },
  });
  const blob = await res.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

export function CustomersTable({ basePath = "/customers" }: { basePath?: string }) {
  const router = useRouter();
  const [search, setSearch] = React.useState("");
  const [q, setQ] = React.useState("");
  const [zone, setZone] = React.useState("all");
  const [store, setStore] = React.useState("all");
  const [risk, setRisk] = React.useState("all");
  const [kyc, setKyc] = React.useState("all");
  const [credit, setCredit] = React.useState("all");
  const [status, setStatus] = React.useState("all");
  // Credit ACCOUNT state (active/frozen/closed) — separate from `status`, which
  // is the user account's active/suspended flag.
  const [creditStatus, setCreditStatus] = React.useState("all");
  const [sort, setSort] = React.useState("newest");
  const [selected, setSelected] = React.useState<Set<string>>(new Set());
  const [notifyOpen, setNotifyOpen] = React.useState(false);
  const [notifyTitle, setNotifyTitle] = React.useState("");
  const [notifyBody, setNotifyBody] = React.useState("");
  const [page, setPage] = React.useState(1);

  React.useEffect(() => {
    const t = setTimeout(() => setQ(search.trim()), 300);
    return () => clearTimeout(t);
  }, [search]);

  const filters = {
    q: q || undefined,
    zone: norm(zone),
    store: norm(store),
    risk: norm(risk),
    kyc: norm(kyc),
    credit: norm(credit),
    status: norm(status),
    creditStatus: norm(creditStatus),
    sort,
  };

  // Any filter/sort change must return to page 1 — staying on page N of a
  // now-shorter result set would show an empty table. Adjusted DURING render
  // (React's "reset state when a value changes" pattern) because this project
  // lints setState-inside-an-effect as an error.
  const filterKey = JSON.stringify(filters);
  const [prevFilterKey, setPrevFilterKey] = React.useState(filterKey);
  if (prevFilterKey !== filterKey) {
    setPrevFilterKey(filterKey);
    setPage(1);
  }

  // Paged: the old `limit: 200` made every customer past 200 unreachable, with
  // nothing on screen saying the directory had been cut off.
  const query = useQuery({
    queryKey: ["admin", "crm", "customers", filters, page],
    queryFn: () => api.getPaged<AdminCustomer>("/admin/crm/customers", { ...filters, page }),
    placeholderData: keepPreviousData,
  });
  const zonesQ = useQuery({ queryKey: ["admin", "zones", "ref"], queryFn: () => api.get<NamedRef[]>("/admin/zones") });
  const storesQ = useQuery({ queryKey: ["admin", "stores", "ref"], queryFn: () => api.get<NamedRef[]>("/admin/stores") });

  const rows = query.data?.rows ?? [];
  const pageMeta = query.data?.meta as PageMeta | undefined;
  const allSelected = rows.length > 0 && rows.every((r) => selected.has(r.id));

  function toggleAll() {
    setSelected(allSelected ? new Set() : new Set(rows.map((r) => r.id)));
  }
  function toggleOne(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  const bulk = useApiMutation(
    (vars: Record<string, unknown>) => api.post("/admin/crm/customers/bulk", vars),
    {
      invalidate: [["admin", "crm", "customers"]],
      successMessage: "Bulk action applied.",
      onDone: () => setSelected(new Set()),
    }
  );

  function runBulk(action: string, extra: Record<string, unknown> = {}) {
    bulk.mutate({ action, customerIds: [...selected], ...extra });
  }

  const columns: ColumnDef<AdminCustomer, unknown>[] = [
    {
      id: "select",
      header: () => (
        <input type="checkbox" checked={allSelected} onChange={toggleAll} aria-label="Select all" className="size-4" />
      ),
      cell: ({ row }) => (
        <input
          type="checkbox"
          checked={selected.has(row.original.id)}
          onChange={() => toggleOne(row.original.id)}
          onClick={(e) => e.stopPropagation()}
          aria-label="Select row"
          className="size-4"
        />
      ),
    },
    {
      accessorKey: "name",
      header: "Customer",
      cell: ({ row }) => (
        <div className="min-w-0">
          <p className="truncate font-medium">{row.original.name || "—"}</p>
          <p className="font-mono text-xs text-muted-foreground">{row.original.vsId ?? "—"}</p>
        </div>
      ),
    },
    { accessorKey: "phone", header: "Phone", cell: ({ row }) => <span className="font-mono text-xs">{row.original.phone}</span> },
    { accessorKey: "vsScore", header: "VS Score", cell: ({ row }) => <span className="tabular-nums">{row.original.vsScore ?? "—"}</span> },
    {
      accessorKey: "outstanding",
      header: "Outstanding",
      cell: ({ row }) => {
        const v = row.original.outstanding ?? 0;
        return <span className={v > 0 ? "font-medium text-destructive" : "text-muted-foreground"}>{inr(v)}</span>;
      },
    },
    { accessorKey: "risk", header: "Risk", cell: ({ row }) => <StatusBadge status={row.original.risk} /> },
    { accessorKey: "kycStatus", header: "KYC", cell: ({ row }) => <StatusBadge status={row.original.kycStatus} /> },
    {
      accessorKey: "creditStatus", header: "Credit",
      cell: ({ row }) => (
        row.original.creditStatus
          ? <StatusBadge status={row.original.creditStatus} />
          : <span className="text-xs text-muted-foreground">—</span>
      ),
    },
    { accessorKey: "active", header: "Status", cell: ({ row }) => <BoolBadge value={row.original.active ?? true} trueLabel="Active" falseLabel="Suspended" /> },
  ];

  return (
    <>
      <DataTable
        columns={columns}
        data={rows}
        loading={query.isLoading}
        error={query.isError ? (query.error as ApiError)?.message ?? "Failed to load customers." : null}
        onRetry={() => query.refetch()}
        onRowClick={(row) => router.push(`${basePath}/${row.id}`)}
        emptyMessage="No customers match your filters."
        pageMeta={pageMeta}
        page={page}
        onPageChange={setPage}
        toolbar={
          <div className="space-y-3">
            {/* Search */}
            <div className="relative">
              <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground" />
              <Input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Search customer — name, phone, VS ID, village…" className="pl-9" />
            </div>
            {/* Filters + sort + export */}
            <div className="flex flex-wrap items-center gap-2">
              <FilterSelect value={zone} onChange={setZone} placeholder="Zone" options={(zonesQ.data ?? []).map((z) => ({ value: z.id, label: z.name }))} />
              <FilterSelect value={store} onChange={setStore} placeholder="Store" options={(storesQ.data ?? []).map((s) => ({ value: s.id, label: s.name }))} />
              <FilterSelect value={risk} onChange={setRisk} placeholder="Risk" options={RISK_OPTS.map((r) => ({ value: r, label: cap(r) }))} />
              <FilterSelect value={kyc} onChange={setKyc} placeholder="KYC" options={KYC_OPTS.map((k) => ({ value: k, label: cap(k) }))} />
              <FilterSelect value={credit} onChange={setCredit} placeholder="Credit" options={[{ value: "yes", label: "Has Credit" }, { value: "no", label: "No Credit" }]} />
              <FilterSelect value={status} onChange={setStatus} placeholder="Status" options={[{ value: "active", label: "Active" }, { value: "suspended", label: "Suspended" }]} />
              <FilterSelect
                value={creditStatus}
                onChange={setCreditStatus}
                placeholder="Credit Status"
                options={[
                  { value: "active", label: "Credit Active" },
                  { value: "frozen", label: "Frozen" },
                  { value: "closed", label: "Closed" },
                ]}
              />
              <Select value={sort} onValueChange={setSort}>
                <SelectTrigger className="w-[170px]">
                  <SelectValue placeholder="Sort By" />
                </SelectTrigger>
                <SelectContent>
                  {SORTS.map((s) => (
                    <SelectItem key={s.value} value={s.value}>{s.label}</SelectItem>
                  ))}
                </SelectContent>
              </Select>
              <div className="ml-auto flex items-center gap-2">
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button variant="outline" size="sm">
                      <Download /> Export <ChevronDown />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="end">
                    <DropdownMenuItem onSelect={() => downloadFile("/admin/crm/customers/export", { ...filters, limit: undefined, fmt: "csv" } as Record<string, string | undefined>, "customers.csv")}>
                      Export CSV
                    </DropdownMenuItem>
                    <DropdownMenuItem onSelect={() => downloadFile("/admin/crm/customers/export", { ...filters, limit: undefined, fmt: "excel" } as Record<string, string | undefined>, "customers.xlsx")}>
                      Export Excel
                    </DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
              </div>
            </div>
            {/* Bulk actions bar (appears with a selection) */}
            {selected.size > 0 && (
              <div className="flex items-center gap-3 rounded-lg border bg-primary/5 px-3 py-2 text-sm">
                <span className="font-medium">{selected.size} selected</span>
                <DropdownMenu>
                  <DropdownMenuTrigger asChild>
                    <Button size="sm" disabled={bulk.isPending}>
                      {bulk.isPending ? <Loader2 className="animate-spin" /> : null} Bulk Actions <ChevronDown />
                    </Button>
                  </DropdownMenuTrigger>
                  <DropdownMenuContent align="start">
                    <DropdownMenuItem onSelect={() => runBulk("freeze_credit")}>Freeze Credit</DropdownMenuItem>
                    <DropdownMenuItem onSelect={() => runBulk("unfreeze_credit")}>Unfreeze Credit</DropdownMenuItem>
                    <DropdownMenuItem onSelect={() => runBulk("assign_collection")}>Assign Collection</DropdownMenuItem>
                    <DropdownMenuItem onSelect={() => setNotifyOpen(true)}>Send Notification</DropdownMenuItem>
                  </DropdownMenuContent>
                </DropdownMenu>
                <Button variant="ghost" size="sm" onClick={() => setSelected(new Set())}>Clear</Button>
                <span className="ml-auto text-xs text-muted-foreground">{rows.length}{rows.length === 200 ? "+" : ""} shown</span>
              </div>
            )}
          </div>
        }
      />

      <Dialog open={notifyOpen} onOpenChange={setNotifyOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Send Notification to {selected.size} customer{selected.size === 1 ? "" : "s"}</DialogTitle>
          </DialogHeader>
          <div className="space-y-3">
            <div className="space-y-1.5">
              <Label htmlFor="ntitle">Title</Label>
              <Input id="ntitle" value={notifyTitle} onChange={(e) => setNotifyTitle(e.target.value)} placeholder="Payment reminder" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="nbody">Message</Label>
              <Input id="nbody" value={notifyBody} onChange={(e) => setNotifyBody(e.target.value)} placeholder="Your dues are pending…" />
            </div>
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setNotifyOpen(false)} disabled={bulk.isPending}>Cancel</Button>
            <Button
              disabled={bulk.isPending || !notifyTitle.trim()}
              onClick={() => {
                runBulk("send_notification", { title: notifyTitle, body: notifyBody });
                setNotifyOpen(false);
                setNotifyTitle("");
                setNotifyBody("");
              }}
            >
              {bulk.isPending && <Loader2 className="size-4 animate-spin" />} Send
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  );
}
