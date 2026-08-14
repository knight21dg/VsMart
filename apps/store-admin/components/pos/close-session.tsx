"use client";

import * as React from "react";
import { Loader2 } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn, inr } from "@/lib/utils";

/** Indian currency, largest first — the order a cashier actually counts in. */
const DENOMS = [500, 200, 100, 50, 20, 10, 5, 2, 1];

/** The day closing `/store/pos/session/close` answers with. */
export interface DayClosing {
  expectedCash: number;
  countedCash: number;
  variance: number;
  totalSales: number;
  cashSales: number;
  upiSales: number;
  cardSales: number;
  creditSales: number;
  transactionCount: number;
}

/**
 * Close the till with a real denomination count.
 *
 * It used to be a single "Counted cash" box — the cashier had to add the drawer
 * up in their head (or on paper) and type one number, which is exactly where
 * counting errors hide. Now they key how many of each note/coin they hold and the
 * total is computed; the breakdown rides along in `notes` so a variance can be
 * investigated afterwards.
 *
 * The backend takes the TOTAL (`countedCash`) — there is no denomination model —
 * so this is a counting aid that produces the number the server already expects.
 *
 * It lives outside the POS page so it can be exercised on its own: mounting the
 * till would drag in the offline database and the scanner audio with it.
 */
export function CloseSession({ onClosed }: { onClosed: () => void }) {
  const [open, setOpen] = React.useState(false);
  const [count, setCount] = React.useState<Record<number, string>>({});
  const [notes, setNotes] = React.useState("");
  // The server's day-closing summary, held so the cashier can actually read it.
  const [closing, setClosing] = React.useState<DayClosing | null>(null);

  const total = DENOMS.reduce((s, d) => s + d * (Number(count[d]) || 0), 0);
  const breakdown = DENOMS
    .filter((d) => Number(count[d]) > 0)
    .map((d) => `${d}x${Number(count[d])}`)
    .join(" ");

  /*
   * `/store/pos/session/close` answers with the whole day closing — expected vs
   * counted cash, the variance, the tender split and the transaction count. All
   * of it used to be dropped on the floor: `onDone` closed the dialog and
   * invalidated the session, so the till screen reset to "Open till" and the
   * cashier saw nothing but a "Till closed" toast. The panel below the counter
   * even promised "The variance against expected cash is shown after closing",
   * which it never was.
   *
   * That is the one number the counting exercise exists to produce — a short
   * drawer has to be visible at the till, while the cashier is still standing
   * there, not discovered later in a report. So the result is kept and rendered,
   * and the session is only invalidated once it has been acknowledged (doing it
   * straight away would unmount this dialog along with the summary).
   */
  const close = useApiMutation<void, DayClosing>(
    () => api.post("/store/pos/session/close", {
      countedCash: total,
      notes: [notes.trim(), breakdown && `[drawer ${breakdown}]`].filter(Boolean).join(" "),
    }),
    { successMessage: "Till closed", onDone: (r) => setClosing(r) },
  );

  function acknowledge() {
    setClosing(null);
    setCount({});
    setNotes("");
    setOpen(false);
    onClosed();
  }

  if (closing) return <ClosingSummary closing={closing} onDone={acknowledge} />;
  if (!open) return <Button variant="outline" onClick={() => setOpen(true)}>Close till</Button>;
  return (
    // Not dismissible mid-close: an Escape or backdrop click while the POST is in
    // flight would drop the summary this dialog exists to hand back.
    <Dialog open onOpenChange={(o) => { if (!o && !close.isPending) setOpen(false); }}>
      <DialogContent className="max-w-sm">
        <DialogHeader><DialogTitle>Count the drawer</DialogTitle></DialogHeader>
        <div className="space-y-2 py-1">
          <div className="grid grid-cols-3 gap-2">
            {DENOMS.map((d) => (
              <div key={d} className="space-y-1">
                <Label className="text-xs" htmlFor={`denom-${d}`}>{inr(d)}</Label>
                <Input
                  id={`denom-${d}`}
                  className="h-8" inputMode="numeric" placeholder="0"
                  value={count[d] ?? ""}
                  onChange={(e) => setCount((p) => ({ ...p, [d]: e.target.value.replace(/\D/g, "") }))}
                />
              </div>
            ))}
          </div>
          <div className="space-y-1.5 pt-1">
            <Label className="text-xs" htmlFor="close-notes">Notes (optional)</Label>
            <Input id="close-notes" className="h-8" value={notes} onChange={(e) => setNotes(e.target.value)}
                   placeholder="e.g. ₹200 paid out for delivery" />
          </div>
          <div className="flex justify-between border-t pt-2 font-semibold">
            <span>Counted</span><span className="tabular-nums">{inr(total, { decimals: true })}</span>
          </div>
          <p className="text-xs text-muted-foreground">
            The variance against expected cash is shown after closing.
          </p>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)} disabled={close.isPending}>Cancel</Button>
          <Button onClick={() => close.mutate()} disabled={close.isPending || total <= 0}>
            {close.isPending && <Loader2 className="size-4 animate-spin" />} Close till
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/**
 * What the drawer actually came to, shown before the till screen resets.
 *
 * The variance leads because it is the only line that needs an action: over or
 * short is a cash discrepancy someone has to explain while the shift is still
 * fresh. It is stated as "short"/"over" rather than a signed number so it can't
 * be misread — a bare "-250" at a till is ambiguous about who owes whom.
 */
function ClosingSummary({ closing, onDone }: { closing: DayClosing; onDone: () => void }) {
  const v = closing.variance;
  const short = v < 0;
  const balanced = Math.abs(v) < 0.005;
  return (
    <Dialog open onOpenChange={(o) => !o && onDone()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>Till closed</DialogTitle>
          <DialogDescription>
            {closing.transactionCount} transaction{closing.transactionCount === 1 ? "" : "s"} ·{" "}
            {inr(closing.totalSales, { decimals: true })} in sales
          </DialogDescription>
        </DialogHeader>
        <div className="space-y-3 py-1 text-sm">
          <div
            className={cn(
              "rounded-lg border p-3 text-center",
              balanced
                ? "border-emerald-200 bg-emerald-50 text-emerald-900"
                : "border-amber-300 bg-amber-50 text-amber-900",
            )}
          >
            <div className="text-xs uppercase tracking-wide opacity-70">Cash variance</div>
            <div className="text-xl font-semibold tabular-nums">
              {balanced ? "Balanced" : `${inr(Math.abs(v), { decimals: true })} ${short ? "short" : "over"}`}
            </div>
          </div>
          <div className="space-y-1.5">
            <div className="flex justify-between font-medium">
              <span>Expected cash</span>
              <span className="tabular-nums">{inr(closing.expectedCash, { decimals: true })}</span>
            </div>
            <div className="flex justify-between font-medium">
              <span>Counted cash</span>
              <span className="tabular-nums">{inr(closing.countedCash, { decimals: true })}</span>
            </div>
            <div className="space-y-1.5 border-t pt-1.5 text-muted-foreground">
              <SummaryRow label="Cash sales" value={closing.cashSales} />
              <SummaryRow label="UPI sales" value={closing.upiSales} />
              <SummaryRow label="Card sales" value={closing.cardSales} />
              <SummaryRow label="Credit sales" value={closing.creditSales} />
            </div>
          </div>
        </div>
        <DialogFooter>
          <Button className="w-full" onClick={onDone}>Done</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function SummaryRow({ label, value }: { label: string; value: number }) {
  return (
    <div className="flex justify-between">
      <span>{label}</span>
      <span className="tabular-nums">{inr(value, { decimals: true })}</span>
    </div>
  );
}
