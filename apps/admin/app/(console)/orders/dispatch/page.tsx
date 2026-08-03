"use client";

import * as React from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Loader2 } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { LoadingState, ErrorState } from "@/components/states";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { inr } from "@/lib/utils";

interface QOrder {
  code: string;
  customer: string | null;
  items: number;
  value: number;
  agent: string | null;
}
interface Queues {
  toPack: QOrder[];
  packed: QOrder[];
  readyForDispatch: QOrder[];
  outForDelivery: QOrder[];
  counts: { toPack: number; packed: number; readyForDispatch: number; outForDelivery: number };
}
interface LiveAgent { id: string; name: string; onDuty: boolean }

export default function DispatchBoardPage() {
  const router = useRouter();
  const [picked, setPicked] = React.useState<Record<string, string>>({});

  const queues = useQuery({
    queryKey: ["admin", "orders", "queues"],
    queryFn: () => api.get<Queues>("/admin/orders/queues"),
    refetchInterval: 20000,
  });
  const live = useQuery({
    queryKey: ["admin", "ops", "live"],
    queryFn: () => api.get<{ agents: LiveAgent[] }>("/admin/ops/live"),
  });
  const agents = (live.data?.agents ?? []).slice().sort((a, b) => Number(b.onDuty) - Number(a.onDuty));

  const invalidate = [["admin", "orders", "queues"]];
  const setStatus = useApiMutation(
    (v: { code: string; status: string }) => api.post(`/admin/orders/${v.code}/status`, { status: v.status }),
    { invalidate, successMessage: "Order updated." }
  );
  const dispatch = useApiMutation(
    async (v: { code: string; agentId: string }) => {
      await api.post(`/admin/orders/${v.code}/assign-agent`, { agentId: v.agentId });
      return api.post(`/admin/orders/${v.code}/status`, { status: "out_for_delivery" });
    },
    { invalidate, successMessage: "Dispatched." }
  );

  const q = queues.data;
  const busy = setStatus.isPending || dispatch.isPending;

  return (
    <>
      <Button variant="ghost" size="sm" className="-ml-2 w-fit" onClick={() => router.push("/orders")}>
        <ArrowLeft /> Orders
      </Button>
      <PageHeader title="Packing & Dispatch" description="Live store-ops board — pack, ready, and dispatch orders." />

      {queues.isLoading ? (
        <LoadingState />
      ) : queues.isError || !q ? (
        <ErrorState message="Couldn't load the board." onRetry={() => queues.refetch()} />
      ) : (
        <div className="grid gap-4 lg:grid-cols-4">
          <Column title="To Pack" count={q.counts.toPack} accent="gold">
            {q.toPack.map((o) => (
              <OrderCard key={o.code} o={o} onOpen={() => router.push(`/orders/${o.code}`)}>
                <Button size="sm" className="w-full" disabled={busy} onClick={() => setStatus.mutate({ code: o.code, status: "packed" })}>
                  Mark Packed
                </Button>
              </OrderCard>
            ))}
          </Column>

          <Column title="Packed" count={q.counts.packed} accent="teal">
            {q.packed.map((o) => (
              <OrderCard key={o.code} o={o} onOpen={() => router.push(`/orders/${o.code}`)}>
                <Button size="sm" variant="outline" className="w-full" disabled={busy} onClick={() => setStatus.mutate({ code: o.code, status: "ready_for_dispatch" })}>
                  Ready for Dispatch
                </Button>
              </OrderCard>
            ))}
          </Column>

          <Column title="Ready for Dispatch" count={q.counts.readyForDispatch} accent="teal">
            {q.readyForDispatch.map((o) => (
              <OrderCard key={o.code} o={o} onOpen={() => router.push(`/orders/${o.code}`)}>
                <div className="space-y-1.5">
                  <Select value={picked[o.code] ?? ""} onValueChange={(v) => setPicked((p) => ({ ...p, [o.code]: v }))}>
                    <SelectTrigger className="h-8 w-full text-xs"><SelectValue placeholder="Assign agent…" /></SelectTrigger>
                    <SelectContent>
                      {agents.map((a) => (
                        <SelectItem key={a.id} value={a.id}>{a.name}{a.onDuty ? " · on duty" : ""}</SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  <Button
                    size="sm"
                    className="w-full"
                    disabled={busy || !picked[o.code]}
                    onClick={() => dispatch.mutate({ code: o.code, agentId: picked[o.code] })}
                  >
                    {dispatch.isPending ? <Loader2 className="size-4 animate-spin" /> : null} Dispatch
                  </Button>
                </div>
              </OrderCard>
            ))}
          </Column>

          <Column title="Out for Delivery" count={q.counts.outForDelivery} accent="green">
            {q.outForDelivery.map((o) => (
              <OrderCard key={o.code} o={o} onOpen={() => router.push(`/orders/${o.code}`)}>
                {/* No "Delivered" button — only the agent's own OTP + photo
                    verification can complete a delivery; the backend rejects
                    this status from any panel now. */}
                <span className="text-xs text-muted-foreground">
                  With {o.agent ?? "an unassigned agent"} — they complete it
                </span>
              </OrderCard>
            ))}
          </Column>
        </div>
      )}
    </>
  );
}

function Column({ title, count, accent, children }: { title: string; count: number; accent: "gold" | "teal" | "green"; children: React.ReactNode }) {
  const dot = { gold: "bg-[var(--color-warning)]", teal: "bg-primary", green: "bg-[var(--color-success)]" }[accent];
  const empty = React.Children.count(children) === 0;
  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2">
        <span className={"size-2 rounded-full " + dot} />
        <h3 className="text-sm font-semibold">{title}</h3>
        <span className="ml-auto rounded-full bg-muted px-2 py-0.5 text-xs font-medium tabular-nums">{count}</span>
      </div>
      <div className="space-y-2">
        {empty ? <p className="rounded-lg border border-dashed py-8 text-center text-xs text-muted-foreground">Empty</p> : children}
      </div>
    </div>
  );
}

function OrderCard({ o, onOpen, children }: { o: QOrder; onOpen: () => void; children: React.ReactNode }) {
  return (
    <div className="rounded-lg border bg-card p-3 shadow-sm">
      <button className="mb-2 block w-full text-left" onClick={onOpen}>
        <p className="font-mono text-xs font-medium">{o.code}</p>
        <p className="truncate text-sm">{o.customer || "—"}</p>
        <p className="text-xs text-muted-foreground">{o.items} item{o.items === 1 ? "" : "s"} · {inr(o.value)}</p>
      </button>
      {children}
    </div>
  );
}
