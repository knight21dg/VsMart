"use client";

import * as React from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import {
  AlertTriangle, CloudOff, FileText, Loader2, Minus, Package, Plus, Printer, Receipt, RefreshCw,
  Keyboard, ScanLine, Search, ShieldCheck, Star, Trash2, UserPlus, Volume2, VolumeX,
  WifiOff, X,
} from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { ApiError } from "@/lib/types";
import { useOnline } from "@/lib/offline/use-online";
import { syncOutbox } from "@/lib/offline/sync";
import {
  adjustCachedStock, enqueueSale, listQueue, newQueuedSale, removeSale,
  saveCatalog, searchCached, updateSale, type CachedProduct, type ProductVariantOption,
  type QueuedSale,
} from "@/lib/offline/db";
import { PageHeader } from "@/components/page-header";
import { RequirePerm } from "@/components/permission-gate";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger,
} from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { EmptyState } from "@/components/states";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { ProductLink } from "@/components/product-link";
import { PosPrintReceipt, printReceipt, type PrintReceipt } from "@/components/pos-print-receipt";
import { CloseSession } from "@/components/pos/close-session";
import { useFocusOnModalClose, useHotkeys } from "@/lib/use-hotkeys";
import {
  beepError, beepScan, beepSuccess, beepTick, isMuted, isMutedServer, setMuted, subscribeMuted,
} from "@/lib/pos-sound";
import { useStore } from "@/lib/store/store-context";
import { cn, inr } from "@/lib/utils";

interface SessionResp {
  session: { id: number; status: string; openingCash: number; cashier: string; drawer?: Record<string, number> } | null;
}
interface SearchRow {
  productId: string; name: string; brand: string; unit?: string;
  price: number; mrp: number; available: number;
  // The bare base (no-variant) bucket, distinct from the product total `available`.
  // For a variant product the base isn't sellable, so the till must never show the
  // total against it.
  baseAvailable?: number;
  imageUrl?: string; variants?: ProductVariantOption[];
}
interface CustomerResp { customerId: string; name: string; phone: string; creditStatus: string; creditAvailable: number; outstanding: number; }
interface CartLine { lineId: string; productId: string; variantId?: string; name: string; price: number; qty: number; available: number; }
interface SaleResp {
  code: string; total: number; tax: number; subtotal: number; changeDue: number;
  creditUsed: number; paymentStatus: string;
  items: { name: string; quantity: number; lineTotal: number }[];
  payments: { method: string; amount: number }[];
}

interface ScanResp {
  productId: string; variantId: string | null; variantLabel: string | null;
  name: string; price: number; mrp: number; available: number; barcode: string;
}
interface OnlineOrder { keyId: string; orderId: string; amount: number; currency: string; gateway: string }
interface DraftItem { productId: string; variantId?: string; name: string; price: number; qty: number; available?: number }
interface DraftPayload { items?: DraftItem[]; customer?: CustomerResp | null; couponCode?: string; discount?: number; total?: number }

interface RazorpaySuccess { razorpay_payment_id: string; razorpay_signature: string; razorpay_order_id: string }
type RazorpayInstance = { open: () => void };
type RazorpayWindow = Window & {
  Razorpay?: new (opts: Record<string, unknown>) => RazorpayInstance;
};

const METHODS = [
  { key: "cash", label: "Cash" },
  { key: "online", label: "Online" },
  { key: "credit", label: "Credit" },
] as const;
type Method = (typeof METHODS)[number]["key"];

export default function POSPage() {
  return (
    <RequirePerm perm="pos.operate">
      <React.Suspense fallback={<div className="flex justify-center py-20"><Loader2 className="size-6 animate-spin text-muted-foreground" /></div>}>
        <POSInner />
      </React.Suspense>
    </RequirePerm>
  );
}

function POSInner() {
  const qc = useQueryClient();
  const sessionQ = useQuery({ queryKey: ["store", "pos", "session"], queryFn: () => api.get<SessionResp>("/store/pos/session") });
  const settingsQ = useQuery({
    queryKey: ["store", "settings"],
    queryFn: () => api.get<{ platform: { gstRate: number; posPriceTaxInclusive: boolean } }>("/store/settings"),
  });
  // `/store/settings` reports GST as a PERCENTAGE (18), the same as every other
  // API surface; the tax maths below needs the fraction, so convert once here.
  const gstPercent = settingsQ.data?.platform.gstRate ?? 18;
  const gstRate = gstPercent / 100;
  // Mirrors `pos.services._split_tax`: when prices are tax-INCLUSIVE the shelf
  // price already contains GST and tax is backed OUT of it; otherwise tax is added
  // on top. Hardcoding "exclusive" here meant flipping this config made the till
  // display ~18% more than the server actually charges.
  const taxInclusive = settingsQ.data?.platform.posPriceTaxInclusive ?? false;
  const session = sessionQ.data?.session ?? null;

  const online = useOnline();
  const [cart, setCart] = React.useState<CartLine[]>([]);
  const [customer, setCustomer] = React.useState<CustomerResp | null>(null);
  const [method, setMethod] = React.useState<Method>("cash");
  const [tendered, setTendered] = React.useState("");
  const [creditOtp, setCreditOtp] = React.useState("");
  const [otpSent, setOtpSent] = React.useState(false);
  const [couponCode, setCouponCode] = React.useState("");   // applied code
  const [discount, setDiscount] = React.useState(0);         // applied discount amount
  const [lastSale, setLastSale] = React.useState<SaleResp | null>(null);
  const scanInputRef = React.useRef<HTMLInputElement | null>(null);
  // localStorage is an external store — read it through useSyncExternalStore so
  // there's no setState-in-an-effect (lint error here) and no wrong-icon flash.
  const muted = React.useSyncExternalStore(subscribeMuted, isMuted, isMutedServer);
  const [charging, setCharging] = React.useState(false);
  const { me } = useStore();

  // The print payload. Derived from the sale we already hold, so printing needs
  // no extra round-trip — the cashier hits F10 and the roll moves.
  const printable = React.useMemo<PrintReceipt | null>(() => {
    if (!lastSale) return null;
    const half = round2(lastSale.tax / 2);
    return {
      storeName: me?.store?.name ?? "VS Mart",
      storeAddress: me?.store?.address ?? undefined,
      gstin: me?.store?.gstin ?? undefined,
      phone: me?.store?.phone ?? undefined,
      code: lastSale.code,
      datetime: new Date().toLocaleString("en-IN"),
      cashier: session?.cashier,
      customer: customer?.name ?? null,
      lines: lastSale.items.map((i) => ({
        name: i.name,
        qty: i.quantity,
        // lineTotal is PRE-tax (see pos.services.build_receipt), so rate derives cleanly.
        rate: i.quantity ? i.lineTotal / i.quantity : 0,
        amount: i.lineTotal,
      })),
      subtotal: lastSale.subtotal,
      discount: 0,
      cgst: half,
      sgst: round2(lastSale.tax - half),
      total: lastSale.total,
      payments: lastSale.payments,
      changeDue: lastSale.changeDue,
    };
  }, [lastSale, me, session, customer]);

  // The offline outbox, surfaced as a query so the UI tracks it without manual
  // state. `invalidateOutbox` re-reads it after enqueue/sync/resolve.
  const outboxQ = useQuery({ queryKey: ["store", "pos", "outbox"], queryFn: () => listQueue() });
  const queue = React.useMemo(() => outboxQ.data ?? [], [outboxQ.data]);
  const invalidateOutbox = React.useCallback(
    () => qc.invalidateQueries({ queryKey: ["store", "pos", "outbox"] }),
    [qc],
  );

  // Keep a local catalog snapshot fresh while online so search/scan + billing
  // keep working through an outage.
  useQuery({
    queryKey: ["store", "pos", "catalog-cache"],
    queryFn: async () => {
      const data = await api.get<{ products: CachedProduct[] }>("/store/pos/catalog");
      await saveCatalog(data.products ?? []);
      return data.products?.length ?? 0;
    },
    enabled: online,
    staleTime: 5 * 60_000,
    refetchInterval: online ? 5 * 60_000 : false,
  });

  // Sync as a mutation (no manual loading state). Drains the outbox to the
  // backend; runs on demand and automatically when connectivity returns.
  const syncMut = useMutation({
    mutationFn: () => syncOutbox(),
    onSuccess: (res) => {
      invalidateOutbox();
      if (res.synced > 0) {
        qc.invalidateQueries({ queryKey: ["store", "pos", "transactions"] });
        qc.invalidateQueries({ queryKey: ["store", "inventory"] });
        toast.success(`Synced ${res.synced} offline sale${res.synced > 1 ? "s" : ""}`);
      }
      if (res.conflicts > 0) {
        toast.error(`${res.conflicts} queued sale${res.conflicts > 1 ? "s" : ""} need review`);
      }
    },
  });
  const runSync = syncMut.mutate;
  React.useEffect(() => { if (online) runSync(); }, [online, runSync]);

  // Per-line, matching the server's loop (it rounds each line, not the sum).
  const subtotal = cart.reduce(
    (s, l) => s + (taxInclusive ? round2((l.price * l.qty) / (1 + gstRate)) : l.price * l.qty), 0);
  const tax = cart.reduce((s, l) => {
    const base = l.price * l.qty;
    return s + (taxInclusive ? round2(base - round2(base / (1 + gstRate))) : round2(base * gstRate));
  }, 0);
  const appliedDiscount = Math.min(discount, round2(subtotal + tax));
  const total = round2(subtotal + tax - appliedDiscount);

  /// Add to the cart, never above on-hand and never at all when out of stock.
  /// Returns false when nothing was added, so callers can skip their success beep.
  function addLine(line: { productId: string; variantId?: string; name: string; price: number; available: number }, qty = 1) {
    // Out of stock is a HARD no. (The old guard clamped with `max(available, 1)`,
    // which turned available:0 into a quantity of 1 — it added the very thing it
    // was meant to block, and checkout then 409'd at Charge.)
    if (line.available <= 0) {
      beepError();
      toast.error(`${line.name} is out of stock.`);
      return false;
    }
    const lineId = line.variantId ? `${line.productId}:${line.variantId}` : line.productId;
    setCart((c) => {
      const ex = c.find((l) => l.lineId === lineId);
      if (ex) {
        // Clamp at hand: checkout rejects over-sell with a 409, so without this the
        // cashier only discovers it at Charge — with the customer already waiting.
        const next = Math.min(ex.qty + qty, Math.max(ex.available, ex.qty));
        if (next === ex.qty) toast.warning(`Only ${ex.available} of ${ex.name} in stock.`);
        return c.map((l) => (l.lineId === lineId ? { ...l, qty: next } : l));
      }
      return [...c, { lineId, ...line, qty: Math.min(qty, line.available) }];
    });
    return true;
  }
  function addToCart(p: SearchRow, variant?: ProductVariantOption, qty = 1) {
    addLine({
      productId: p.productId,
      variantId: variant?.id,
      name: variant ? `${p.name} · ${variant.label}` : p.name,
      price: variant ? variant.price : p.price,
      // Each pack has its own shelf: gate on the variant's available, not the
      // product total — otherwise a 1kg with 0 stock rode in on the 500g's count.
      available: variant ? variant.available : p.available,
    }, qty);
  }
  // Scan a barcode → resolve product/variant → add straight to the cart (no search).
  async function scanCode(code: string) {
    const trimmed = code.trim();
    if (!trimmed) return;
    try {
      if (online) {
        const p = await api.get<ScanResp>("/store/pos/scan", { code: trimmed });
        // NB: `name` already reads "Product · Variant" for a variant barcode — the
        // scan endpoint composes it server-side. Don't re-append `variantLabel`.
        // addLine refuses an out-of-stock item and reports its own error, so
        // don't beep "Added" over the top of it.
        if (addLine({ productId: p.productId, variantId: p.variantId ?? undefined, name: p.name, price: p.price, available: p.available })) {
          beepScan();
          toast.success(`Added ${p.name}`);
        }
        return;
      }
      // OFFLINE: resolve against the cached catalog, which stores each product's
      // primary barcode for exactly this. Refusing to scan offline defeated the
      // point of an offline till — the scanner IS the till's main input.
      const hit = (await searchCached(trimmed)).find((p) => p.barcode === trimmed);
      if (!hit) {
        beepError();
        toast.error("Not in the offline catalog. Sync when you're back online.");
        return;
      }
      if (addLine({ productId: hit.productId, name: hit.name, price: hit.price, available: hit.available })) {
        beepScan();
        toast.success(`Added ${hit.name} (offline)`);
      }
    } catch (e) {
      beepError();
      toast.error(e instanceof ApiError ? e.message : "Unknown barcode.");
    }
  }
  // Quantities are DECIMAL: a grocer sells tomatoes at 1.35 kg, not "1 tomato".
  // Rounded to 3dp so float arithmetic from the ± buttons never leaves 1.2000000002
  // on the bill.
  function setQty(lineId: string, qty: number) {
    setCart((c) => (qty <= 0
      ? c.filter((l) => l.lineId !== lineId)
      // Never let the cart exceed on-hand — the server 409s at Charge otherwise.
      : c.map((l) => (l.lineId === lineId ? { ...l, qty: round3(Math.min(qty, Math.max(l.available, 1))) } : l))));
  }
  // Fractional quantities are billed correctly here but TRUNCATED by the backend
  // (storeops/pos_views.py casts qty with int()). Until that lands the cashier
  // must see it rather than discover a variance at close of till.
  const fractionalLines = cart.filter((l) => !Number.isInteger(l.qty));
  function clearSale() {
    setCart([]); setCustomer(null); setTendered(""); setMethod("cash");
    setCreditOtp(""); setOtpSent(false); setCouponCode(""); setDiscount(0);
  }

  // Wiping a rung-up sale is destructive and used to happen on a bare Escape with
  // no prompt and no visible control — a cashier dismissing a dialog lost the
  // whole cart and had no idea what they'd pressed. Escape and the Clear button
  // both route through here; a non-empty cart always asks first.
  const [confirmClear, setConfirmClear] = React.useState(false);
  function requestClearSale() {
    if (cart.length === 0) { clearSale(); return; }
    beepTick();
    setConfirmClear(true);
  }

  // Validate + apply a coupon against the current subtotal.
  const applyCoupon = useApiMutation<string, { code: string; discount: number }>(
    (code: string) => api.post("/store/pos/coupon", { code, subtotal }),
    { onDone: (r) => { setCouponCode(r.code); setDiscount(r.discount); toast.success(`Coupon applied — ${inr(r.discount)} off`); } },
  );

  // Save the current cart as a draft.
  const saveDraft = useApiMutation<void, { id: string }>(
    () => api.post("/store/pos/drafts", {
      label: customer?.name || "",
      customerId: customer?.customerId,
      payload: {
        items: cart.map((l) => ({ productId: l.productId, variantId: l.variantId, name: l.name, price: l.price, qty: l.qty, available: l.available })),
        customer, couponCode: couponCode || undefined, discount: appliedDiscount, total,
      },
    }),
    { invalidate: [["store", "pos", "drafts"]], successMessage: "Saved to drafts", onDone: () => clearSale() },
  );

  // Resume a parked draft (?resume=<id>): load its cart + customer + coupon, then
  // remove it. Loaded once via a keyed guard so it doesn't re-run on re-render.
  const search = useSearchParams();
  const resumeId = search.get("resume");
  const router = useRouter();
  const resumedRef = React.useRef<string | null>(null);
  React.useEffect(() => {
    if (!resumeId || resumedRef.current === resumeId) return;
    resumedRef.current = resumeId;
    (async () => {
      try {
        const d = await api.get<{ payload: DraftPayload }>(`/store/pos/drafts/${resumeId}`);
        const p = d.payload || {};
        setCart((p.items ?? []).map((i) => ({
          lineId: i.variantId ? `${i.productId}:${i.variantId}` : i.productId,
          productId: i.productId, variantId: i.variantId, name: i.name, price: i.price,
          qty: i.qty, available: i.available ?? 0,
        })));
        if (p.customer) setCustomer(p.customer);
        if (p.couponCode) { setCouponCode(p.couponCode); setDiscount(p.discount ?? 0); }
        await api.del(`/store/pos/drafts/${resumeId}`);
        qc.invalidateQueries({ queryKey: ["store", "pos", "drafts"] });
        toast.success("Draft loaded");
      } catch {
        toast.error("Couldn't load that draft.");
      } finally {
        router.replace("/pos");
      }
    })();
  }, [resumeId, router, qc]);

  // Ring up the sale. Online → POST with an idempotency key. Offline (or on a
  // network/5xx failure) → persist to the outbox so billing never stops; the cash
  // is already taken, so the bill must survive. The stable key makes sync replay
  // safe against double-posting.
  function handleCharge() {
    if (cart.length === 0 || charging) return;
    if (method === "online") return void handleOnlineCharge();
    if (method === "credit") return void handleCreditCharge();
    return void handleCashCharge();
  }

  // Retail F-keys: a cashier works scanner-in-hand and shouldn't reach for a
  // mouse mid-queue. These fire even while the scan box has focus (it always
  // does — the scanner types into it), but NEVER while a dialog is open — see
  // useHotkeys, which used to let F9 complete a sale from behind one.
  useHotkeys({
    F2: () => scanInputRef.current?.focus(),
    F4: () => { if (cart.length) { beepTick(); setMethod("cash"); } },
    F6: () => { if (cart.length) { beepTick(); setMethod("online"); } },
    F7: () => { if (cart.length) { beepTick(); setMethod("credit"); } },
    F8: () => { if (cart.length && !saveDraft.isPending && !charging) saveDraft.mutate(); },
    F9: () => handleCharge(),
    F10: () => { if (lastSale) printReceipt(); },
    Escape: () => requestClearSale(),
  });
  // Closing a dialog hands focus back to whatever opened it (a product card, say),
  // so the next scan typed into a button and its Enter reopened the dialog. Put
  // the scanner back in charge.
  useFocusOnModalClose(scanInputRef);

  // Post a completed sale (online / credit — both require a live connection).
  async function completeSale(payment: { method: string; amount: number }, extra: Record<string, unknown>) {
    const resp = await api.post<SaleResp>(
      "/store/pos/checkout",
      {
        items: cart.map((l) => ({ productId: l.productId, variantId: l.variantId, qty: l.qty })),
        payments: [payment], customerId: customer?.customerId,
        couponCode: couponCode || undefined, ...extra,
      },
      undefined,
      { headers: { "Idempotency-Key": crypto.randomUUID() } },
    );
    beepSuccess();
    setLastSale(resp);
    clearSale();
    qc.invalidateQueries({ queryKey: ["store", "pos", "transactions"] });
    qc.invalidateQueries({ queryKey: ["store", "inventory"] });
    toast.success("Sale completed");
  }

  // Cash: offline-resilient. Online → POST; offline/network drop → queue so billing
  // never stops (cash already taken); the stable key makes sync replay safe.
  async function handleCashCharge() {
    setCharging(true);
    const amount = Number(tendered || total);
    const sale = newQueuedSale({
      items: cart.map((l) => ({ productId: l.productId, variantId: l.variantId, name: l.name, qty: l.qty, price: l.price })),
      payment: { method: "cash", amount }, customerId: customer?.customerId, customerName: customer?.name, total,
      // The coupon rides along to sync. Without it the replay posted at full
      // price while the drawer only ever held the discounted cash — the till
      // came up short by the discount on every offline coupon sale. Only the
      // code is replayed; the server recomputes the amount (`appliedDiscount`
      // here is for display and audit).
      couponCode: couponCode || undefined, discount: appliedDiscount,
    });
    try {
      if (!online) throw new Error("offline");
      const resp = await api.post<SaleResp>(
        "/store/pos/checkout",
        { items: sale.items.map((i) => ({ productId: i.productId, variantId: i.variantId, qty: i.qty })),
          payments: [sale.payment], customerId: sale.customerId, couponCode: couponCode || undefined },
        undefined, { headers: { "Idempotency-Key": sale.id } },
      );
      beepSuccess(); setLastSale(resp); clearSale();
      qc.invalidateQueries({ queryKey: ["store", "pos", "transactions"] });
      qc.invalidateQueries({ queryKey: ["store", "inventory"] });
      toast.success("Sale completed");
    } catch (err) {
      const serverRejected = err instanceof ApiError && err.status >= 400 && err.status < 500;
      if (serverRejected) {
        toast.error((err as ApiError).status === 409 ? "Out of stock — sale not completed." : (err as ApiError).message);
      } else {
        await enqueueSale(sale); await adjustCachedStock(sale.items);
        setLastSale(queuedReceipt(sale)); clearSale(); invalidateOutbox();
        toast.message("Saved offline — will sync automatically");
      }
    } finally { setCharging(false); }
  }

  // Online: create a Razorpay order, open Checkout (or auto-settle on the dev mock
  // gateway), then complete the sale with the verified payment reference.
  async function handleOnlineCharge() {
    setCharging(true);
    try {
      const order = await api.post<OnlineOrder>("/store/pos/online/order", { amount: total });
      let ref = { razorpayOrderId: order.orderId, razorpayPaymentId: "mock", razorpaySignature: "mock" };
      if (order.gateway === "razorpay") {
        const res = await openRazorpay(order);
        if (!res) { setCharging(false); return; } // customer dismissed
        ref = { razorpayOrderId: res.razorpay_order_id, razorpayPaymentId: res.razorpay_payment_id, razorpaySignature: res.razorpay_signature };
      }
      await completeSale({ method: "online", amount: total }, ref);
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Online payment failed.");
    } finally { setCharging(false); }
  }

  // Credit: the customer confirms in-app with a 2FA code the cashier enters here.
  async function requestCreditOtp() {
    if (!customer) return;
    try {
      await api.post("/store/pos/credit/request-otp", { customerId: customer.customerId, amount: total });
      setOtpSent(true);
      toast.success("Confirmation code sent to the customer's app");
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Couldn't send the code.");
    }
  }
  async function handleCreditCharge() {
    if (!customer) { toast.error("Attach a customer to bill on credit."); return; }
    if (!creditOtp.trim()) { toast.error("Enter the confirmation code from the customer's app."); return; }
    setCharging(true);
    try {
      await completeSale({ method: "credit", amount: total }, { creditOtp: creditOtp.trim() });
    } catch (err) {
      toast.error(err instanceof ApiError ? err.message : "Credit sale failed.");
    } finally { setCharging(false); }
  }

  async function retryQueued(s: QueuedSale) {
    await updateSale({ ...s, status: "pending", error: undefined });
    invalidateOutbox();
    runSync();
  }
  async function discardQueued(s: QueuedSale) {
    await removeSale(s.id);
    invalidateOutbox();
  }

  if (sessionQ.isLoading) return <div className="flex justify-center py-20"><Loader2 className="size-6 animate-spin text-muted-foreground" /></div>;

  if (!session) return <NoSession onOpened={() => qc.invalidateQueries({ queryKey: ["store", "pos", "session"] })} />;

  const creditBlocked = method === "credit" && (!customer || customer.creditAvailable < total);

  return (
    <div className="space-y-5">
      <PageHeader
        title="Point of Sale"
        description={`Till open · opening float ${inr(session.openingCash)}`}
        actions={
          <div className="flex items-center gap-2">
            <Button
              variant="outline" size="icon"
              title={muted ? "Scanner sounds off — click to enable" : "Scanner sounds on"}
              aria-label={muted ? "Unmute scanner sounds" : "Mute scanner sounds"}
              onClick={() => { const next = !muted; setMuted(next); if (!next) beepScan(); }}
            >
              {muted ? <VolumeX className="size-4 text-muted-foreground" /> : <Volume2 className="size-4" />}
            </Button>
            <HotkeyLegend />
            <CloseSession onClosed={() => qc.invalidateQueries({ queryKey: ["store", "pos", "session"] })} />
          </div>
        }
      />

      <OfflineBar online={online} queueCount={queue.length} syncing={syncMut.isPending} onSync={runSync} />

      {/* `items-start` so the sticky column can size to its content rather than
          being stretched to the catalog's height (which would kill the stick). */}
      <div className="grid items-start gap-4 lg:grid-cols-[minmax(340px,420px)_1fr]">
        {/* Left: the bill — 1) cart (products), 2) customer, 3) payment.
            STICKY: the cashier scrolls the catalog to find items, and the running
            bill + Charge button must stay on screen the whole time — scrolling
            back up to take payment is a per-customer tax. It scrolls internally
            when the bill grows past the viewport. */}
        <div className="space-y-4 lg:sticky lg:top-4 lg:max-h-[calc(100vh-6rem)] lg:overflow-y-auto lg:pr-1">
          <Card>
            <CardHeader className="flex-row items-center justify-between gap-2 py-3">
              <CardTitle className="text-sm">1 · Cart ({cart.length})</CardTitle>
              {/* Clearing the sale was Escape-only and therefore invisible — the
                  one destructive action on the page had no control at all. */}
              {cart.length > 0 && (
                <Button variant="ghost" size="sm" className="h-7 text-muted-foreground" onClick={requestClearSale}>
                  <Trash2 className="size-3.5" /> Clear cart <span className="ml-1 text-[10px] opacity-60">Esc</span>
                </Button>
              )}
            </CardHeader>
            <CardContent className="pt-0">
              {cart.length === 0 ? (
                <EmptyState title="Cart is empty" description="Scan a barcode or tap a product to add it." />
              ) : (
                <ul className="divide-y">
                  {cart.map((l) => (
                    <li key={l.lineId} className="flex items-center gap-2 py-2">
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-sm"><ProductLink id={l.productId} name={l.name} className="font-medium" /></p>
                        <p className="text-xs text-muted-foreground">{inr(l.price)} each</p>
                      </div>
                      <div className="flex items-center gap-1">
                        <Button variant="outline" size="icon" className="size-7" onClick={() => setQty(l.lineId, l.qty - 1)}><Minus className="size-3" /></Button>
                        <QtyInput value={l.qty} label={l.name} onCommit={(n) => setQty(l.lineId, n)} />
                        <Button variant="outline" size="icon" className="size-7" onClick={() => setQty(l.lineId, l.qty + 1)}><Plus className="size-3" /></Button>
                      </div>
                      <span className="w-20 text-right text-sm font-semibold">{inr(l.price * l.qty)}</span>
                      <Button variant="ghost" size="icon" className="size-7 text-muted-foreground" onClick={() => setQty(l.lineId, 0)}><Trash2 className="size-3.5" /></Button>
                    </li>
                  ))}
                </ul>
              )}
              {fractionalLines.length > 0 && <FractionalQtyWarning lines={fractionalLines} />}
            </CardContent>
          </Card>

          <div className="space-y-1.5">
            <p className="px-1 text-sm font-semibold text-muted-foreground">2 · Customer {method === "credit" && <span className="text-destructive">(required)</span>}</p>
            <CustomerPanel customer={customer} onSet={setCustomer} />
          </div>

          <Card>
            <CardHeader className="py-3"><CardTitle className="text-sm">3 · Payment</CardTitle></CardHeader>
            <CardContent className="space-y-3 pt-0">
              <div className="space-y-1 text-sm">
                <Row label="Subtotal" value={inr(subtotal, { decimals: true })} />
                <Row label={`GST (${gstPercent}%)`} value={inr(tax, { decimals: true })} />
                {appliedDiscount > 0 && (
                  <div className="flex justify-between text-[var(--color-success)]">
                    <span>Discount {couponCode && <span className="font-medium">({couponCode})</span>}</span>
                    <span>− {inr(appliedDiscount, { decimals: true })}</span>
                  </div>
                )}
                <div className="flex justify-between border-t pt-2 text-base font-bold">
                  <span>Grand Total</span><span>{inr(total, { decimals: true })}</span>
                </div>
              </div>

              {/* Coupon */}
              {couponCode ? (
                <div className="flex items-center justify-between rounded-md border border-[var(--color-success)]/40 bg-[var(--color-success)]/10 px-3 py-2 text-sm">
                  <span>Coupon <span className="font-semibold">{couponCode}</span> applied</span>
                  <Button variant="ghost" size="icon" className="size-6" onClick={() => { setCouponCode(""); setDiscount(0); }}><X className="size-3.5" /></Button>
                </div>
              ) : (
                <CouponInput onApply={(code) => applyCoupon.mutate(code)} pending={applyCoupon.isPending} disabled={cart.length === 0} />
              )}

              <div className="grid grid-cols-3 gap-1.5">
                {METHODS.map((m) => (
                  <button key={m.key} onClick={() => setMethod(m.key)}
                    className={`rounded-md border py-2 text-xs font-medium transition-colors ${method === m.key ? "border-primary bg-primary text-primary-foreground" : "hover:bg-accent"}`}>
                    {m.label}
                  </button>
                ))}
              </div>

              {method === "cash" && (
                <div className="space-y-1.5">
                  <Label>Cash tendered</Label>
                  <Input inputMode="numeric" value={tendered} onChange={(e) => setTendered(e.target.value)} placeholder={String(total)} />
                  {Number(tendered) > total && <p className="text-xs text-muted-foreground">Change: {inr(Number(tendered) - total, { decimals: true })}</p>}
                </div>
              )}

              {method === "online" && (
                <p className="rounded-md border bg-muted/40 px-3 py-2 text-xs text-muted-foreground">
                  Razorpay Checkout opens when you charge — the customer pays by UPI / card / netbanking.
                </p>
              )}

              {method === "credit" && (
                <div className="space-y-2">
                  <p className={`text-xs ${creditBlocked ? "text-destructive" : "text-muted-foreground"}`}>
                    {!customer ? "Attach a customer above to bill on credit." :
                      customer.creditAvailable < total ? `Insufficient credit (available ${inr(customer.creditAvailable)}).` :
                      `Credit available: ${inr(customer.creditAvailable)}`}
                  </p>
                  {customer && customer.creditAvailable >= total && (
                    <>
                      <Button variant="outline" size="sm" className="w-full" onClick={requestCreditOtp} disabled={charging}>
                        <ShieldCheck className="size-4" /> {otpSent ? "Resend code to customer's app" : "Send confirmation code"}
                      </Button>
                      <div className="space-y-1.5">
                        <Label>Confirmation code (from the customer&apos;s app)</Label>
                        <Input inputMode="numeric" maxLength={6} value={creditOtp}
                          onChange={(e) => setCreditOtp(e.target.value)} placeholder="6-digit code" />
                      </div>
                    </>
                  )}
                </div>
              )}

              <div className="flex gap-2">
                <Button variant="outline" className="shrink-0" disabled={cart.length === 0 || saveDraft.isPending || charging} onClick={() => saveDraft.mutate()}>
                  {saveDraft.isPending ? <Loader2 className="size-4 animate-spin" /> : <FileText className="size-4" />} Draft <span className="ml-1 text-[10px] opacity-60">F8</span>
                </Button>
                {/* Fractional quantities are rejected server-side (integer stock
                    spine), so block the charge here rather than let the cashier
                    take payment and then hit a 400. */}
                <Button className="flex-1" disabled={cart.length === 0 || charging || creditBlocked || fractionalLines.length > 0 || (method === "credit" && !creditOtp.trim())} onClick={handleCharge}>
                  {charging && <Loader2 className="size-4 animate-spin" />}
                  {method === "online" ? "Pay online · " : method === "credit" ? "Bill to credit · " : online ? "Charge · " : "Charge offline · "}
                  {inr(total, { decimals: true })}
                  <span className="ml-1 text-[10px] opacity-70">F9</span>
                </Button>
              </div>
            </CardContent>
          </Card>

          {lastSale && <ReceiptCard sale={lastSale} onClose={() => setLastSale(null)} />}

          <QueuedSalesCard queue={queue} onRetry={retryQueued} onDiscard={discardQueued} />
        </div>

        {/* Right: scan-to-cart + product catalog */}
        <ProductCatalog onAdd={addToCart} onScan={scanCode} online={online} scanRef={scanInputRef} />
      </div>

      <ConfirmDialog
        open={confirmClear}
        onOpenChange={setConfirmClear}
        title="Clear this sale?"
        description={`${cart.length} item${cart.length === 1 ? "" : "s"} · ${inr(total, { decimals: true })} will be removed, along with the customer and any coupon. Use Draft (F8) to park it instead.`}
        confirmLabel="Clear sale"
        destructive
        onConfirm={() => { clearSale(); setConfirmClear(false); }}
      />

      {/* Portals into <body> — `@media print` hides the app and prints only this. */}
      <PosPrintReceipt receipt={printable} />
    </div>
  );
}

/**
 * Cart quantity as a typed value, not just ± clicks.
 *
 * A shop selling loose produce bills 1.35 kg; the old read-only <span> made that
 * impossible, and reaching 1.35 by clicking + is not a thing. Holds its own text
 * while focused so a half-typed "1." isn't parsed and clobbered mid-keystroke,
 * and only commits values above zero — emptying the box must not silently delete
 * the line (that's what the bin button is for).
 */
function QtyInput({ value, label, onCommit }: {
  value: number; label: string; onCommit: (qty: number) => void;
}) {
  const [text, setText] = React.useState(String(value));
  const [editing, setEditing] = React.useState(false);
  // Follow external changes (± buttons, stock clamping) while not being typed in.
  // Adjusting state during render is the sanctioned pattern here — the same one
  // ProductDialog uses for its variant selection.
  const [seen, setSeen] = React.useState(value);
  if (!editing && seen !== value) { setSeen(value); setText(String(value)); }

  return (
    <input
      inputMode="decimal"
      aria-label={`Quantity — ${label}`}
      className="h-7 w-14 rounded-md border bg-transparent px-1 text-center text-sm font-medium tabular-nums outline-none focus-visible:border-primary"
      value={text}
      onFocus={(e) => { setEditing(true); e.currentTarget.select(); }}
      onChange={(e) => {
        // Digits + a single dot only; a scanner or a stray letter can't corrupt qty.
        const next = e.target.value.replace(/[^\d.]/g, "").replace(/(\..*)\./g, "$1");
        setText(next);
        const n = Number(next);
        if (next !== "" && Number.isFinite(n) && n > 0) onCommit(n);
      }}
      onBlur={() => {
        setEditing(false);
        const n = Number(text);
        // Blank / zero / junk → snap back to the real quantity rather than drop the line.
        if (!(Number.isFinite(n) && n > 0)) { setText(String(value)); return; }
        onCommit(n);
        setText(String(round3(n)));
      }}
      onKeyDown={(e) => { if (e.key === "Enter") e.currentTarget.blur(); }}
    />
  );
}

/**
 * Quantity is an integer column the whole way down the stock spine
 * (POSTransactionItem, StockItem, StockBatch, InventoryLedger), so the server
 * cannot honour a fractional quantity and now rejects one outright rather than
 * truncating it. Blocking the charge here keeps the failure at the point the
 * cashier can fix it, instead of after they've taken the money.
 */
function FractionalQtyWarning({ lines }: { lines: CartLine[] }) {
  return (
    <div className="mt-2 flex gap-2 rounded-md border border-destructive/40 bg-destructive/10 p-2 text-xs text-destructive">
      <AlertTriangle className="mt-0.5 size-3.5 shrink-0" />
      <div className="space-y-0.5">
        <p className="font-semibold">This till bills whole units only.</p>
        <p>
          {lines.map((l) => `${l.name} (${l.qty})`).join(", ")} can&apos;t be charged
          as a fraction. Weigh the item and enter the price as its own line, or set
          a whole quantity to continue.
        </p>
      </div>
    </div>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return <div className="flex justify-between text-muted-foreground"><span>{label}</span><span>{value}</span></div>;
}

function round2(n: number) { return Math.round(n * 100) / 100; }
/** Weighed goods need decimals; 3dp is grams on a kg scale. */
function round3(n: number) { return Math.round(n * 1000) / 1000; }

/** Lazily inject the Razorpay Checkout script (once). */
function loadRazorpay(): Promise<boolean> {
  return new Promise((resolve) => {
    const w = window as RazorpayWindow;
    if (w.Razorpay) return resolve(true);
    const s = document.createElement("script");
    s.src = "https://checkout.razorpay.com/v1/checkout.js";
    s.onload = () => resolve(true);
    s.onerror = () => resolve(false);
    document.body.appendChild(s);
  });
}

/** Open Razorpay Checkout for a POS order; resolves the success payload or null if
 * the customer dismissed it. */
async function openRazorpay(order: OnlineOrder): Promise<RazorpaySuccess | null> {
  const ok = await loadRazorpay();
  const w = window as RazorpayWindow;
  if (!ok || !w.Razorpay) return null;
  return new Promise((resolve) => {
    const rzp = new w.Razorpay!({
      key: order.keyId,
      order_id: order.orderId,
      amount: Math.round(order.amount * 100),
      currency: order.currency,
      name: "VS Mart",
      description: "In-store purchase",
      theme: { color: "#16A34A" },
      handler: (r: RazorpaySuccess) => resolve(r),
      modal: { ondismiss: () => resolve(null) },
    });
    rzp.open();
  });
}

/** A receipt stand-in shown right after an offline sale is queued. */
function queuedReceipt(sale: QueuedSale): SaleResp {
  return {
    code: "Queued — will sync",
    total: sale.total,
    tax: 0,
    subtotal: sale.total,
    changeDue: sale.payment.method === "cash" ? Math.max(0, sale.payment.amount - sale.total) : 0,
    creditUsed: sale.payment.method === "credit" ? sale.total : 0,
    paymentStatus: "queued",
    items: sale.items.map((i) => ({ name: i.name, quantity: i.qty, lineTotal: i.price * i.qty })),
    payments: [sale.payment],
  };
}

/** Connectivity + outbox status strip. Hidden when online with an empty queue. */
function OfflineBar({ online, queueCount, syncing, onSync }: {
  online: boolean; queueCount: number; syncing: boolean; onSync: () => void;
}) {
  if (online && queueCount === 0) return null;
  return (
    <div
      className={`flex items-center justify-between gap-3 rounded-lg border px-4 py-2.5 text-sm ${
        online
          ? "border-amber-300 bg-amber-50 text-amber-900 dark:border-amber-500/40 dark:bg-amber-500/10 dark:text-amber-300"
          : "border-destructive/40 bg-destructive/10 text-destructive"
      }`}
    >
      <div className="flex min-w-0 items-center gap-2">
        {online ? <CloudOff className="size-4 shrink-0" /> : <WifiOff className="size-4 shrink-0" />}
        <span className="truncate">
          {online
            ? `${queueCount} offline sale${queueCount > 1 ? "s" : ""} waiting to sync`
            : "Offline — sales are saved on this device and sync automatically when you reconnect."}
        </span>
      </div>
      {online && queueCount > 0 && (
        <Button size="sm" variant="outline" className="shrink-0" onClick={onSync} disabled={syncing}>
          {syncing ? <Loader2 className="size-3.5 animate-spin" /> : <RefreshCw className="size-3.5" />}
          Sync now
        </Button>
      )}
    </div>
  );
}

/** Lists queued offline sales; conflicts (stock ran out at sync) get retry/discard. */
function QueuedSalesCard({ queue, onRetry, onDiscard }: {
  queue: QueuedSale[]; onRetry: (s: QueuedSale) => void; onDiscard: (s: QueuedSale) => void;
}) {
  if (queue.length === 0) return null;
  return (
    <Card>
      <CardHeader className="py-3"><CardTitle className="text-sm">Offline queue ({queue.length})</CardTitle></CardHeader>
      <CardContent className="pt-0">
        <ul className="divide-y">
          {queue.map((s) => (
            <li key={s.id} className="flex items-center gap-2 py-2 text-sm">
              <div className="min-w-0 flex-1">
                <p className="truncate font-medium">{s.items.length} item{s.items.length > 1 ? "s" : ""} · {inr(s.total)}</p>
                <p className="text-xs text-muted-foreground">
                  {new Date(s.createdAt).toLocaleTimeString()} · {s.payment.method}
                  {s.customerName ? ` · ${s.customerName}` : ""}
                </p>
                {s.status === "conflict" && <p className="text-xs text-destructive">{s.error || "Needs review"}</p>}
              </div>
              <Badge variant={s.status === "conflict" ? "destructive" : "secondary"} className="capitalize">{s.status}</Badge>
              {s.status === "conflict" && (
                <>
                  <Button size="sm" variant="outline" className="h-7" onClick={() => onRetry(s)}>Retry</Button>
                  <Button size="sm" variant="ghost" className="h-7" onClick={() => onDiscard(s)}>Discard</Button>
                </>
              )}
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}

/** Browsable product catalog as tappable cards. Clicking a card opens a details
 * dialog (image, variants, quantity, stock) that adds the chosen item to the cart. */
function ProductCatalog({ onAdd, onScan, online, scanRef }: {
  onAdd: (p: SearchRow, variant?: ProductVariantOption, qty?: number) => void;
  onScan: (code: string) => void;
  online: boolean;
  /** Owned by the page so F2 can jump focus back to the scanner from anywhere. */
  scanRef: React.RefObject<HTMLInputElement | null>;
}) {
  const [q, setQ] = React.useState("");
  const [dq, setDq] = React.useState("");
  const [scan, setScan] = React.useState("");
  const [brand, setBrand] = React.useState("");
  const [category, setCategory] = React.useState("");
  const [selected, setSelected] = React.useState<SearchRow | null>(null);

  React.useEffect(() => {
    const t = setTimeout(() => setDq(q.trim()), 250);
    return () => clearTimeout(t);
  }, [q]);

  const brandsQ = useQuery({ queryKey: ["store", "brands"], queryFn: () => api.get<string[]>("/store/brands"), enabled: online });
  const catsQ = useQuery({ queryKey: ["store", "categories"], queryFn: () => api.get<{ id: string; name: string; parentId: string | null }[]>("/store/categories"), enabled: online });
  const departments = (catsQ.data ?? []).filter((c) => !c.parentId);

  // Online → server search (empty query returns a browse set); offline → cache.
  const search = useQuery<SearchRow[]>({
    queryKey: ["store", "pos", "search", dq, brand, category, online],
    queryFn: () => (online
      ? api.get<SearchRow[]>("/store/pos/search", { q: dq, brand: brand || undefined, category: category || undefined })
      : searchCached(dq)),
  });
  const products = search.data ?? [];

  function submitScan(e: React.FormEvent) {
    e.preventDefault();
    if (!scan.trim()) return;
    onScan(scan);           // a hardware scanner types the code then hits Enter
    setScan("");
  }

  const ALL = "__all__";

  return (
    <Card className="flex h-full flex-col">
      <CardContent className="flex min-h-0 flex-1 flex-col gap-3 p-3">
        {/* Scan-to-cart: the primary way to add items while the POS is active. */}
        <form onSubmit={submitScan} className="relative">
          <ScanLine className="absolute left-2.5 top-2.5 size-4 text-primary" />
          <Input ref={scanRef} autoFocus className="border-primary/40 pl-8" placeholder="Scan barcode…  (F2)"
            value={scan} onChange={(e) => setScan(e.target.value)} />
        </form>
        <div className="grid gap-2 sm:grid-cols-2">
          <Select value={brand || ALL} onValueChange={(v) => setBrand(v === ALL ? "" : v)}>
            <SelectTrigger><SelectValue placeholder="Select Brand" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All brands</SelectItem>
              {(brandsQ.data ?? []).map((b) => <SelectItem key={b} value={b}>{b}</SelectItem>)}
            </SelectContent>
          </Select>
          <Select value={category || ALL} onValueChange={(v) => setCategory(v === ALL ? "" : v)}>
            <SelectTrigger><SelectValue placeholder="Select Category" /></SelectTrigger>
            <SelectContent>
              <SelectItem value={ALL}>All categories</SelectItem>
              {departments.map((c) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
        <div className="relative">
          <Search className="absolute left-2.5 top-2.5 size-4 text-muted-foreground" />
          <Input className="pl-8" placeholder="…or search products" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
        {search.isLoading ? (
          <div className="grid flex-1 place-items-center py-10"><Loader2 className="size-5 animate-spin text-muted-foreground" /></div>
        ) : products.length === 0 ? (
          <EmptyState title="No products" description={dq ? "Nothing matches that search." : "No products in this store yet."} />
        ) : (
          <div className="grid grid-cols-2 gap-3 overflow-y-auto sm:grid-cols-3 xl:grid-cols-4">
            {products.map((p) => (
              <button key={p.productId} onClick={() => setSelected(p)}
                className="group flex flex-col overflow-hidden rounded-lg border text-left transition-colors hover:border-primary hover:bg-accent">
                <div className="relative grid aspect-square place-items-center overflow-hidden bg-muted">
                  {p.imageUrl ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={api.assetUrl(p.imageUrl)} alt="" className="size-full object-cover" />
                  ) : (
                    <Package className="size-8 text-muted-foreground" />
                  )}
                  <span className={`absolute right-1 top-1 rounded px-1.5 py-0.5 text-[10px] font-medium ${p.available > 0 ? "bg-background/80 text-muted-foreground" : "bg-destructive text-destructive-foreground"}`}>
                    {p.available > 0 ? `${p.available} left` : "Out"}
                  </span>
                </div>
                <div className="flex flex-1 flex-col gap-0.5 p-2">
                  <p className="line-clamp-2 text-xs font-medium leading-tight">{p.name}</p>
                  <p className="mt-auto text-sm font-semibold">{inr(p.price)}</p>
                </div>
              </button>
            ))}
          </div>
        )}
      </CardContent>
      {selected && (
        <ProductDialog product={selected} onAdd={onAdd} onClose={() => setSelected(null)} />
      )}
    </Card>
  );
}

interface ProductDetail {
  productId: string; name: string; brand: string; unit: string;
  price: number; mrp: number; discountPercent: number;
  imageUrl: string; gallery: string[]; rating: number; reviews: number;
  description: string; available: number; baseAvailable?: number;
  variants: ProductVariantOption[];
}

/** Product detail popup — mirrors the customer app's product page: gallery,
 * brand·unit, rating, price/MRP/discount, variants, quantity, stock, description. */
function ProductDialog({ product, onAdd, onClose }: {
  product: SearchRow;
  onAdd: (p: SearchRow, variant?: ProductVariantOption, qty?: number) => void;
  onClose: () => void;
}) {
  const [variant, setVariant] = React.useState<ProductVariantOption | null>(null);
  const [qty, setQty] = React.useState(1);
  const [img, setImg] = React.useState(0);

  // Fetch the full store-resolved detail (falls back to the grid row while loading).
  const detailQ = useQuery({
    queryKey: ["store", "pos", "product", product.productId],
    queryFn: () => api.get<ProductDetail>(`/store/pos/product/${product.productId}`),
  });
  const d = detailQ.data;

  const name = d?.name ?? product.name;
  const brand = d?.brand ?? product.brand;
  const unit = d?.unit ?? product.unit ?? "";
  const basePrice = d?.price ?? product.price;
  const mrp = d?.mrp ?? product.mrp;
  const available = d?.available ?? product.available;
  // The base (no-variant) bucket on its own — what a no-variant product sells from.
  const baseAvailable = d?.baseAvailable ?? product.baseAvailable ?? available;
  const variants = d?.variants ?? product.variants ?? [];
  const hasVariants = variants.length > 0;

  // A variant product is sold ONLY as a pack — there is no sellable "base". Default
  // the selection to the first pack (an in-stock one when possible) so the dialog
  // opens on a real, correctly-stocked choice instead of the product total.
  // Adjusted during render (react-compiler forbids setState-in-effect); the guard
  // goes false once a pack is chosen.
  if (hasVariants && variant === null) {
    setVariant(variants.find((v) => v.available > 0) ?? variants[0]);
  }
  // Resolve the selection against the CURRENT list (detail may reload with fresh
  // per-pack stock after the grid row's copy).
  const selected = variant ? (variants.find((v) => v.id === variant.id) ?? variant) : null;

  // A selected pack shows ITS photo first (falls back to the product gallery).
  const baseGallery = (d?.gallery && d.gallery.length ? d.gallery : (product.imageUrl ? [product.imageUrl] : []));
  const gallery = selected?.imageUrl ? [selected.imageUrl, ...baseGallery] : baseGallery;
  const discount = d?.discountPercent ?? 0;
  const price = selected ? selected.price : basePrice;
  // Stock + the whole footer track the SELECTED pack; a no-variant product uses its
  // own base bucket — never the product total (which sums every pack).
  const effAvailable = selected ? selected.available : baseAvailable;

  // The product passed to onAdd carries the store-resolved values.
  const effective: SearchRow = {
    ...product, name, brand, unit, price: basePrice, mrp, available,
    imageUrl: gallery[0], variants,
  };

  const chip = (active: boolean) =>
    `rounded-md border px-3 py-1.5 text-sm transition-colors disabled:opacity-40 ${active ? "border-primary bg-primary text-primary-foreground" : "hover:bg-accent"}`;

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[88vh] max-w-md overflow-y-auto">
        <DialogHeader className="sr-only"><DialogTitle>{name}</DialogTitle></DialogHeader>

        {/* Gallery */}
        <div className="grid aspect-square w-full place-items-center overflow-hidden rounded-lg border bg-muted">
          {gallery.length > 0 ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={api.assetUrl(gallery[img] ?? gallery[0])} alt="" className="size-full object-cover" />
          ) : (
            <Package className="size-12 text-muted-foreground" />
          )}
        </div>
        {gallery.length > 1 && (
          <div className="flex gap-2">
            {gallery.map((g, i) => (
              <button key={i} onClick={() => setImg(i)}
                className={`size-12 overflow-hidden rounded-md border ${i === img ? "border-primary" : ""}`}>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={api.assetUrl(g)} alt="" className="size-full object-cover" />
              </button>
            ))}
          </div>
        )}

        {/* Brand · unit + stock status */}
        <div className="flex items-center justify-between">
          <span className="text-xs font-semibold uppercase tracking-wide text-primary">
            {brand}{unit ? ` · ${unit}` : ""}
          </span>
          <Badge variant={effAvailable > 0 ? "secondary" : "destructive"}>
            {effAvailable > 0 ? `${effAvailable} in stock` : "Out of stock"}
          </Badge>
        </div>

        <h2 className="text-lg font-bold leading-tight">{name}</h2>

        {(d?.rating ?? 0) > 0 && (
          <div className="flex items-center gap-1.5 text-sm">
            <Star className="size-4 fill-amber-400 text-amber-400" />
            <span className="font-medium">{d?.rating}</span>
            <span className="text-muted-foreground">({d?.reviews ?? 0} reviews)</span>
          </div>
        )}

        {/* Price / MRP / discount */}
        <div className="flex items-baseline gap-2">
          <span className="text-2xl font-bold">{inr(price)}</span>
          {mrp > price && <span className="text-sm text-muted-foreground line-through">{inr(mrp)}</span>}
          {discount > 0 && !selected && <Badge variant="success">{discount}% OFF</Badge>}
        </div>

        {/* A variant product is sold as a pack — there is no "Standard/base" option,
            since the base isn't independently sellable. The shopper picks a pack, and
            every following field (badge, price, quantity cap, Add) follows it. */}
        {hasVariants && (
          <div className="space-y-1.5">
            <Label>Select variation</Label>
            <div className="flex flex-wrap gap-2">
              {variants.map((v) => (
                <button key={v.id} type="button" disabled={v.available <= 0}
                  onClick={() => setVariant(v)} className={chip(selected?.id === v.id)}
                  title={v.available <= 0 ? "Out of stock" : `${v.available} in stock`}>
                  {v.label} · {inr(v.price)}
                  {v.available <= 0 && " · sold out"}
                </button>
              ))}
            </div>
          </div>
        )}

        <div className="flex items-center justify-between">
          <Label>Quantity</Label>
          <div className="flex items-center gap-2">
            <Button variant="outline" size="icon" className="size-8" onClick={() => setQty((n) => Math.max(1, n - 1))}><Minus className="size-4" /></Button>
            <span className="w-8 text-center font-medium">{qty}</span>
            <Button variant="outline" size="icon" className="size-8" onClick={() => setQty((n) => n + 1)}><Plus className="size-4" /></Button>
          </div>
        </div>
        {effAvailable > 0 && qty > effAvailable && (
          <p className="text-xs text-destructive">Only {effAvailable} in stock.</p>
        )}

        {(d?.description || detailQ.isLoading) && (
          <div className="space-y-1">
            <Label>Description</Label>
            {detailQ.isLoading ? (
              <p className="text-sm text-muted-foreground">Loading…</p>
            ) : (
              <p className="text-sm leading-relaxed text-muted-foreground">{d?.description}</p>
            )}
          </div>
        )}

        <DialogFooter>
          {/* Out of stock => nothing to add. The button used to stay live and the
              sale then failed with a 409 at Charge. */}
          <Button
            className="w-full"
            disabled={effAvailable <= 0}
            onClick={() => { onAdd(effective, selected ?? undefined, qty); onClose(); }}
          >
            <Plus className="size-4" />
            {effAvailable <= 0
              ? (selected ? `${selected.label} out of stock` : "Out of stock")
              : `Add ${qty} · ${inr(price * qty)}`}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function CustomerPanel({ customer, onSet }: { customer: CustomerResp | null; onSet: (c: CustomerResp | null) => void }) {
  const [phone, setPhone] = React.useState("");
  const [adding, setAdding] = React.useState(false);
  const lookup = useApiMutation<void, CustomerResp>(
    () => api.get<CustomerResp>("/store/pos/customer", { phone }),
    { onDone: (c) => onSet(c) }
  );
  if (customer) {
    return (
      <Card>
        <CardContent className="flex items-center justify-between p-3">
          <div>
            <p className="text-sm font-medium">{customer.name}</p>
            <p className="text-xs text-muted-foreground">{customer.phone} · credit {inr(customer.creditAvailable)}</p>
          </div>
          <Button variant="ghost" size="icon" onClick={() => onSet(null)}><X className="size-4" /></Button>
        </CardContent>
      </Card>
    );
  }
  return (
    <Card>
      <CardContent className="space-y-2 p-3">
        <div className="flex items-center justify-between">
          <Label className="flex items-center gap-1.5 text-xs"><UserPlus className="size-3.5" /> Attach a customer</Label>
          <button className="text-xs font-medium text-primary hover:underline" onClick={() => setAdding(true)}>+ New customer</button>
        </div>
        <div className="flex gap-2">
          <Input placeholder="Customer phone" value={phone} onChange={(e) => setPhone(e.target.value)} />
          <Button variant="outline" onClick={() => lookup.mutate()} disabled={lookup.isPending || phone.length < 10}>
            {lookup.isPending ? <Loader2 className="size-4 animate-spin" /> : "Find"}
          </Button>
        </div>
        {adding && <AddCustomerDialog onClose={() => setAdding(false)} onCreated={(c) => { onSet(c); setAdding(false); }} />}
      </CardContent>
    </Card>
  );
}

/** Create a walk-in customer and attach them to the sale. */
function AddCustomerDialog({ onClose, onCreated }: { onClose: () => void; onCreated: (c: CustomerResp) => void }) {
  const [f, setF] = React.useState<Record<string, string>>({});
  const set = (k: string, v: string) => setF((p) => ({ ...p, [k]: v }));
  const m = useApiMutation<void, CustomerResp>(
    () => api.post("/store/pos/customer/create", {
      firstName: f.firstName, lastName: f.lastName, phone: f.phone, email: f.email,
    }),
    { successMessage: "Customer added", onDone: (c) => onCreated(c) },
  );
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-md">
        <DialogHeader><DialogTitle>Add new customer</DialogTitle></DialogHeader>
        <div className="grid grid-cols-2 gap-3">
          <div className="space-y-1.5"><Label>First name *</Label>
            <Input value={f.firstName ?? ""} onChange={(e) => set("firstName", e.target.value)} /></div>
          <div className="space-y-1.5"><Label>Last name</Label>
            <Input value={f.lastName ?? ""} onChange={(e) => set("lastName", e.target.value)} /></div>
          <div className="col-span-2 space-y-1.5"><Label>Phone number *</Label>
            <Input inputMode="tel" value={f.phone ?? ""} onChange={(e) => set("phone", e.target.value)} placeholder="+91…" /></div>
          <div className="col-span-2 space-y-1.5"><Label>Email</Label>
            <Input type="email" value={f.email ?? ""} onChange={(e) => set("email", e.target.value)} /></div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={m.isPending}>Close</Button>
          <Button onClick={() => m.mutate()} disabled={m.isPending || !f.firstName?.trim() || (f.phone ?? "").length < 10}>
            {m.isPending && <Loader2 className="size-4 animate-spin" />} Confirm
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

/** Coupon code entry + Apply. */
function CouponInput({ onApply, pending, disabled }: { onApply: (code: string) => void; pending: boolean; disabled: boolean }) {
  const [code, setCode] = React.useState("");
  return (
    <div className="flex gap-2">
      <Input placeholder="Add coupon" value={code} onChange={(e) => setCode(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && code.trim()) onApply(code.trim()); }} />
      <Button variant="outline" onClick={() => onApply(code.trim())} disabled={pending || disabled || !code.trim()}>
        {pending ? <Loader2 className="size-4 animate-spin" /> : "Apply"}
      </Button>
    </div>
  );
}

function ReceiptCard({ sale, onClose }: { sale: SaleResp; onClose: () => void }) {
  const queued = sale.paymentStatus === "queued";
  return (
    <Card className="border-primary/40">
      <CardHeader className="flex-row items-center justify-between py-3">
        <CardTitle className="flex items-center gap-2 text-sm"><Receipt className="size-4 text-primary" /> {sale.code}</CardTitle>
        <Button variant="ghost" size="icon" className="size-7" onClick={onClose}><X className="size-4" /></Button>
      </CardHeader>
      <CardContent className="space-y-2 pt-0 text-sm">
        <ul className="divide-y">
          {sale.items.map((i, idx) => (
            // `SaleResp.items` is the receipt snapshot — name only, no product id.
            <li key={idx} className="flex justify-between py-1">
              <span>{i.quantity} × <ProductLink name={i.name} /></span>
              <span>{inr(i.lineTotal, { decimals: true })}</span>
            </li>
          ))}
        </ul>
        <div className="flex justify-between border-t pt-2 font-bold"><span>Total</span><span>{inr(sale.total, { decimals: true })}</span></div>
        {sale.changeDue > 0 && <Row label="Change due" value={inr(sale.changeDue, { decimals: true })} />}
        {sale.creditUsed > 0 && <Row label="On credit" value={inr(sale.creditUsed, { decimals: true })} />}
        <div className="flex items-center gap-2 pt-1">
          <Badge variant="success" className="capitalize">{sale.paymentStatus}</Badge>
          {/* Print straight from the till. A queued (offline) sale has no real
              receipt number yet, so printing one would hand the customer a slip
              that matches nothing — it's offered once the sale has synced. */}
          <Button size="sm" variant="outline" className="ml-auto"
                  disabled={queued}
                  title={queued ? "Available once this sale syncs" : "Print receipt (F10)"}
                  onClick={() => printReceipt()}>
            <Printer className="size-3.5" /> Print <span className="ml-1 text-[10px] opacity-60">F10</span>
          </Button>
        </div>
      </CardContent>
    </Card>
  );
}

function NoSession({ onOpened }: { onOpened: () => void }) {
  const [opening, setOpening] = React.useState("");
  const open = useApiMutation<void>(
    () => api.post("/store/pos/session", { openingCash: Number(opening || 0) }),
    { successMessage: "Till opened", onDone: onOpened }
  );
  return (
    <div className="space-y-5">
      <PageHeader title="Point of Sale" description="Open your till to start billing." />
      <Card className="mx-auto max-w-sm">
        <CardHeader><CardTitle className="text-base">Open till</CardTitle></CardHeader>
        <CardContent className="space-y-3">
          <div className="space-y-1.5">
            <Label>Opening cash float</Label>
            <Input inputMode="numeric" value={opening} onChange={(e) => setOpening(e.target.value)} placeholder="0" />
          </div>
          <Button className="w-full" onClick={() => open.mutate()} disabled={open.isPending}>
            {open.isPending && <Loader2 className="size-4 animate-spin" />} Open till
          </Button>
        </CardContent>
      </Card>
    </div>
  );
}

/** The F-key cheat sheet. A cashier learns these in a day, but only if they can
 *  see them — an undiscoverable shortcut is the same as no shortcut. */
function HotkeyLegend() {
  const keys: [string, string][] = [
    ["F2", "Focus scanner"],
    ["F4", "Cash"],
    ["F6", "Online"],
    ["F7", "Credit"],
    ["F8", "Save draft"],
    ["F9", "Charge"],
    ["F10", "Print last receipt"],
    ["Esc", "Clear sale"],
  ];
  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button variant="outline" size="icon" title="Keyboard shortcuts" aria-label="Keyboard shortcuts">
          <Keyboard className="size-4" />
        </Button>
      </DialogTrigger>
      <DialogContent className="max-w-xs">
        <DialogHeader><DialogTitle>Shortcuts</DialogTitle></DialogHeader>
        <ul className="space-y-1.5 py-1 text-sm">
          {keys.map(([k, label]) => (
            <li key={k} className="flex items-center justify-between">
              <span className="text-muted-foreground">{label}</span>
              <kbd className="rounded border bg-muted px-1.5 py-0.5 font-mono text-xs">{k}</kbd>
            </li>
          ))}
        </ul>
      </DialogContent>
    </Dialog>
  );
}
