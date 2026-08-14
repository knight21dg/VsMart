"use client";

import * as React from "react";
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
import { Button } from "@/components/ui/button";
import { inr, cn } from "@/lib/utils";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  BalanceSheetTab, JournalTab, ProfitLossTab, TrialBalanceTab,
} from "@/components/general-ledger";

interface Summary {
  periodDays: number;
  from: string;
  to: string;
  orderBook: {
    placed: number; grossOrdered: number;
    delivered: number; deliveredValue: number;
    inFlight: number; inFlightValue: number;
    returned: number; returnedValue: number;
    cancelled: number; cancelledValue: number;
  };
  revenue: {
    delivered: number; pos: number; posTransactions: number;
    refunds: number; returnsCount: number; net: number;
  };
  cogs: { amount: number | null; coveragePct: number | null; costedUnits: number; totalUnits: number };
  pnl: { netRevenue: number; cogs: number | null; grossProfit: number | null; grossMarginPct: number | null };
  cash: { collected: number; repayments: number; platformFees: number };
  expenses: { procurement: number };
  notes: string[];
}
interface Cashflow {
  series: { date: string; inflow: number; outflow: number; net: number }[];
  totals: { inflow: number; outflow: number; net: number };
  note: string;
}
interface Settlement {
  agentId: string; name: string; deliveries: number; collections: number;
  deliveryPay: number; collectionPay: number; incentives: number;
  earned: number;
  /** null when no payout ledger exists — unknown, not zero. */
  paid: number | null;
  payable: number | null;
}
interface Settlements {
  settlements: Settlement[];
  totalEarned: number;
  totalPaid: number | null;
  totalPayable: number | null;
  payoutsTracked: boolean;
  note: string;
}
interface StorePnl {
  storeId: string | null; store: string; orders: number; grossOrdered: number;
  delivered: number; revenue: number; inFlight: number; platformFees: number;
  procurement: number; revenueLessPurchasing: number;
}

const PERIODS = [7, 30, 90] as const;

/** A figure the backend could not compute reads as "—", never as zero. */
function orDash(v: number | null | undefined, fmt: (n: number) => string) {
  return v === null || v === undefined ? "—" : fmt(v);
}

export default function AccountingPage() {
  const [days, setDays] = React.useState<number>(30);

  const summary = useQuery({
    queryKey: ["acct", "summary", days],
    queryFn: () => api.get<Summary>("/admin/accounting/summary", { days }),
  });
  const cashflow = useQuery({
    queryKey: ["acct", "cashflow", days],
    queryFn: () => api.get<Cashflow>("/admin/accounting/cashflow", { days }),
  });
  const byStore = useQuery({
    queryKey: ["acct", "by-store", days],
    queryFn: () => api.get<{ stores: StorePnl[] }>("/admin/accounting/by-store", { days }),
  });
  const settlements = useQuery({
    queryKey: ["acct", "settlements"],
    queryFn: () => api.get<Settlements>("/admin/accounting/settlements"),
  });

  const s = summary.data;
  const ld = summary.isLoading;
  const ob = s?.orderBook;
  const cfData = (cashflow.data?.series ?? []).map((p) => ({ ...p, label: p.date.slice(5) }));

  const storeColumns: ColumnDef<StorePnl, unknown>[] = [
    { accessorKey: "store", header: "Store", cell: ({ row }) => <span className="font-medium">{row.original.store}</span> },
    { accessorKey: "orders", header: "Orders", cell: ({ row }) => <span className="tabular-nums">{row.original.orders}</span> },
    { accessorKey: "delivered", header: "Delivered", cell: ({ row }) => <span className="tabular-nums">{row.original.delivered}</span> },
    { accessorKey: "revenue", header: "Revenue", cell: ({ row }) => <span className="font-medium">{inr(row.original.revenue)}</span> },
    { accessorKey: "inFlight", header: "In flight", cell: ({ row }) => <span className="text-muted-foreground">{inr(row.original.inFlight)}</span> },
    { accessorKey: "procurement", header: "Purchasing", cell: ({ row }) => inr(row.original.procurement) },
    {
      accessorKey: "revenueLessPurchasing",
      header: "Revenue − purchasing",
      cell: ({ row }) => (
        <span className={row.original.revenueLessPurchasing >= 0 ? "font-medium text-[var(--color-success)]" : "font-medium text-destructive"}>
          {inr(row.original.revenueLessPurchasing)}
        </span>
      ),
    },
  ];

  const columns: ColumnDef<Settlement, unknown>[] = [
    { accessorKey: "name", header: "Agent", cell: ({ row }) => <span className="font-medium">{row.original.name}</span> },
    { accessorKey: "deliveries", header: "Deliveries", cell: ({ row }) => <span className="tabular-nums">{row.original.deliveries}</span> },
    { accessorKey: "collections", header: "Collections", cell: ({ row }) => <span className="tabular-nums">{row.original.collections}</span> },
    { accessorKey: "deliveryPay", header: "Delivery pay", cell: ({ row }) => inr(row.original.deliveryPay) },
    { accessorKey: "collectionPay", header: "Collection pay", cell: ({ row }) => inr(row.original.collectionPay) },
    { accessorKey: "incentives", header: "Incentives", cell: ({ row }) => inr(row.original.incentives) },
    { accessorKey: "earned", header: "Accrued", cell: ({ row }) => <span className="font-semibold">{inr(row.original.earned)}</span> },
    {
      // Unknown, not zero: nothing in the platform records an agent being paid.
      accessorKey: "paid",
      header: "Paid",
      cell: ({ row }) => orDash(row.original.paid, (n) => inr(n)),
    },
  ];

  return (
    <>
      <PageHeader
        title="Accounting"
        description="What the period actually earned, and the double-entry ledger behind it."
        actions={
          <div className="flex items-center gap-1 rounded-lg border bg-card p-1">
            {PERIODS.map((d) => (
              <Button
                key={d}
                size="sm"
                variant={days === d ? "default" : "ghost"}
                onClick={() => setDays(d)}
              >
                {d}d
              </Button>
            ))}
          </div>
        }
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
          {/*
            The order book comes first because it is the thing that makes the rest
            legible: revenue used to be the GMV of every non-cancelled order, so
            money appeared the moment an order was placed. Showing the funnel makes
            it obvious how much of the period's trading has actually landed.
          */}
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-sm">
                Order book{s ? ` · ${s.from} → ${s.to}` : ""}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <div className="grid grid-cols-2 gap-4 sm:grid-cols-5">
                <Funnel label="Placed" n={ob?.placed} value={ob?.grossOrdered} loading={ld} />
                <Funnel label="Delivered" n={ob?.delivered} value={ob?.deliveredValue} loading={ld} tone="good" />
                <Funnel label="In flight" n={ob?.inFlight} value={ob?.inFlightValue} loading={ld} hint="not revenue yet" />
                <Funnel label="Returned" n={ob?.returned} value={ob?.returnedValue} loading={ld} tone="bad" />
                <Funnel label="Cancelled" n={ob?.cancelled} value={ob?.cancelledValue} loading={ld} tone="muted" />
              </div>
            </CardContent>
          </Card>

          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <StatCard
              label="Net Revenue"
              value={inr(s?.revenue.net)}
              accent="green"
              loading={ld}
              hint="delivered + POS − refunds"
            />
            <StatCard
              label="Gross Profit"
              value={orDash(s?.pnl.grossProfit, (n) => inr(n))}
              accent="green"
              loading={ld}
              hint={
                s?.pnl.grossMarginPct != null
                  ? `${s.pnl.grossMarginPct}% margin · COGS on ${s.cogs.coveragePct}% of units`
                  : "no costed stock for these units"
              }
            />
            <StatCard
              label="COGS"
              value={orDash(s?.cogs.amount, (n) => inr(n))}
              accent="gold"
              loading={ld}
              hint={
                s ? `${s.cogs.costedUnits} of ${s.cogs.totalUnits} units costed` : undefined
              }
            />
            <StatCard
              label="Counter (POS)"
              value={inr(s?.revenue.pos)}
              accent="teal"
              loading={ld}
              hint={s ? `${s.revenue.posTransactions} transaction(s)` : undefined}
            />
            <StatCard
              label="Cash Collected"
              value={inr(s?.cash.collected)}
              accent="green"
              loading={ld}
              hint="credit recovered in period"
            />
            <StatCard label="Repayments" value={inr(s?.cash.repayments)} accent="teal" loading={ld} />
            <StatCard
              label="Purchasing (out)"
              value={inr(s?.expenses.procurement)}
              accent="gold"
              loading={ld}
              hint="posted GRNs — not COGS"
            />
            {/* Accrued, not payable. `released` on the earnings ledger is stamped at
                delivery and nothing ever records a payout, so what is still owed is
                genuinely unknown — showing ₹0 there would be an unknown dressed as a
                fact. */}
            <StatCard
              label="Agent Earnings Accrued"
              value={inr(settlements.data?.totalEarned)}
              accent="red"
              loading={settlements.isLoading}
              hint={
                settlements.data && !settlements.data.payoutsTracked
                  ? "payouts not tracked — amount still owed is unknown"
                  : settlements.data
                    ? `${inr(settlements.data.totalPaid)} paid`
                    : undefined
              }
            />
          </div>

          <Card>
            <CardHeader className="pb-2">
              <CardTitle>Cash Flow — last {days} days</CardTitle>
              {cashflow.data && (
                <p className="text-sm text-muted-foreground">
                  In {inr(cashflow.data.totals.inflow)} · Out {inr(cashflow.data.totals.outflow)} ·{" "}
                  <span className={cashflow.data.totals.net >= 0 ? "text-[var(--color-success)]" : "text-destructive"}>
                    Net {inr(cashflow.data.totals.net)}
                  </span>
                </p>
              )}
            </CardHeader>
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
            <h2 className="mb-2 text-sm font-semibold">Trading by Store</h2>
            <DataTable
              columns={storeColumns}
              data={byStore.data?.stores ?? []}
              loading={byStore.isLoading}
              error={byStore.isError ? "Failed to load store trading." : null}
              onRetry={() => byStore.refetch()}
              emptyMessage="No store data for this period."
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
              emptyMessage="No agent earnings recorded."
            />
            {settlements.data?.note && (
              <p className="mt-2 text-xs text-muted-foreground">{settlements.data.note}</p>
            )}
          </div>

          {/* How each figure was arrived at, in the operator's own view rather than
              buried in an API docstring. */}
          {s?.notes?.length ? (
            <Card className="flex items-start gap-3 border-primary/20 bg-primary/5 p-4 text-sm">
              <Info className="mt-0.5 size-4 shrink-0 text-primary" />
              <ul className="space-y-1 text-muted-foreground">
                {s.notes.map((n) => <li key={n}>{n}</li>)}
              </ul>
            </Card>
          ) : null}
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

function Funnel({
  label, n, value, loading, tone = "default", hint,
}: {
  label: string;
  n?: number;
  value?: number;
  loading?: boolean;
  tone?: "default" | "good" | "bad" | "muted";
  hint?: string;
}) {
  const toneClass = {
    default: "",
    good: "text-[var(--color-success)]",
    bad: "text-destructive",
    muted: "text-muted-foreground",
  }[tone];
  return (
    <div className="space-y-0.5">
      <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-muted-foreground">
        {label}
      </p>
      <p className={cn("font-display text-xl font-bold tabular-nums", toneClass)}>
        {loading ? "—" : n ?? 0}
      </p>
      <p className="text-xs tabular-nums text-muted-foreground">
        {loading ? "" : inr(value)}
      </p>
      {hint && <p className="text-[10px] uppercase tracking-wide text-muted-foreground/70">{hint}</p>}
    </div>
  );
}
