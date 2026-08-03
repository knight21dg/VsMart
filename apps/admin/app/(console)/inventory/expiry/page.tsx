"use client";

import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { api } from "@/lib/api/client";
import { InvNav } from "@/components/inventory/inv-nav";
import { PageHeader } from "@/components/page-header";
import { DataTable } from "@/components/data-table";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { LoadingState } from "@/components/states";
import { ProductLink } from "@/components/product-link";
import type { AgingBucket, NearExpiry } from "@/lib/inventory";
import { inr } from "@/lib/utils";

export default function ExpiryAgingPage() {
  const query = useQuery({
    queryKey: ["inv", "aging"],
    queryFn: () => api.get<{ aging: AgingBucket[]; nearExpiry: NearExpiry[] }>("/inventory/aging"),
  });
  const aging = query.data?.aging ?? [];
  const maxVal = Math.max(...aging.map((a) => a.value), 1);

  const columns: ColumnDef<NearExpiry, unknown>[] = [
    { accessorKey: "name", header: "Product", cell: ({ row }) => <ProductLink id={row.original.productId} name={row.original.name} className="font-medium" /> },
    { accessorKey: "batchNo", header: "Batch", cell: ({ row }) => <span className="font-mono text-xs">{row.original.batchNo}</span> },
    { accessorKey: "quantity", header: "Qty", cell: ({ row }) => <span className="tabular-nums">{row.original.quantity}</span> },
    { accessorKey: "value", header: "Value", cell: ({ row }) => inr(row.original.value) },
    { accessorKey: "expiryDate", header: "Expiry", cell: ({ row }) => new Date(row.original.expiryDate).toLocaleDateString("en-IN") },
    {
      accessorKey: "daysToExpiry",
      header: "Days Left",
      cell: ({ row }) => {
        const d = row.original.daysToExpiry;
        return <Badge variant={d <= 7 ? "destructive" : d <= 15 ? "warning" : "secondary"}>{d}d</Badge>;
      },
    },
  ];

  return (
    <>
      <PageHeader title="Expiry & Aging" description="Stock aging buckets and near-expiry batches." />
      <InvNav />

      <Card>
        <CardHeader><CardTitle>Inventory Aging (by batch age)</CardTitle></CardHeader>
        <CardContent>
          {query.isLoading ? (
            <LoadingState />
          ) : (
            <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
              {aging.map((a) => (
                <div key={a.bucket} className="rounded-lg border p-4">
                  <p className="text-xs uppercase tracking-wide text-muted-foreground">{a.bucket} days</p>
                  <p className="mt-1 text-xl font-bold">{inr(a.value)}</p>
                  <p className="text-xs text-muted-foreground">{a.quantity} units</p>
                  <div className="mt-2 h-1.5 overflow-hidden rounded-full bg-muted">
                    <div className="h-full rounded-full bg-primary" style={{ width: `${(a.value / maxVal) * 100}%` }} />
                  </div>
                </div>
              ))}
            </div>
          )}
        </CardContent>
      </Card>

      <div>
        <h2 className="mb-2 text-sm font-semibold">Near Expiry (≤ 30 days)</h2>
        <DataTable
          columns={columns}
          data={query.data?.nearExpiry ?? []}
          loading={query.isLoading}
          error={query.isError ? "Failed to load." : null}
          onRetry={() => query.refetch()}
          emptyMessage="No batches expiring within 30 days."
        />
      </div>
    </>
  );
}
