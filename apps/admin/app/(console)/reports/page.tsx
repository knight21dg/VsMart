"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Download, FileSpreadsheet, FileText, Loader2 } from "lucide-react";
import { toast } from "sonner";
import { api, API_BASE } from "@/lib/api/client";
import { getAccessToken } from "@/lib/auth/session";
import { PageHeader } from "@/components/page-header";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { LoadingState, ErrorState } from "@/components/states";
import { cn } from "@/lib/utils";

interface ReportData {
  title: string;
  columns: string[];
  rows: (string | number)[][];
}

const REPORTS = [
  { key: "sales", label: "Sales" },
  { key: "orders", label: "Orders" },
  { key: "credit", label: "Credit" },
  { key: "collections", label: "Collections" },
  { key: "inventory", label: "Inventory" },
  { key: "agents", label: "Agents" },
];

async function downloadReport(type: string, fmt: "csv" | "excel" | "pdf") {
  const token = getAccessToken();
  const res = await fetch(`${API_BASE}/reports/export?type=${type}&fmt=${fmt}`, {
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
  if (!res.ok) {
    toast.error(`Export failed (${res.status}).`);
    return;
  }
  const blob = await res.blob();
  const ext = fmt === "excel" ? "xlsx" : fmt;
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `vsmart-${type}-report.${ext}`;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

export default function ReportsPage() {
  const [active, setActive] = React.useState("sales");
  const [exporting, setExporting] = React.useState<string | null>(null);

  const query = useQuery({
    queryKey: ["reports", active],
    queryFn: () => api.get<ReportData>(`/reports/${active}`),
  });
  const r = query.data;

  async function doExport(fmt: "csv" | "excel" | "pdf") {
    setExporting(fmt);
    try {
      await downloadReport(active, fmt);
    } finally {
      setExporting(null);
    }
  }

  return (
    <>
      <PageHeader
        title="Reports & Analytics"
        description="Operational reports with CSV, Excel and PDF export."
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

      <Card className="p-0">
        {query.isLoading ? (
          <LoadingState />
        ) : query.isError || !r ? (
          <ErrorState message="Couldn't load this report." onRetry={() => query.refetch()} />
        ) : (
          <div className="p-1">
            <p className="px-3 py-2 text-sm font-medium">{r.title}</p>
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  {r.columns.map((c) => (
                    <TableHead key={c}>{c}</TableHead>
                  ))}
                </TableRow>
              </TableHeader>
              <TableBody>
                {r.rows.length === 0 ? (
                  <TableRow className="hover:bg-transparent">
                    <TableCell colSpan={r.columns.length} className="py-10 text-center text-sm text-muted-foreground">
                      No data for this report.
                    </TableCell>
                  </TableRow>
                ) : (
                  r.rows.map((row, i) => (
                    <TableRow key={i}>
                      {row.map((cell, j) => (
                        <TableCell key={j} className={cn(typeof cell === "number" && "tabular-nums")}>
                          {String(cell)}
                        </TableCell>
                      ))}
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        )}
      </Card>
    </>
  );
}
