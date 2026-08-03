"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { api } from "@/lib/api/client";
import { PageHeader } from "@/components/page-header";
import { StatCard } from "@/components/stat-card";
import { DataTable } from "@/components/data-table";
import { Badge } from "@/components/ui/badge";
import { StatusBadge } from "@/components/status-badge";
import { StoreZone, StoreZoneFilter } from "@/components/store-zone";
import { fmtDate, inr, titleize } from "@/lib/utils";

interface PosTxn {
  id: string; code: string; type: string; storeName: string | null; terminal: string;
  subtotal: number; tax: number; discount: number; total: number; paymentStatus: string;
  creditUsed: number; isVoided: boolean; createdAt: string;
}
interface Resp { transactions: PosTxn[]; summary: { count: number; salesCount: number; salesTotal: number } }

export default function PosOversightPage() {
  const [store, setStore] = React.useState("");
  const [zone, setZone] = React.useState("");
  const query = useQuery({ queryKey: ["pos", "txns", store], queryFn: () => api.get<Resp>("/admin/pos/transactions", { store: store || undefined }) });
  const s = query.data?.summary;

  const columns: ColumnDef<PosTxn, unknown>[] = [
    { accessorKey: "code", header: "Receipt", cell: ({ row }) => <span className="font-mono text-xs">{row.original.code}</span> },
    { id: "loc", header: "Store / Register", cell: ({ row }) => <span className="flex flex-col"><StoreZone store={row.original.storeName} zone={row.original.terminal ? `Register ${row.original.terminal}` : null} /></span> },
    { accessorKey: "type", header: "Type", cell: ({ row }) => <Badge variant={row.original.isVoided ? "destructive" : row.original.type === "sale" ? "success" : "warning"}>{row.original.isVoided ? "Voided" : titleize(row.original.type)}</Badge> },
    { accessorKey: "subtotal", header: "Subtotal", cell: ({ row }) => inr(row.original.subtotal) },
    { accessorKey: "tax", header: "Tax", cell: ({ row }) => inr(row.original.tax) },
    { accessorKey: "total", header: "Total", cell: ({ row }) => <span className="font-medium">{inr(row.original.total)}</span> },
    { accessorKey: "creditUsed", header: "Credit", cell: ({ row }) => (row.original.creditUsed ? inr(row.original.creditUsed) : "—") },
    { accessorKey: "paymentStatus", header: "Payment", cell: ({ row }) => <StatusBadge status={row.original.paymentStatus} /> },
    { accessorKey: "createdAt", header: "Time", cell: ({ row }) => <span className="text-xs text-muted-foreground">{fmtDate(row.original.createdAt, true)}</span> },
  ];

  return (
    <>
      <PageHeader title="POS" description="Walk-in store billing oversight across registers." />
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard label="Transactions" value={s?.count ?? 0} loading={query.isLoading} />
        <StatCard label="Sales" value={s?.salesCount ?? 0} accent="teal" loading={query.isLoading} />
        <StatCard label="Sales Value" value={inr(s?.salesTotal)} accent="green" loading={query.isLoading} />
        <StatCard label="Voids / Returns" value={(s?.count ?? 0) - (s?.salesCount ?? 0)} accent="gold" loading={query.isLoading} />
      </div>
      <div className="flex justify-end">
        <StoreZoneFilter store={store} zone={zone} onStore={setStore} onZone={setZone} />
      </div>
      <DataTable
        columns={columns}
        data={query.data?.transactions ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load POS transactions." : null}
        onRetry={() => query.refetch()}
        emptyMessage="No POS transactions yet."
      />
    </>
  );
}
