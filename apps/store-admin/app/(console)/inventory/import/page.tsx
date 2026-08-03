"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useMutation } from "@tanstack/react-query";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { AlertTriangle, ArrowLeft, CheckCircle2, Download, FileSpreadsheet, Loader2, Upload } from "lucide-react";
import { api } from "@/lib/api/hooks";
import { ApiError } from "@/lib/types";
import { PageHeader } from "@/components/page-header";
import { RequirePerm } from "@/components/permission-gate";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { parseCsvObjects, downloadCsv } from "@/lib/csv";

/**
 * Bulk catalog import.
 *
 * The flow is deliberately preview-then-commit: pick a file → see exactly what
 * will be created/updated and everything that's wrong → only then import. The
 * backend runs the SAME validation for both passes, so the preview can't lie,
 * and the commit is one transaction (a bad row can't leave half a catalog).
 */

interface RowVerdict {
  index: number;
  name: string;
  barcode: string;
  action: "create" | "update" | "error";
  errors: Record<string, string>;
  existingId: string | null;
}
interface ImportResult {
  committed: boolean;
  summary: { total: number; create: number; update: number; errors: number };
  rows: RowVerdict[];
}

const TEMPLATE_COLUMNS = [
  "name", "barcode", "category", "brand", "unit", "sku", "hsn",
  "price", "mrp", "openingStock", "reorderLevel",
];

export default function ImportPage() {
  return (
    <RequirePerm perm="inventory.manage">
      <Inner />
    </RequirePerm>
  );
}

function Inner() {
  const router = useRouter();
  const qc = useQueryClient();
  const [fileName, setFileName] = React.useState("");
  const [rows, setRows] = React.useState<Record<string, string>[]>([]);
  const [result, setResult] = React.useState<ImportResult | null>(null);
  // Which valid rows (by their `index` into `rows`) will actually be
  // committed — defaults to every valid row, but a variant nobody wants
  // stocked yet (or anything else worth reviewing later) can be unchecked
  // without having to fix or drop it from the sheet entirely.
  const [selected, setSelected] = React.useState<Set<number>>(new Set());
  const inputRef = React.useRef<HTMLInputElement | null>(null);

  const preview = useMutation({
    mutationFn: (parsed: Record<string, string>[]) =>
      api.post<ImportResult>("/store/inventory/import", { rows: parsed, commit: false }),
    onSuccess: (r) => {
      setResult(r);
      setSelected(new Set(r.rows.filter((row) => row.action !== "error").map((row) => row.index)));
    },
    onError: (e) => toast.error(e instanceof ApiError ? e.message : "Couldn't read that file."),
  });

  const commit = useMutation({
    mutationFn: () =>
      api.post<ImportResult>("/store/inventory/import", {
        rows: rows.filter((_, i) => selected.has(i)),
        commit: true,
      }),
    onSuccess: (r) => {
      setResult(r);
      if (r.committed) {
        qc.invalidateQueries({ queryKey: ["store", "inventory"] });
        toast.success(`Imported — ${r.summary.create} added, ${r.summary.update} updated`);
        router.push("/inventory");
      }
    },
    onError: (e) => toast.error(e instanceof ApiError ? e.message : "Import failed."),
  });

  async function pick(file: File) {
    setFileName(file.name);
    setResult(null);
    setSelected(new Set());
    const text = await file.text();
    const parsed = parseCsvObjects(text);
    if (parsed.length === 0) {
      toast.error("That file has no rows under its header.");
      setRows([]);
      return;
    }
    // parseCsvObjects lower-cases headers, so the two camelCase columns arrive
    // as `openingstock`/`reorderlevel`; re-expose them under the names the
    // backend reads.
    const normalised = parsed.map((r) => ({
      ...r,
      openingStock: r.openingstock ?? "",
      reorderLevel: r.reorderlevel ?? "",
    }));
    setRows(normalised);
    preview.mutate(normalised);
  }

  function toggle(index: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(index)) next.delete(index); else next.add(index);
      return next;
    });
  }

  const s = result?.summary;
  const validRows = result?.rows.filter((r) => r.action !== "error") ?? [];
  const allValidSelected = validRows.length > 0 && validRows.every((r) => selected.has(r.index));
  const toCommit = selected.size;

  return (
    <div className="space-y-5">
      <PageHeader
        title="Import products"
        description="Add or update your whole catalog from a spreadsheet — with opening stock."
        actions={
          <Button variant="outline" onClick={() => router.push("/inventory")}>
            <ArrowLeft className="size-4" /> Back
          </Button>
        }
      />

      <Card>
        <CardContent className="space-y-4 p-5">
          <div className="flex flex-wrap items-center gap-2">
            <Button
              variant="outline"
              onClick={() => downloadCsv("vsmart-product-template.csv", TEMPLATE_COLUMNS, [{
                name: "Tea Powder 250g", barcode: "8901234567890", category: "Groceries",
                brand: "Tata", unit: "250 g", sku: "", hsn: "0902",
                price: "120", mrp: "150", openingStock: "40", reorderLevel: "10",
              }])}
            >
              <Download className="size-4" /> Download template
            </Button>
            <input
              ref={inputRef}
              type="file"
              accept=".csv,text/csv"
              className="hidden"
              onChange={(e) => { const f = e.target.files?.[0]; if (f) void pick(f); e.target.value = ""; }}
            />
            <Button onClick={() => inputRef.current?.click()} disabled={preview.isPending}>
              {preview.isPending ? <Loader2 className="size-4 animate-spin" /> : <Upload className="size-4" />}
              Choose CSV
            </Button>
            {fileName && (
              <span className="inline-flex items-center gap-1.5 text-sm text-muted-foreground">
                <FileSpreadsheet className="size-4" /> {fileName} · {rows.length} rows
              </span>
            )}
          </div>

          <p className="text-xs text-muted-foreground">
            Required columns: <code className="font-mono">name</code>,{" "}
            <code className="font-mono">category</code>, <code className="font-mono">price</code>.
            Rows are matched on <strong>barcode</strong> — an existing code updates that
            product, a new one creates it, so re-importing a corrected sheet is safe.
            Leave barcode blank and we generate a scannable in-store code.
          </p>
        </CardContent>
      </Card>

      {result && (
        <>
          <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
            <Stat label="Rows" value={s!.total} />
            <Stat label="Will be added" value={s!.create} tone="success" />
            <Stat label="Will be updated" value={s!.update} tone="info" />
            <Stat label="Errors" value={s!.errors} tone={s!.errors ? "danger" : "muted"} />
          </div>

          {s!.errors > 0 && (
            <div className="flex items-start gap-2 rounded-lg border border-[var(--color-danger)]/30 bg-[var(--color-danger)]/5 p-3 text-sm">
              <AlertTriangle className="mt-0.5 size-4 shrink-0 text-[var(--color-danger)]" />
              <p>
                <strong>{s!.errors} row{s!.errors > 1 ? "s" : ""} need fixing.</strong>{" "}
                Those rows can&apos;t be imported and are unchecked below. Everything else is
                ready — uncheck any row you don&apos;t want to bring in yet, then press Import.
              </p>
            </div>
          )}
          {s!.errors === 0 && (
            <div className="flex items-start gap-2 rounded-lg border border-[var(--color-success)]/30 bg-[var(--color-success)]/5 p-3 text-sm">
              <CheckCircle2 className="mt-0.5 size-4 shrink-0 text-[var(--color-success)]" />
              <p>Every row is valid. Uncheck anything you don&apos;t want to import yet, then press Import.</p>
            </div>
          )}

          <div className="overflow-x-auto rounded-lg border">
            <table className="w-full text-sm">
              <thead className="bg-muted/50 text-left text-xs uppercase text-muted-foreground">
                <tr>
                  <th className="w-9 px-3 py-2">
                    <input
                      type="checkbox"
                      checked={allValidSelected}
                      onChange={(e) =>
                        setSelected(e.target.checked ? new Set(validRows.map((r) => r.index)) : new Set())
                      }
                      aria-label="Select all valid rows"
                    />
                  </th>
                  <th className="px-3 py-2 font-medium">Row</th>
                  <th className="px-3 py-2 font-medium">Product</th>
                  <th className="px-3 py-2 font-medium">Barcode</th>
                  <th className="px-3 py-2 font-medium">Action</th>
                  <th className="px-3 py-2 font-medium">Problem</th>
                </tr>
              </thead>
              <tbody>
                {result.rows.map((r) => {
                  const isError = r.action === "error";
                  return (
                    <tr key={r.index} className={`border-t ${isError ? "bg-[var(--color-danger)]/5" : ""}`}>
                      <td className="px-3 py-2">
                        <input
                          type="checkbox"
                          checked={!isError && selected.has(r.index)}
                          disabled={isError}
                          onChange={() => toggle(r.index)}
                          aria-label={`Include row ${r.index + 2}`}
                        />
                      </td>
                      {/* +2: the operator's row number in the sheet (1-based, past the header). */}
                      <td className="px-3 py-2 tabular-nums text-muted-foreground">{r.index + 2}</td>
                      <td className="px-3 py-2 font-medium">{r.name || <span className="text-muted-foreground">—</span>}</td>
                      <td className="px-3 py-2 font-mono text-xs text-muted-foreground">{r.barcode || "auto"}</td>
                      <td className="px-3 py-2">
                        <Badge variant={isError ? "destructive" : r.action === "update" ? "secondary" : "success"}>
                          {r.action === "create" ? "Add" : r.action === "update" ? "Update" : "Error"}
                        </Badge>
                      </td>
                      <td className="px-3 py-2 text-xs text-[var(--color-danger)]">
                        {Object.entries(r.errors).map(([k, v]) => <div key={k}><strong>{k}:</strong> {v}</div>)}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          <div className="flex items-center justify-between">
            <p className="text-xs text-muted-foreground">
              {toCommit} of {validRows.length} valid row{validRows.length === 1 ? "" : "s"} selected
            </p>
            <div className="flex gap-2">
              <Button variant="outline" onClick={() => { setResult(null); setRows([]); setFileName(""); setSelected(new Set()); }}>
                Clear
              </Button>
              <Button disabled={toCommit === 0 || commit.isPending} onClick={() => commit.mutate()}>
                {commit.isPending && <Loader2 className="size-4 animate-spin" />}
                Import {toCommit} product{toCommit === 1 ? "" : "s"}
              </Button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}

function Stat({ label, value, tone = "muted" }: { label: string; value: number; tone?: "success" | "info" | "danger" | "muted" }) {
  const color =
    tone === "success" ? "text-[var(--color-success)]" :
    tone === "danger" ? "text-[var(--color-danger)]" :
    tone === "info" ? "text-primary" : "";
  return (
    <Card>
      <CardContent className="p-4">
        <p className="text-xs text-muted-foreground">{label}</p>
        <p className={`text-2xl font-semibold tabular-nums ${color}`}>{value}</p>
      </CardContent>
    </Card>
  );
}
