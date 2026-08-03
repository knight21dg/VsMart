"use client";

import { useParams, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Boxes, TrendingUp } from "lucide-react";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { LoadingState, ErrorState } from "@/components/states";
import { fmtDate, inr } from "@/lib/utils";
import type { ProductOverview } from "@/lib/inventory";

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs uppercase tracking-wide text-muted-foreground">{label}</p>
      <div className="mt-0.5 text-sm font-medium">{children}</div>
    </div>
  );
}

export default function ProductIntelligencePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const query = useQuery({
    queryKey: ["inv", "product", id],
    queryFn: () => api.get<ProductOverview>(`/inventory/products/${id}/overview`),
  });
  const d = query.data;

  return (
    <>
      <Button variant="ghost" size="sm" className="-ml-2 w-fit" onClick={() => router.back()}>
        <ArrowLeft /> Back
      </Button>

      {query.isLoading ? (
        <LoadingState />
      ) : query.isError || !d ? (
        <ErrorState message="Couldn't load this product." onRetry={() => query.refetch()} />
      ) : (
        <>
          <PageHeader title={d.summary.name} description={`${d.summary.brand || "—"} · ${d.summary.category}`} />

          {/* totals */}
          <div className="grid grid-cols-2 gap-4 md:grid-cols-5">
            <StatCard label="On Hand" value={d.totals.onHand} icon={<Boxes />} accent="teal" />
            <StatCard label="Reserved" value={d.totals.reserved} accent="slate" />
            <StatCard label="Available" value={d.totals.available} accent="green" />
            <StatCard label="Damaged" value={d.totals.damaged} accent={d.totals.damaged ? "red" : "slate"} />
            <StatCard label="Network Value" value={inr(d.totals.networkValue)} accent="green" />
          </div>

          <div className="grid gap-4 lg:grid-cols-3">
            {/* summary */}
            <Card>
              <CardHeader><CardTitle>Product</CardTitle></CardHeader>
              <CardContent className="grid grid-cols-2 gap-4">
                <Field label="Unit">{d.summary.unit}</Field>
                <Field label="Selling Price">{inr(d.summary.sellingPrice)}</Field>
                <Field label="MRP">{inr(d.summary.mrp)}</Field>
                <Field label="Avg Cost (WAC)">{inr(d.summary.avgCost)}</Field>
                <Field label="Margin">{inr(d.summary.margin)} ({d.summary.marginPct}%)</Field>
                <Field label="Credit Price">{d.summary.creditPrice != null ? inr(d.summary.creditPrice) : "—"}</Field>
              </CardContent>
            </Card>

            {/* velocity */}
            <Card>
              <CardHeader><CardTitle className="flex items-center gap-2"><TrendingUp className="size-4" /> Velocity</CardTitle></CardHeader>
              <CardContent className="grid grid-cols-2 gap-4">
                <Field label="Sold (7d)">{d.velocity.units7d}</Field>
                <Field label="Sold (30d)">{d.velocity.units30d}</Field>
                <Field label="Sold (90d)">{d.velocity.units90d}</Field>
                <Field label="Avg / day">{d.velocity.avgDaily}</Field>
                <Field label="Last Sale">{d.velocity.lastSale ? fmtDate(d.velocity.lastSale) : "Never"}</Field>
              </CardContent>
            </Card>

            {/* reorder */}
            <Card>
              <CardHeader><CardTitle>Reorder Intelligence</CardTitle></CardHeader>
              <CardContent className="grid grid-cols-2 gap-4">
                <Field label="Avg Daily">{d.reorder.avgDaily}</Field>
                <Field label="Days Remaining">{d.reorder.daysRemaining ?? "∞"}</Field>
                <Field label="Suggested Qty">
                  {d.reorder.suggestedQty > 0 ? <Badge variant="warning">{d.reorder.suggestedQty}</Badge> : <Badge variant="success">Healthy</Badge>}
                </Field>
                <Field label="Lead Time">{d.reorder.leadTimeDays}d (assumed)</Field>
              </CardContent>
            </Card>
          </div>

          {/* distribution */}
          <Card>
            <CardHeader><CardTitle>Network Distribution</CardTitle></CardHeader>
            <CardContent className="p-0">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead>Warehouse / Store</TableHead><TableHead>On Hand</TableHead><TableHead>Reserved</TableHead><TableHead>Available</TableHead><TableHead>Damaged</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {d.distribution.map((r) => (
                    <TableRow key={r.warehouseId}>
                      <TableCell className="font-medium">{r.warehouse}</TableCell>
                      <TableCell className="tabular-nums">{r.onHand}</TableCell>
                      <TableCell className="tabular-nums">{r.reserved}</TableCell>
                      <TableCell className="font-medium tabular-nums">{r.available}</TableCell>
                      <TableCell className="tabular-nums">{r.damaged}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>

          <div className="grid gap-4 lg:grid-cols-2">
            {/* suppliers */}
            <Card>
              <CardHeader><CardTitle>Supplier History</CardTitle></CardHeader>
              <CardContent className="p-0">
                {d.suppliers.length === 0 ? (
                  <p className="py-8 text-center text-sm text-muted-foreground">No purchase history.</p>
                ) : (
                  <Table>
                    <TableHeader>
                      <TableRow className="hover:bg-transparent"><TableHead>Supplier</TableHead><TableHead>Qty</TableHead><TableHead>Avg Cost</TableHead><TableHead>Orders</TableHead><TableHead>Last</TableHead></TableRow>
                    </TableHeader>
                    <TableBody>
                      {d.suppliers.map((s, i) => (
                        <TableRow key={i}>
                          <TableCell className="font-medium">{s.supplier}</TableCell>
                          <TableCell className="tabular-nums">{s.totalQty}</TableCell>
                          <TableCell>{inr(s.avgCost)}</TableCell>
                          <TableCell>{s.orders}</TableCell>
                          <TableCell className="text-muted-foreground">{s.lastOrder ? fmtDate(s.lastOrder) : "—"}</TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                )}
              </CardContent>
            </Card>

            {/* movement timeline */}
            <Card>
              <CardHeader><CardTitle>Movement Timeline</CardTitle></CardHeader>
              <CardContent className="p-0">
                <Table>
                  <TableHeader>
                    <TableRow className="hover:bg-transparent"><TableHead>Time</TableHead><TableHead>Type</TableHead><TableHead>Qty</TableHead><TableHead>Balance</TableHead></TableRow>
                  </TableHeader>
                  <TableBody>
                    {d.ledger.map((e) => (
                      <TableRow key={e.id}>
                        <TableCell className="text-xs text-muted-foreground">{fmtDate(e.createdAt, true)}</TableCell>
                        <TableCell><Badge variant="secondary">{e.type}</Badge></TableCell>
                        <TableCell className={"tabular-nums " + (e.quantity < 0 ? "text-destructive" : "text-[var(--color-success)]")}>{e.quantity > 0 ? "+" : ""}{e.quantity}</TableCell>
                        <TableCell className="tabular-nums">{e.balanceAfter}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </CardContent>
            </Card>
          </div>
        </>
      )}
    </>
  );
}
