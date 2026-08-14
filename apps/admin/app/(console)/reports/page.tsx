"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { ChevronLeft, ChevronRight, Download, FileSpreadsheet, FileText, Loader2, X } from "lucide-react";
import { toast } from "sonner";
import { api, API_BASE } from "@/lib/api/client";
import { getAccessToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/page-header";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { LoadingState, ErrorState } from "@/components/states";
import { cn } from "@/lib/utils";

interface ReportData {
  title: string;
  columns: string[];
  rows: (string | number)[][];
  summary?: Record<string, string | number>;
  meta?: { total: number; page: number; pageSize: number };
}
interface StoreRef { id: string; name: string }

const REPORTS = [
  { key: "sales", label: "Sales" },
  { key: "orders", label: "Orders" },
  { key: "credit", label: "Credit" },
  { key: "collections", label: "Collections" },
  { key: "inventory", label: "Inventory" },
  { key: "agents", label: "Agents" },
];

/** Reports whose figures are a position rather than a flow — a date range on a
 *  balance sheet of live credit accounts would be meaningless, so the control is
 *  hidden rather than shown and silently ignored. */
const UNDATED = new Set(["credit", "inventory"]);

const PAGE_SIZE = 100;

function isoDaysAgo(n: number) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
}

export default function ReportsPage() {
  const [active, setActive] = React.useState("sales");
  const [exporting, setExporting] = React.useState<string | null>(null);
  const [from, setFrom] = React.useState(isoDaysAgo(29));
  const [to, setTo] = React.useState(isoDaysAgo(0));
  const [store, setStore] = React.useState<string>("");
  const [page, setPage] = React.useState(1);
  const [sort, setSort] = React.useState<{ col: string; dir: "asc" | "desc" } | null>(null);

  const dated = !UNDATED.has(active);

  // Every control that changes the result set must also reset the page, or page 5
  // of the old filter is requested against the new one.
  React.useEffect(() => { setPage(1); }, [active, from, to, store, sort]);

  const stores = useQuery({
    queryKey: ["admin", "stores", "ref"],
    queryFn: () => api.getPaged<StoreRef>("/admin/stores", { page_size: 200 }),
  });

  /** The exact params the screen is showing — reused verbatim by the export so a
   *  downloaded file can never disagree with the table above it. */
  const params = React.useMemo(() => {
    const p: Record<string, string | number> = {};
    if (dated) { p.date_from = from; p.date_to = to; }
    if (store) p.store = store;
    if (sort) { p.sort = sort.col; p.dir = sort.dir; }
    return p;
  }, [dated, from, to, store, sort]);

  const query = useQuery({
    queryKey: ["reports", active, params, page],
    queryFn: () => api.get<ReportData>(`/reports/${active}`, {
      ...params, page, page_size: PAGE_SIZE,
    }),
  });
  const r = query.data;
  const meta = r?.meta;
  const totalPages = meta?.pageSize ? Math.max(1, Math.ceil(meta.total / meta.pageSize)) : 1;

  async function doExport(fmt: "csv" | "excel" | "pdf") {
    setExporting(fmt);
    try {
      const token = getAccessToken();
      // Same filters as the view. The export deliberately omits page/page_size —
      // a filtered report should download in full, not one screen of it.
      const qs = new URLSearchParams({ type: active, fmt });
      for (const [k, v] of Object.entries(params)) qs.set(k, String(v));
      const res = await fetch(`${API_BASE}/reports/export?${qs}`, {
        headers: token ? { Authorization: `Bearer ${token}` } : undefined,
      });
      if (!res.ok) {
        toast.error(`Export failed (${res.status}).`);
        return;
      }
      const blob = await res.blob();
      const ext = fmt === "excel" ? "xlsx" : fmt;
      const stamp = dated ? `-${from}_${to}` : "";
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `vsmart-${active}${stamp}.${ext}`;
      document.body.appendChild(a);
      a.click();
      a.remove();
      URL.revokeObjectURL(url);
    } catch {
      toast.error("Couldn't download that export.");
    } finally {
      setExporting(null);
    }
  }

  function toggleSort(col: string) {
    setSort((s) =>
      s?.col === col
        ? (s.dir === "asc" ? { col, dir: "desc" } : null)
        : { col, dir: "asc" },
    );
  }

  const storeRows = stores.data?.rows ?? [];
  const filtered = !!store || (dated && (from !== isoDaysAgo(29) || to !== isoDaysAgo(0)));

  return (
    <>
      <PageHeader
        title="Reports & Analytics"
        description="Filter the period, then export exactly what you're looking at."
        actions={
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => doExport("csv")} disabled={!!exporting}>
              {exporting === "csv" ? <Loader2 className="animate-spin" /> : <Download />} CSV
            </Button>
            <Button variant="outline" size="sm" onClick={() => doExport("excel")} disabled={!!exporting}>
              {exporting === "excel" ? <Loader2 className="animate-spin" /> : <FileSpreadsheet />} Excel
            </Button>
            <Button variant="outline" size="sm" onClick={() => doExport("pdf")} disabled={!!exporting}>
              {exporting === "pdf" ? <Loader2 className="animate-spin" /> : <FileText />} PDF
            </Button>
          </div>
        }
      />

      <div className="flex flex-wrap gap-2">
        {REPORTS.map((rep) => (
          <button
            key={rep.key}
            onClick={() => setActive(rep.key)}
            className={cn(
              "rounded-full border px-3.5 py-1.5 text-sm transition-colors",
              active === rep.key
                ? "border-primary bg-primary text-primary-foreground"
                : "bg-card hover:bg-accent"
            )}
          >
            {rep.label}
          </button>
        ))}
      </div>

      <Card className="flex flex-wrap items-end gap-3 p-4">
        {dated && (
          <>
            <div className="space-y-1.5">
              <Label className="text-xs" htmlFor="rep-from">From</Label>
              <Input id="rep-from" type="date" className="h-9 w-[9.5rem]" value={from}
                     max={to} onChange={(e) => setFrom(e.target.value)} />
            </div>
            <div className="space-y-1.5">
              <Label className="text-xs" htmlFor="rep-to">To</Label>
              <Input id="rep-to" type="date" className="h-9 w-[9.5rem]" value={to}
                     min={from} onChange={(e) => setTo(e.target.value)} />
            </div>
            <div className="flex gap-1.5 pb-0.5">
              {[7, 30, 90].map((d) => (
                <Button key={d} size="sm" variant="outline"
                        onClick={() => { setFrom(isoDaysAgo(d - 1)); setTo(isoDaysAgo(0)); }}>
                  {d}d
                </Button>
              ))}
            </div>
          </>
        )}
        <div className="space-y-1.5">
          <Label className="text-xs">Store</Label>
          <Select value={store || "all"} onValueChange={(v) => setStore(v === "all" ? "" : v)}>
            <SelectTrigger className="h-9 w-52"><SelectValue placeholder="All stores" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All stores</SelectItem>
              {storeRows.map((st) => (
                <SelectItem key={st.id} value={String(st.id)}>{st.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        {filtered && (
          <Button variant="ghost" size="sm" className="mb-0.5"
                  onClick={() => { setFrom(isoDaysAgo(29)); setTo(isoDaysAgo(0)); setStore(""); setSort(null); }}>
            <X className="size-3.5" /> Reset
          </Button>
        )}
        {!dated && (
          <p className="mb-2 text-xs text-muted-foreground">
            This report shows current balances, so it isn&apos;t date-filtered.
          </p>
        )}
      </Card>

      <Card className="p-0">
        {query.isLoading ? (
          <LoadingState />
        ) : query.isError || !r ? (
          <ErrorState message="Couldn't load this report." onRetry={() => query.refetch()} />
        ) : (
          <div className="p-1">
            <div className="flex flex-wrap items-center justify-between gap-2 px-3 py-2">
              <p className="text-sm font-medium">{r.title}</p>
              {meta && (
                <p className="text-xs text-muted-foreground">
                  {meta.total.toLocaleString("en-IN")} row{meta.total === 1 ? "" : "s"}
                </p>
              )}
            </div>

            {/* Column totals, so the operator doesn't add the page up by hand — and
                so a filtered view states its own bottom line. */}
            {r.summary && Object.keys(r.summary).length > 0 && (
              <div className="mx-3 mb-2 flex flex-wrap gap-x-6 gap-y-1 rounded-lg bg-muted/50 px-3 py-2 text-sm">
                {Object.entries(r.summary).map(([k, v]) => (
                  <span key={k}>
                    <span className="text-muted-foreground">{k}: </span>
                    <span className="font-semibold tabular-nums">
                      {typeof v === "number" ? v.toLocaleString("en-IN") : v}
                    </span>
                  </span>
                ))}
              </div>
            )}

            <div className="overflow-x-auto">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    {r.columns.map((c) => (
                      <TableHead key={c}>
                        <button
                          className="flex items-center gap-1 hover:text-foreground"
                          onClick={() => toggleSort(c)}
                        >
                          {c}
                          {sort?.col === c && (
                            <span className="text-[10px]">{sort.dir === "asc" ? "▲" : "▼"}</span>
                          )}
                        </button>
                      </TableHead>
                    ))}
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {r.rows.length === 0 ? (
                    <TableRow className="hover:bg-transparent">
                      <TableCell colSpan={r.columns.length} className="py-10 text-center text-sm text-muted-foreground">
                        {filtered
                          ? "No rows match these filters."
                          : "No data for this report."}
                      </TableCell>
                    </TableRow>
                  ) : (
                    r.rows.map((row, i) => (
                      <TableRow key={i}>
                        {row.map((cell, j) => (
                          <TableCell key={j} className={cn(typeof cell === "number" && "tabular-nums")}>
                            {typeof cell === "number" ? cell.toLocaleString("en-IN") : String(cell)}
                          </TableCell>
                        ))}
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </div>

            {meta && totalPages > 1 && (
              <div className="flex items-center justify-end gap-2 px-3 py-2 text-sm text-muted-foreground">
                <span>Page {meta.page} of {totalPages}</span>
                <Button variant="outline" size="icon" disabled={page <= 1}
                        onClick={() => setPage((p) => p - 1)}>
                  <ChevronLeft />
                </Button>
                <Button variant="outline" size="icon" disabled={page >= totalPages}
                        onClick={() => setPage((p) => p + 1)}>
                  <ChevronRight />
                </Button>
              </div>
            )}
          </div>
        )}
      </Card>
    </>
  );
}
