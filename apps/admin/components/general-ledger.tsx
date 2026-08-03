"use client";

import * as React from "react";
import { keepPreviousData, useQuery, useQueryClient } from "@tanstack/react-query";
import { type ColumnDef } from "@tanstack/react-table";
import { AlertTriangle, Check, Loader2, Plus, Trash2, Undo2 } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError, type PageMeta } from "@/lib/types";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { DataTable } from "@/components/data-table";
import { StatusBadge } from "@/components/status-badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from "@/components/ui/select";
import { inr, titleize } from "@/lib/utils";

interface Account {
  id: string; code: string; name: string; type: string;
  isControl: boolean; isActive: boolean;
}
interface TrialRow {
  accountId: string; code: string; name: string; type: string;
  debit: number | string; credit: number | string;
}
interface TrialBalance {
  asOf: string; rows: TrialRow[];
  totalDebit: number | string; totalCredit: number | string; balanced: boolean;
}
interface PnlRow { code: string; name: string; type: string; amount: number | string }
interface Pnl {
  income: PnlRow[]; totalIncome: number | string;
  expenses: PnlRow[]; totalExpenses: number | string;
  netProfit: number | string;
}
interface BalanceSheet {
  asOf: string;
  assets: PnlRow[]; totalAssets: number | string;
  liabilities: PnlRow[]; totalLiabilities: number | string;
  equity: PnlRow[]; retainedEarnings: number | string;
  totalEquity: number | string; balanced: boolean;
}
interface JournalLine {
  accountCode: string; accountName: string;
  debit: number | string; credit: number | string; narration: string;
}
interface JournalEntry {
  id: string; entryDate: string; narration: string; reference: string;
  status: string; sourceModule: string; total: number | string;
  createdByName: string | null; lines: JournalLine[];
}

const n = (v: number | string | null | undefined) => Number(v ?? 0);
const today = () => new Date().toISOString().slice(0, 10);
const monthStart = () => {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth(), 1).toISOString().slice(0, 10);
};

/** Trial balance — the integrity check. If this doesn't balance, something
 *  bypassed the posting service and every other report is suspect. */
export function TrialBalanceTab() {
  const [asOf, setAsOf] = React.useState(today());
  const query = useQuery({
    queryKey: ["gl", "trial-balance", asOf],
    queryFn: () => api.get<TrialBalance>("/admin/accounting/trial-balance", { asOf }),
  });
  const tb = query.data;

  const columns: ColumnDef<TrialRow, unknown>[] = [
    { accessorKey: "code", header: "Code", cell: ({ row }) => <span className="font-mono text-xs">{row.original.code}</span> },
    { accessorKey: "name", header: "Account" },
    { accessorKey: "type", header: "Type", cell: ({ row }) => <span className="text-xs text-muted-foreground">{titleize(row.original.type)}</span> },
    {
      accessorKey: "debit", header: "Debit",
      cell: ({ row }) => <span className="tabular-nums">{n(row.original.debit) ? inr(n(row.original.debit)) : "—"}</span>,
    },
    {
      accessorKey: "credit", header: "Credit",
      cell: ({ row }) => <span className="tabular-nums">{n(row.original.credit) ? inr(n(row.original.credit)) : "—"}</span>,
    },
  ];

  return (
    <>
      <div className="mb-3 flex flex-wrap items-end gap-3">
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">As of</Label>
          <Input type="date" value={asOf} onChange={(e) => setAsOf(e.target.value)} className="w-[160px]" />
        </div>
        {tb && (
          <Card className={`flex items-center gap-2 px-3 py-2 text-sm ${
            tb.balanced ? "" : "border-destructive/40 bg-destructive/5"}`}>
            {tb.balanced ? (
              <><Check className="size-4 text-[var(--color-success)]" />
                <span>Balanced — debits equal credits.</span></>
            ) : (
              <><AlertTriangle className="size-4 text-destructive" />
                <span className="text-destructive">
                  Out of balance by {inr(Math.abs(n(tb.totalDebit) - n(tb.totalCredit)))}.
                  Something bypassed the posting service.
                </span></>
            )}
          </Card>
        )}
      </div>

      <DataTable
        columns={columns}
        data={tb?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load the trial balance." : null}
        onRetry={() => query.refetch()}
        emptyMessage="Nothing posted yet."
      />

      {tb && (
        <div className="mt-3 flex justify-end gap-8 border-t pt-3 text-sm font-medium">
          <span>Total debits <span className="tabular-nums">{inr(n(tb.totalDebit))}</span></span>
          <span>Total credits <span className="tabular-nums">{inr(n(tb.totalCredit))}</span></span>
        </div>
      )}
    </>
  );
}

/** Profit & loss, from the journal rather than an aggregate over orders. */
export function ProfitLossTab() {
  const [from, setFrom] = React.useState(monthStart());
  const [to, setTo] = React.useState(today());
  const query = useQuery({
    queryKey: ["gl", "pnl", from, to],
    queryFn: () => api.get<Pnl>("/admin/accounting/pnl", { from, to }),
  });
  const p = query.data;
  const profit = n(p?.netProfit);

  return (
    <>
      <div className="mb-3 flex flex-wrap items-end gap-3">
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">From</Label>
          <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} className="w-[160px]" />
        </div>
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">To</Label>
          <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} className="w-[160px]" />
        </div>
      </div>

      {query.isLoading && <div className="grid place-items-center py-10"><Loader2 className="size-5 animate-spin text-muted-foreground" /></div>}

      {p && (
        <div className="space-y-4">
          <StatementBlock title="Income" rows={p.income} total={n(p.totalIncome)} />
          <StatementBlock title="Expenses" rows={p.expenses} total={n(p.totalExpenses)} />
          <Card className="flex items-center justify-between p-4">
            <span className="font-medium">{profit >= 0 ? "Net profit" : "Net loss"}</span>
            <span className={`text-xl font-semibold tabular-nums ${
              profit >= 0 ? "text-[var(--color-success)]" : "text-destructive"}`}>
              {inr(Math.abs(profit))}
            </span>
          </Card>
        </div>
      )}
    </>
  );
}

export function BalanceSheetTab() {
  const [asOf, setAsOf] = React.useState(today());
  const query = useQuery({
    queryKey: ["gl", "balance-sheet", asOf],
    queryFn: () => api.get<BalanceSheet>("/admin/accounting/balance-sheet", { asOf }),
  });
  const b = query.data;

  return (
    <>
      <div className="mb-3 flex flex-wrap items-end gap-3">
        <div className="space-y-1">
          <Label className="text-xs text-muted-foreground">As of</Label>
          <Input type="date" value={asOf} onChange={(e) => setAsOf(e.target.value)} className="w-[160px]" />
        </div>
        {b && !b.balanced && (
          <Card className="flex items-center gap-2 border-destructive/40 bg-destructive/5 px-3 py-2 text-sm text-destructive">
            <AlertTriangle className="size-4" /> Assets don&apos;t equal liabilities plus equity.
          </Card>
        )}
      </div>

      {query.isLoading && <div className="grid place-items-center py-10"><Loader2 className="size-5 animate-spin text-muted-foreground" /></div>}

      {b && (
        <div className="grid gap-4 lg:grid-cols-2">
          <StatementBlock title="Assets" rows={b.assets} total={n(b.totalAssets)} />
          <div className="space-y-4">
            <StatementBlock title="Liabilities" rows={b.liabilities} total={n(b.totalLiabilities)} />
            <StatementBlock
              title="Equity"
              rows={[
                ...b.equity,
                { code: "—", name: "Retained earnings", type: "equity",
                  amount: b.retainedEarnings },
              ]}
              total={n(b.totalEquity)}
            />
          </div>
        </div>
      )}
    </>
  );
}

function StatementBlock({ title, rows, total }: {
  title: string; rows: PnlRow[]; total: number;
}) {
  return (
    <Card className="overflow-hidden p-0">
      <div className="border-b bg-muted/40 px-3 py-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
        {title}
      </div>
      {rows.length === 0 ? (
        <p className="px-3 py-4 text-sm text-muted-foreground">Nothing in this section.</p>
      ) : (
        <div className="divide-y">
          {rows.map((r) => (
            <div key={`${r.code}-${r.name}`} className="flex items-center justify-between px-3 py-2 text-sm">
              <span>
                <span className="font-mono text-xs text-muted-foreground">{r.code}</span>{" "}
                {r.name}
              </span>
              <span className="tabular-nums">{inr(n(r.amount))}</span>
            </div>
          ))}
        </div>
      )}
      <div className="flex items-center justify-between border-t bg-muted/20 px-3 py-2 text-sm font-medium">
        <span>Total {title.toLowerCase()}</span>
        <span className="tabular-nums">{inr(total)}</span>
      </div>
    </Card>
  );
}

/** The journal — every posting, with its lines, newest first. */
export function JournalTab() {
  const qc = useQueryClient();
  const [page, setPage] = React.useState(1);
  const [source, setSource] = React.useState("");
  const [openId, setOpenId] = React.useState<string | null>(null);
  const [posting, setPosting] = React.useState(false);

  const query = useQuery({
    queryKey: ["gl", "journal", source, page],
    queryFn: () => api.getPaged<JournalEntry>("/admin/accounting/journal", {
      source: source || undefined, page,
    }),
    placeholderData: keepPreviousData,
  });

  const columns: ColumnDef<JournalEntry, unknown>[] = [
    {
      accessorKey: "entryDate", header: "Date",
      cell: ({ row }) => (
        <span className="whitespace-nowrap text-xs">
          {new Date(row.original.entryDate).toLocaleDateString("en-IN", {
            day: "2-digit", month: "short", year: "numeric",
          })}
        </span>
      ),
    },
    { accessorKey: "narration", header: "Narration" },
    {
      accessorKey: "sourceModule", header: "Source",
      cell: ({ row }) => (
        <span className="text-xs text-muted-foreground">
          {titleize(row.original.sourceModule || "manual")}
        </span>
      ),
    },
    {
      accessorKey: "total", header: "Amount",
      cell: ({ row }) => <span className="tabular-nums font-medium">{inr(n(row.original.total))}</span>,
    },
    { accessorKey: "status", header: "Status", cell: ({ row }) => <StatusBadge status={row.original.status} /> },
  ];

  return (
    <>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <Select value={source || "__all__"} onValueChange={(v) => { setSource(v === "__all__" ? "" : v); setPage(1); }}>
          <SelectTrigger className="w-[200px]"><SelectValue placeholder="Source" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="__all__">All sources</SelectItem>
            {["manual", "payment", "cash_deposit", "purchase_invoice", "vendor_payment"].map((s) => (
              <SelectItem key={s} value={s}>{titleize(s)}</SelectItem>
            ))}
          </SelectContent>
        </Select>
        <Button className="ml-auto" onClick={() => setPosting(true)}>
          <Plus className="size-4" /> New entry
        </Button>
      </div>

      <DataTable
        columns={columns}
        data={query.data?.rows ?? []}
        loading={query.isLoading}
        error={query.isError ? "Failed to load the journal." : null}
        onRetry={() => query.refetch()}
        emptyMessage="Nothing posted yet."
        pageMeta={query.data?.meta as PageMeta | undefined}
        page={page}
        onPageChange={setPage}
        onRowClick={(row) => setOpenId(row.id)}
      />

      {openId && (
        <EntryDialog
          entry={(query.data?.rows ?? []).find((e) => e.id === openId)!}
          onClose={() => setOpenId(null)}
          onChanged={() => { qc.invalidateQueries({ queryKey: ["gl"] }); setOpenId(null); }}
        />
      )}
      {posting && (
        <PostEntryDialog
          onClose={() => setPosting(false)}
          onPosted={() => { qc.invalidateQueries({ queryKey: ["gl"] }); setPosting(false); }}
        />
      )}
    </>
  );
}

function EntryDialog({ entry, onClose, onChanged }: {
  entry: JournalEntry; onClose: () => void; onChanged: () => void;
}) {
  const [busy, setBusy] = React.useState(false);
  const [confirming, setConfirming] = React.useState(false);
  const entryTotal = entry.lines.reduce((sum, l) => sum + n(l.debit), 0);

  async function reverse() {
    setBusy(true);
    try {
      await api.post(`/admin/accounting/journal/${entry.id}/reverse`, {
        reason: `Reversal of JE${entry.id}`,
      });
      toast.success("Reversing entry posted.");
      setConfirming(false);
      onChanged();
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Could not reverse.");
    } finally { setBusy(false); }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-2xl overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            JE{entry.id} <StatusBadge status={entry.status} />
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-3">
          <p className="text-sm">{entry.narration}</p>
          <p className="text-xs text-muted-foreground">
            {new Date(entry.entryDate).toLocaleDateString("en-IN")}
            {entry.reference ? ` · ${entry.reference}` : ""}
            {entry.createdByName ? ` · ${entry.createdByName}` : ""}
            {entry.sourceModule ? ` · ${titleize(entry.sourceModule)}` : ""}
          </p>

          <div className="overflow-hidden rounded-md border">
            <div className="grid grid-cols-[1fr_auto_auto] gap-2 border-b bg-muted/40 px-3 py-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
              <span>Account</span><span className="text-right">Debit</span><span className="text-right">Credit</span>
            </div>
            <div className="divide-y">
              {entry.lines.map((l, i) => (
                <div key={i} className="grid grid-cols-[1fr_auto_auto] gap-2 px-3 py-2 text-sm">
                  <span>
                    <span className="font-mono text-xs text-muted-foreground">{l.accountCode}</span>{" "}
                    {l.accountName}
                    {l.narration && <span className="block text-xs text-muted-foreground">{l.narration}</span>}
                  </span>
                  <span className="w-24 text-right tabular-nums">{n(l.debit) ? inr(n(l.debit)) : ""}</span>
                  <span className="w-24 text-right tabular-nums">{n(l.credit) ? inr(n(l.credit)) : ""}</span>
                </div>
              ))}
            </div>
          </div>
          <p className="text-xs text-muted-foreground">
            Posted entries are never edited or deleted — a correction is a
            reversing entry, so both the mistake and the fix stay on the record.
          </p>
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onClose} disabled={busy}>Close</Button>
          {entry.status === "posted" && (
            <Button variant="destructive" onClick={() => setConfirming(true)} disabled={busy}>
              {busy ? <Loader2 className="size-4 animate-spin" /> : <Undo2 className="size-4" />}
              Reverse
            </Button>
          )}
        </DialogFooter>
      </DialogContent>
      <ConfirmDialog
        open={confirming}
        onOpenChange={setConfirming}
        title={`Post a reversing entry for JE${entry.id}?`}
        description={
          `This posts a new, permanent journal entry that mirrors JE${entry.id} — ${inr(entryTotal)} across ` +
          `${entry.lines.length} line${entry.lines.length === 1 ? "" : "s"}, with every debit and credit swapped. ` +
          `JE${entry.id} itself stays on the books. The reversal is a posted entry too, so it can only be undone by ` +
          `reversing it in turn. It will show in the trial balance and P&L for today.`
        }
        confirmLabel="Post reversing entry"
        destructive
        loading={busy}
        onConfirm={reverse}
      />
    </Dialog>
  );
}

interface DraftLine { accountCode: string; debit: string; credit: string }

function PostEntryDialog({ onClose, onPosted }: {
  onClose: () => void; onPosted: () => void;
}) {
  const [entryDate, setEntryDate] = React.useState(today());
  const [narration, setNarration] = React.useState("");
  const [reference, setReference] = React.useState("");
  const [lines, setLines] = React.useState<DraftLine[]>([
    { accountCode: "", debit: "", credit: "" },
    { accountCode: "", debit: "", credit: "" },
  ]);
  const [busy, setBusy] = React.useState(false);

  const accounts = useQuery({
    queryKey: ["gl", "accounts"],
    queryFn: () => api.get<Account[]>("/admin/accounting/accounts"),
  });

  const totalDebit = lines.reduce((s, l) => s + Number(l.debit || 0), 0);
  const totalCredit = lines.reduce((s, l) => s + Number(l.credit || 0), 0);
  const balanced = totalDebit > 0 && totalDebit === totalCredit;

  function update(i: number, patch: Partial<DraftLine>) {
    setLines((prev) => prev.map((l, idx) => (idx === i ? { ...l, ...patch } : l)));
  }

  async function submit() {
    setBusy(true);
    try {
      await api.post("/admin/accounting/journal/post", {
        entryDate, narration, reference,
        lines: lines
          .filter((l) => l.accountCode && (Number(l.debit) || Number(l.credit)))
          .map((l) => ({
            accountCode: l.accountCode,
            debit: Number(l.debit) || 0,
            credit: Number(l.credit) || 0,
          })),
      });
      toast.success("Entry posted.");
      onPosted();
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Could not post the entry.");
    } finally { setBusy(false); }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] max-w-3xl overflow-y-auto">
        <DialogHeader><DialogTitle>New journal entry</DialogTitle></DialogHeader>

        <div className="space-y-3">
          <div className="grid grid-cols-3 gap-3">
            <div className="space-y-1.5">
              <Label className="text-xs text-muted-foreground">Date</Label>
              <Input type="date" value={entryDate} onChange={(e) => setEntryDate(e.target.value)} />
            </div>
            <div className="col-span-2 space-y-1.5">
              <Label className="text-xs text-muted-foreground">Narration</Label>
              <Input value={narration} onChange={(e) => setNarration(e.target.value)}
                     placeholder="What is this entry for?" />
            </div>
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs text-muted-foreground">Reference (optional)</Label>
            <Input value={reference} onChange={(e) => setReference(e.target.value)} />
          </div>

          <div className="space-y-2">
            {lines.map((line, i) => (
              <div key={i} className="grid grid-cols-[1fr_120px_120px_auto] items-end gap-2">
                <div className="space-y-1.5">
                  {i === 0 && <Label className="text-xs text-muted-foreground">Account</Label>}
                  <Select value={line.accountCode}
                          onValueChange={(v) => update(i, { accountCode: v })}>
                    <SelectTrigger><SelectValue placeholder="Choose" /></SelectTrigger>
                    <SelectContent>
                      {(accounts.data ?? []).map((a) => (
                        <SelectItem key={a.code} value={a.code}>
                          {a.code} · {a.name}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                </div>
                <div className="space-y-1.5">
                  {i === 0 && <Label className="text-xs text-muted-foreground">Debit</Label>}
                  <Input type="number" min={0} value={line.debit}
                         onChange={(e) => update(i, { debit: e.target.value, credit: "" })} />
                </div>
                <div className="space-y-1.5">
                  {i === 0 && <Label className="text-xs text-muted-foreground">Credit</Label>}
                  <Input type="number" min={0} value={line.credit}
                         onChange={(e) => update(i, { credit: e.target.value, debit: "" })} />
                </div>
                <Button variant="ghost" size="icon" disabled={lines.length <= 2}
                        onClick={() => setLines((p) => p.filter((_, idx) => idx !== i))}>
                  <Trash2 className="size-4" />
                </Button>
              </div>
            ))}
            <Button variant="outline" size="sm"
                    onClick={() => setLines((p) => [...p, { accountCode: "", debit: "", credit: "" }])}>
              <Plus className="size-4" /> Add line
            </Button>
          </div>

          <div className={`flex items-center justify-between rounded-md border p-3 text-sm ${
            balanced ? "" : "border-amber-500/40 bg-amber-500/5"}`}>
            <span className="text-muted-foreground">
              {balanced ? "Balanced." : "Debits and credits must match before this can post."}
            </span>
            <span className="tabular-nums">
              Dr {inr(totalDebit)} · Cr {inr(totalCredit)}
            </span>
          </div>
        </div>

        <DialogFooter className="gap-2">
          <Button variant="outline" onClick={onClose} disabled={busy}>Cancel</Button>
          <Button disabled={busy || !balanced || !narration.trim()} onClick={submit}>
            {busy && <Loader2 className="size-4 animate-spin" />} Post entry
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
