"use client";

import * as React from "react";
import { createPortal } from "react-dom";

/**
 * 80mm thermal receipt, printed straight from the browser.
 *
 * Why not the PDF endpoint: printing a sale used to mean leaving the till,
 * opening /pos/sales, downloading a PDF and printing that — several clicks and a
 * context switch per customer. A thermal printer is just a printer, so rendering
 * the receipt as HTML and calling window.print() makes it one keypress.
 *
 * The component renders nothing on screen. `@media print` (see globals.css)
 * hides the whole app and reveals only this node, sized to an 80mm roll.
 *
 * PORTAL — not optional. The print stylesheet hides `body > *` and re-shows only
 * `#pos-print-receipt`. Rendered inline (deep inside the POS page) the node sits
 * under a hidden ancestor and inherits `display:none`, so every print — F10 and
 * the Print button alike — came out as a blank roll. It must be a DIRECT child of
 * <body>, which is what createPortal gives us.
 */

export interface PrintLine { name: string; qty: number; rate: number; amount: number }
export interface PrintReceipt {
  storeName: string;
  storeAddress?: string;
  gstin?: string;
  phone?: string;
  code: string;
  datetime: string;
  cashier?: string;
  customer?: string | null;
  lines: PrintLine[];
  subtotal: number;
  discount: number;
  cgst: number;
  sgst: number;
  total: number;
  payments: { method: string; amount: number }[];
  changeDue: number;
  footer?: string;
}

const money = (v: number) => (Number.isFinite(v) ? v.toFixed(2) : "0.00");

/** Hydration-safe "are we on the client yet?" — `document` only exists after
 * mount, and a portal must not run during SSR. useSyncExternalStore rather than
 * setState-in-an-effect (which the react-hooks compiler rules reject). */
const neverChanges = () => () => {};
function useIsMounted() {
  return React.useSyncExternalStore(neverChanges, () => true, () => false);
}

export function PosPrintReceipt({ receipt }: { receipt: PrintReceipt | null }) {
  const mounted = useIsMounted();
  if (!mounted || !receipt) return null;
  const r = receipt;
  return createPortal(
    <div id="pos-print-receipt" aria-hidden="true">
      <div className="pr-center pr-bold pr-lg">{r.storeName}</div>
      {r.storeAddress ? <div className="pr-center pr-sm">{r.storeAddress}</div> : null}
      {(r.gstin || r.phone) && (
        <div className="pr-center pr-sm">
          {r.gstin ? `GSTIN: ${r.gstin}` : ""}{r.gstin && r.phone ? " | " : ""}{r.phone ?? ""}
        </div>
      )}
      <div className="pr-rule" />

      <div className="pr-sm">Receipt: <span className="pr-bold">{r.code}</span></div>
      <div className="pr-sm">{r.datetime}</div>
      {r.cashier ? <div className="pr-sm">Cashier: {r.cashier}</div> : null}
      {r.customer ? <div className="pr-sm">Customer: {r.customer}</div> : null}
      <div className="pr-rule" />

      <div className="pr-row pr-bold pr-sm"><span>Item</span><span>Amount</span></div>
      {r.lines.map((l, i) => (
        <div key={i}>
          <div className="pr-sm">{l.name}</div>
          <div className="pr-row pr-sm">
            <span>&nbsp;&nbsp;{l.qty} x {money(l.rate)}</span>
            <span>{money(l.amount)}</span>
          </div>
        </div>
      ))}
      <div className="pr-rule" />

      {/* Amounts are PRE-tax per line; GST is broken out once here, so
          Subtotal + CGST + SGST reconciles to Total. */}
      <div className="pr-row pr-sm"><span>Subtotal</span><span>{money(r.subtotal)}</span></div>
      {r.discount > 0 && (
        <div className="pr-row pr-sm"><span>Discount</span><span>-{money(r.discount)}</span></div>
      )}
      <div className="pr-row pr-sm"><span>CGST</span><span>{money(r.cgst)}</span></div>
      <div className="pr-row pr-sm"><span>SGST</span><span>{money(r.sgst)}</span></div>
      <div className="pr-row pr-bold"><span>TOTAL</span><span>{money(r.total)}</span></div>
      <div className="pr-rule" />

      {r.payments.map((p, i) => (
        <div key={i} className="pr-row pr-sm">
          <span className="pr-cap">Paid ({p.method})</span><span>{money(p.amount)}</span>
        </div>
      ))}
      {r.changeDue > 0 && (
        <div className="pr-row pr-sm pr-bold"><span>Change</span><span>{money(r.changeDue)}</span></div>
      )}
      <div className="pr-rule" />
      <div className="pr-center pr-sm">{r.footer ?? `Thank you for shopping at ${r.storeName}`}</div>
      {/* Feed the roll past the tear bar. */}
      <div className="pr-feed" />
    </div>,
    document.body,
  );
}

/** Fire the browser print dialog for the currently-mounted receipt. */
export function printReceipt() {
  if (typeof window !== "undefined") window.print();
}
