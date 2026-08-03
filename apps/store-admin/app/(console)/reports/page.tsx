"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Download } from "lucide-react";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { RequirePerm } from "@/components/permission-gate";
import { StatCard } from "@/components/stat-card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { AreaTrend } from "@/components/trend-chart";
import { LoadingState, ErrorState, EmptyState } from "@/components/states";
import { StatusBadge } from "@/components/status-badge";
import { ProductLink } from "@/components/product-link";
import { downloadCsv, type CsvRow } from "@/lib/csv";
import { inr } from "@/lib/utils";

const REPORTS = [
  { key: "sales", label: "Sales" },
  { key: "inventory", label: "Inventory" },
  { key: "top-products", label: "Top Products" },
  { key: "credit", label: "Credit" },
];

// Reports whose data is windowed by date (the others are point-in-time snapshots).
const DATED = new Set(["sales", "top-products"]);

function isoDaysAgo(n: number) {
  const d = new Date();
  d.setDate(d.getDate() - n);
  return d.toISOString().slice(0, 10);
}

export default function ReportsPage() {
  return (
    <RequirePerm perm="reports.view">
      <ReportsInner />
    </RequirePerm>
  );
}

function ReportsInner() {
  const [active, setActive] = React.useState("sales");
  const [from, setFrom] = React.useState(() => isoDaysAgo(29));
  const [to, setTo] = React.useState(() => isoDaysAgo(0));
  const dated = DATED.has(active);

  const q = useQuery({
    queryKey: ["store", "reports", active, dated ? from : null, dated ? to : null],
    queryFn: () => api.get<Record<string, unknown>>(`/store/reports/${active}`, dated ? { from, to } : {}),
  });

  return (
    <div className="space-y-5">
      <PageHeader
        title="Reports"
        description="Store-level sales, inventory and credit reporting."
        actions={
          q.data ? (
            <Button variant="outline" size="sm" onClick={() => exportReport(active, q.data!)}>
              <Download className="size-3.5" /> Export CSV
            </Button>
          ) : null
        }
      />
      <div className="flex flex-wrap items-center gap-2">
        {REPORTS.map((r) => (
          <button key={r.key} onClick={() => setActive(r.key)}
            className={`rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors ${active === r.key ? "bg-primary text-primary-foreground" : "bg-muted text-muted-foreground hover:bg-accent"}`}>
            {r.label}
          </button>
        ))}
        {dated && (
          <div className="ml-auto flex items-center gap-2 text-sm">
            <Input type="date" value={from} max={to} onChange={(e) => setFrom(e.target.value)} className="h-8 w-[150px]" />
            <span className="text-muted-foreground">to</span>
            <Input type="date" value={to} min={from} max={isoDaysAgo(0)} onChange={(e) => setTo(e.target.value)} className="h-8 w-[150px]" />
          </div>
        )}
      </div>

      {q.isLoading ? <LoadingState /> : q.error || !q.data ? <ErrorState onRetry={() => q.refetch()} /> : (
        <ReportBody name={active} data={q.data} />
      )}
    </div>
  );
}

/** Build a flat, typed CSV from whichever report is in view, then download it. */
function exportReport(name: string, data: Record<string, unknown>) {
  const stamp = new Date().toISOString().slice(0, 10);
  if (name === "sales") {
    const rows = (data.rows as CsvRow[]) ?? [];
    downloadCsv(`sales-${stamp}.csv`, ["date", "revenue", "orders"], rows);
  } else if (name === "top-products") {
    const rows = (data.rows as CsvRow[]) ?? [];
    downloadCsv(`top-products-${stamp}.csv`, ["name", "qtySold", "revenue"], rows);
  } else if (name === "credit") {
    const rows = (data.rows as CsvRow[]) ?? [];
    downloadCsv(`credit-${stamp}.csv`, ["name", "outstanding", "creditLimit", "status"], rows);
  } else if (name === "inventory") {
    const low = ((data.lowStock as CsvRow[]) ?? []).map((r) => ({ ...r, section: "low_stock" }));
    const exp = ((data.expiring as CsvRow[]) ?? []).map((r) => ({ ...r, section: "expiring" }));
    downloadCsv(`inventory-${stamp}.csv`, ["section", "name", "available", "reorderLevel", "expiryDate", "daysLeft"], [...low, ...exp]);
  }
}

function ReportBody({ name, data }: { name: string; data: Record<string, unknown> }) {
  if (name === "sales") {
    const rows = (data.rows as { date: string; revenue: number; orders: number }[]) ?? [];
    const summary = data.summary as { revenue: number; orders: number };
    const chart = rows.map((r) => ({ date: r.date.slice(5), revenue: r.revenue }));
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
          <StatCard label="Revenue" value={inr(summary.revenue)} accent="teal" />
          <StatCard label="Orders" value={summary.orders} accent="green" />
          <StatCard label="Avg / order" value={inr(summary.orders ? summary.revenue / summary.orders : 0)} accent="slate" />
        </div>
        <Card>
          <CardHeader><CardTitle className="text-sm">{String(data.title)}</CardTitle></CardHeader>
          <CardContent className="pt-0"><AreaTrend data={chart} xKey="date" series={[{ key: "revenue", label: "Revenue (₹)" }]} /></CardContent>
        </Card>
      </div>
    );
  }

  if (name === "inventory") {
    const s = data.summary as { stockValue: number; lowStockItems: number; expiringItems: number };
    const low = (data.lowStock as { productId: string; name: string; available: number; reorderLevel: number }[]) ?? [];
    const exp = (data.expiring as { productId: string; name: string; expiryDate: string; daysLeft: number }[]) ?? [];
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-3 gap-3">
          <StatCard label="Stock value" value={inr(s.stockValue)} accent="teal" />
          <StatCard label="Low stock" value={s.lowStockItems} accent="gold" />
          <StatCard label="Expiring" value={s.expiringItems} accent="red" />
        </div>
        <div className="grid gap-4 lg:grid-cols-2">
          <ListCard title="Low stock" rows={low.map((r) => ({ left: <ProductLink id={r.productId} name={r.name} />, right: `${r.available} / ${r.reorderLevel}` }))} />
          <ListCard title="Expiring soon" rows={exp.map((r) => ({ left: <ProductLink id={r.productId} name={r.name} />, right: `${r.daysLeft}d` }))} />
        </div>
      </div>
    );
  }

  if (name === "top-products") {
    const rows = (data.rows as { name: string; qtySold: number; revenue: number }[]) ?? [];
    // Aggregated by OrderItem.name server-side — no product id to link to.
    return <ListCard title={String(data.title)} rows={rows.map((r) => ({ left: <ProductLink name={r.name} />, right: `${r.qtySold} · ${inr(r.revenue)}` }))} />;
  }

  if (name === "credit") {
    const s = data.summary as { totalOutstanding: number; totalLimit: number; accounts: number };
    const rows = (data.rows as { name: string; outstanding: number; creditLimit: number; status: string }[]) ?? [];
    return (
      <div className="space-y-4">
        <div className="grid grid-cols-3 gap-3">
          <StatCard label="Outstanding" value={inr(s.totalOutstanding)} accent="red" />
          <StatCard label="Total limit" value={inr(s.totalLimit)} accent="teal" />
          <StatCard label="Accounts" value={s.accounts} accent="slate" />
        </div>
        <Card>
          <CardHeader><CardTitle className="text-sm">Outstanding by customer</CardTitle></CardHeader>
          <CardContent className="pt-0">
            {rows.length === 0 ? <EmptyState title="No credit accounts" /> : (
              <ul className="divide-y text-sm">
                {rows.map((r, i) => (
                  <li key={i} className="flex items-center justify-between py-2">
                    <span>{r.name}</span>
                    <span className="flex items-center gap-2"><span className="font-medium">{inr(r.outstanding)}</span><StatusBadge status={r.status} /></span>
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    );
  }
  return null;
}

// `left` is a ReactNode so product rows can pass a <ProductLink> rather than a
// bare string; plain-text rows still work unchanged.
function ListCard({ title, rows }: { title: string; rows: { left: React.ReactNode; right: string }[] }) {
  return (
    <Card>
      <CardHeader><CardTitle className="text-sm">{title}</CardTitle></CardHeader>
      <CardContent className="pt-0">
        {rows.length === 0 ? <EmptyState title="Nothing to show" /> : (
          <ul className="divide-y text-sm">
            {rows.map((r, i) => (
              <li key={i} className="flex items-center justify-between gap-2 py-2"><span className="truncate">{r.left}</span><span className="shrink-0 text-muted-foreground">{r.right}</span></li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}
