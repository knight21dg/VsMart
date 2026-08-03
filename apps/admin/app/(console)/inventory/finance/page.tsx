"use client";

import { useQuery } from "@tanstack/react-query";
import { Info } from "lucide-react";
import { api } from "@/lib/api/client";
import { InvNav } from "@/components/inventory/inv-nav";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { inr } from "@/lib/utils";
import type { Finance } from "@/lib/inventory";

export default function FinancePage() {
  const query = useQuery({ queryKey: ["inv", "finance"], queryFn: () => api.get<Finance>("/inventory/finance", { days: 30 }) });
  const f = query.data;
  const ld = query.isLoading;

  return (
    <>
      <PageHeader title="Inventory Finance" description="What the inventory is worth — and what it's costing." />
      <InvNav />

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard label="Inventory Value" value={inr(f?.inventoryValue)} accent="green" loading={ld} />
        <StatCard label="Expected Revenue" value={inr(f?.expectedRevenue)} accent="teal" loading={ld} hint="if all available stock sells" />
        <StatCard label="Margin Potential" value={inr(f?.marginPotential)} accent="green" loading={ld} />
        <StatCard label="Dead Stock Value" value={inr(f?.deadStockValue)} accent="red" loading={ld} hint="locked, 90d+ idle" />
        <StatCard label="Turnover (annualised)" value={`${f?.turnoverRatio ?? 0}×`} accent="teal" loading={ld} />
        <StatCard label="GMROI" value={`${f?.gmroi ?? 0}`} accent="teal" loading={ld} hint="gross margin / inventory" />
        <StatCard label="Holding Cost (30d)" value={inr(f?.holdingCost)} accent="gold" loading={ld} />
        <StatCard label="Shrinkage" value={inr(f?.shrinkageValue)} accent="red" loading={ld} hint={`${f?.shrinkagePct ?? 0}% · ${f?.shrinkageUnits ?? 0} units`} />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader><CardTitle>P&L Inputs (last {f?.periodDays ?? 30} days)</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-sm">
            <Row label="COGS (period)" value={inr(f?.cogsPeriod)} />
            <Row label="COGS (annualised)" value={inr(f?.cogsAnnualized)} />
            <Row label="Gross margin (period)" value={inr(f?.grossMarginPeriod)} />
            <Row label="Inventory turnover" value={`${f?.turnoverRatio ?? 0}×`} />
            <Row label="GMROI" value={`${f?.gmroi ?? 0}`} />
          </CardContent>
        </Card>

        <Card className="border-primary/20 bg-primary/5">
          <CardHeader><CardTitle className="flex items-center gap-2"><Info className="size-4 text-primary" /> Assumptions</CardTitle></CardHeader>
          <CardContent className="space-y-2 text-sm text-muted-foreground">
            <p>• Holding cost uses an assumed annual carrying rate of <span className="font-medium text-foreground">{((f?.assumptions.carryingRate ?? 0.24) * 100).toFixed(0)}%</span> (not configured in the backend yet).</p>
            <p>• Turnover is annualised from the {f?.periodDays ?? 30}-day window and compared to current inventory value.</p>
            <p>• COGS/GMROI use weighted-average cost from the ledger. No demand forecasting is applied.</p>
          </CardContent>
        </Card>
      </div>
    </>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between border-b py-2 last:border-0">
      <span className="text-muted-foreground">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}
