"use client";

import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { Info } from "lucide-react";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { DataTable } from "@/components/data-table";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { AreaTrend } from "@/components/trend-chart";
import { LoadingState } from "@/components/states";
import { inr } from "@/lib/utils";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  BalanceSheetTab, JournalTab, ProfitLossTab, TrialBalanceTab,
} from "@/components/general-ledger";

interface Summary {
  periodDays: number;
  income: { revenue: number; platformFees: number; cashCollected: number; repayments: number };
  expenses: { procurement: number };
  pnl: { grossRevenue: number; cogsProxy: number; grossProfit: number; grossMarginPct: number };
  note: string;
}
interface Cashflow { series: { date: string; inflow: number; outflow: number; net: number }[] }
interface Settlement { agentId: string; name: string; deliveries: number; collections: number; incentives: number; base: number; payable: number }
interface StorePnl { storeId: string | null; store: string; revenue: number; orders: number; platformFees: number; procurement: number; margin: number }

export default function AccountingPage() {
  const summary = useQuery({ queryKey: ["acct", "summary"], queryFn: () => api.get<Summary>("/admin/accounting/summary", { days: 30 }) });
  const cashflow = useQuery({ queryKey: ["acct", "cashflow"], queryFn: () => api.get<Cashflow>("/admin/accounting/cashflow", { days: 30 }) });
  const byStore = useQuery({ queryKey: ["acct", "by-store"], queryFn: () => api.get<{ stores: StorePnl[] }>("/admin/accounting/by-store", { days: 30 }) });
  const settlements = useQuery({ queryKey: ["acct", "settlements"], queryFn: () => api.get<{ settlements: Settlement[]; totalPayable: number }>("/admin/accounting/settlements") });

  const s = summary.data;
  const ld = summary.isLoading;
  const cfData = (cashflow.data?.series ?? []).map((p) => ({ ...p, label: p.date.slice(5) }));

  const storeColumns: ColumnDef<StorePnl, unknown>[] = [
    { accessorKey: "store", header: "Store", cell: ({ row }) => <span className="font-medium">{row.original.store}</span> },
    { accessorKey: "orders", header: "Orders", cell: ({ row }) => <span className="tabular-nums">{row.original.orders}</span> },
    { accessorKey: "revenue", header: "Revenue", cell: ({ row }) => inr(row.original.revenue) },
    { accessorKey: "platformFees", header: "Platform Fees", cell: ({ row }) => inr(row.original.platformFees) },
    { accessorKey: "procurement", header: "Procurement", cell: ({ row }) => inr(row.original.procurement) },
    { accessorKey: "margin", header: "Margin", cell: ({ row }) => <span className={row.original.margin >= 0 ? "font-medium text-[var(--color-success)]" : "font-medium text-destructive"}>{inr(row.original.margin)}</span> },
  ];

  const columns: ColumnDef<Settlement, unknown>[] = [
    { accessorKey: "name", header: "Agent", cell: ({ row }) => <span className="font-medium">{row.original.name}</span> },
    { accessorKey: "deliveries", header: "Deliveries", cell: ({ row }) => <span className="tabular-nums">{row.original.deliveries}</span> },
    { accessorKey: "collections", header: "Collections", cell: ({ row }) => <span className="tabular-nums">{row.original.collections}</span> },
    { accessorKey: "incentives", header: "Incentives", cell: ({ row }) => inr(row.original.incentives) },
    { accessorKey: "payable", header: "Payable", cell: ({ row }) => <span className="font-semibold">{inr(row.original.payable)}</span> },
  ];

  return (
    <>
      <PageHeader
        title="Accounting"
        description="Operational figures at a glance, and the double-entry ledger behind them."
      />

      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="pnl">Profit &amp; Loss</TabsTrigger>
          <TabsTrigger value="balance">Balance Sheet</TabsTrigger>
          <TabsTrigger value="trial">Trial Balance</TabsTrigger>
          <TabsTrigger value="journal">Journal</TabsTrigger>
        </TabsList>

        <TabsContent value="overview">

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Revenue (GMV)" value={inr(s?.income.revenue)} accent="green" loading={ld} />
        <StatCard label="Gross Profit" value={inr(s?.pnl.grossProfit)} accent="green" loading={ld} hint={`${s?.pnl.grossMarginPct ?? 0}% margin`} />
        <StatCard label="Procurement (COGS proxy)" value={inr(s?.expenses.procurement)} accent="gold" loading={ld} />
        <StatCard label="Platform Fees" value={inr(s?.income.platformFees)} accent="teal" loading={ld} />
        <StatCard label="Cash Collected" value={inr(s?.income.cashCollected)} accent="green" loading={ld} />
        <StatCard label="Repayments" value={inr(s?.income.repayments)} accent="teal" loading={ld} />
        <StatCard label="Agent Settlements Due" value={inr(settlements.data?.totalPayable)} accent="red" loading={settlements.isLoading} />
        <StatCard label="Net (Rev − COGS)" value={inr(s?.pnl.grossProfit)} accent="slate" loading={ld} />
      </div>

      <Card>
        <CardHeader><CardTitle>Cash Flow — last 30 days</CardTitle></CardHeader>
        <CardContent>
          {cashflow.isLoading ? (
            <LoadingState />
          ) : (
            <AreaTrend
              data={cfData}
              xKey="label"
              series={[
                { key: "inflow", label: "Inflow", color: "var(--color-chart-2)" },
                { key: "outflow", label: "Outflow", color: "var(--color-chart-3)" },
              ]}
            />
          )}
        </CardContent>
      </Card>

      <div>
        <h2 className="mb-2 text-sm font-semibold">P&L by Store</h2>
        <DataTable
          columns={storeColumns}
          data={byStore.data?.stores ?? []}
          loading={byStore.isLoading}
          error={byStore.isError ? "Failed to load store P&L." : null}
          onRetry={() => byStore.refetch()}
          emptyMessage="No store data."
        />
      </div>

      <div>
        <h2 className="mb-2 text-sm font-semibold">Agent Settlements</h2>
        <DataTable
          columns={columns}
          data={settlements.data?.settlements ?? []}
          loading={settlements.isLoading}
          error={settlements.isError ? "Failed to load settlements." : null}
          onRetry={() => settlements.refetch()}
          emptyMessage="No settlements due."
        />
      </div>

      {s?.note && (
          <Card className="flex items-start gap-3 border-primary/20 bg-primary/5 p-4 text-sm">
            <Info className="mt-0.5 size-4 shrink-0 text-primary" />
            <p className="text-muted-foreground">{s.note}</p>
          </Card>
        )}
        </TabsContent>

        {/* The statutory ledger: derived from journal postings, not aggregates. */}
        <TabsContent value="pnl"><ProfitLossTab /></TabsContent>
        <TabsContent value="balance"><BalanceSheetTab /></TabsContent>
        <TabsContent value="trial"><TrialBalanceTab /></TabsContent>
        <TabsContent value="journal"><JournalTab /></TabsContent>
      </Tabs>
    </>
  );
}
