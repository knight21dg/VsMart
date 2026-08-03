"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Loader2, Snowflake, SlidersHorizontal } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { StatCard } from "@/components/stat-card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { StatusBadge } from "@/components/status-badge";
import { LoadingState, ErrorState } from "@/components/states";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { inr, fmtDate } from "@/lib/utils";
import type { Customer360 } from "./types";
import {
  Field,
  OverviewTab,
  CreditTab,
  OrdersTab,
  CollectionsTab,
  KycTab,
  NetworkTab,
  SupportTab,
  TimelineTab,
  NotesTab,
} from "./sections";

const TABS = [
  "Overview",
  "Credit",
  "Orders",
  "Collections",
  "KYC",
  "Network",
  "Support",
  "Timeline",
  "Notes",
] as const;

export default function Customer360Page() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [limitOpen, setLimitOpen] = React.useState(false);
  const [ticketOpen, setTicketOpen] = React.useState(false);
  const [limit, setLimit] = React.useState("");
  const [ticketSubject, setTicketSubject] = React.useState("");
  // Freeze-credit and suspend cut the customer off immediately, so they get a
  // confirm step. Their restorative counterparts (unfreeze/reactivate) don't.
  const [confirm, setConfirm] = React.useState<
    { title: string; description: string; confirmLabel: string; action: string } | null
  >(null);

  const query = useQuery({
    queryKey: ["admin", "crm", id],
    queryFn: () => api.get<Customer360>(`/admin/crm/customers/${id}`),
  });
  const c = query.data;
  const invalidate = [["admin", "crm", id]];

  const action = useApiMutation(
    (vars: Record<string, unknown>) => api.post(`/admin/crm/customers/${id}/actions`, vars),
    { invalidate, successMessage: "Done.", onDone: () => setConfirm(null) }
  );
  const addNote = useApiMutation(
    (vars: { body: string; category: string }) => api.post(`/admin/crm/customers/${id}/notes`, vars),
    { invalidate, successMessage: "Note added." }
  );

  const creditFrozen = c?.creditIntelligence?.status === "frozen";
  const suspended = c?.header?.status === "suspended";

  return (
    <>
      <Button variant="ghost" size="sm" className="-ml-2 w-fit" onClick={() => router.back()}>
        <ArrowLeft /> Back
      </Button>

      {query.isLoading ? (
        <LoadingState />
      ) : query.isError || !c ? (
        <ErrorState message="Couldn't load this customer." onRetry={() => query.refetch()} />
      ) : (
        <>
          <PageHeader
            title={c.header.name || c.header.phone}
            description={`${c.header.vsId} · ${c.header.phone}`}
            actions={
              <div className="flex flex-wrap gap-2">
                <Button variant="outline" onClick={() => { setLimit(String(c.creditIntelligence.creditLimit ?? "")); setLimitOpen(true); }}>
                  <SlidersHorizontal /> Adjust Limit
                </Button>
                <Button
                  variant={creditFrozen ? "default" : "destructive"}
                  onClick={() =>
                    creditFrozen
                      ? action.mutate({ action: "unfreeze_credit" })
                      : setConfirm({
                          title: `Freeze credit for ${c.header.name || c.header.phone}?`,
                          description:
                            `They lose VS Credit at checkout straight away — the app will only offer prepaid and COD. ` +
                            `Their outstanding ${inr(c.health.outstanding)} stays due and collections carry on. ` +
                            `You can unfreeze from this page.`,
                          confirmLabel: "Freeze credit",
                          action: "freeze_credit",
                        })
                  }
                  disabled={action.isPending}
                >
                  {action.isPending ? <Loader2 className="animate-spin" /> : <Snowflake />}
                  {creditFrozen ? "Unfreeze" : "Freeze Credit"}
                </Button>
                <Button
                  variant="outline"
                  onClick={() =>
                    suspended
                      ? action.mutate({ action: "reactivate" })
                      : setConfirm({
                          title: `Suspend ${c.header.name || c.header.phone}?`,
                          description:
                            `The account is blocked immediately: no new orders, no credit, and the app shows an ` +
                            `account-suspended screen on next open. Their outstanding ${inr(c.health.outstanding)} ` +
                            `remains due. Reactivate from this page.`,
                          confirmLabel: "Suspend account",
                          action: "suspend",
                        })
                  }
                  disabled={action.isPending}
                >
                  {suspended ? "Reactivate" : "Suspend"}
                </Button>
                <Button variant="outline" onClick={() => action.mutate({ action: "assign_collection" })} disabled={action.isPending}>
                  Assign Collection
                </Button>
                <Button variant="outline" onClick={() => setTicketOpen(true)}>
                  Create Ticket
                </Button>
              </div>
            }
          />

          {/* Executive header strip */}
          <div className="grid grid-cols-2 gap-4 rounded-xl border bg-card p-5 sm:grid-cols-4 lg:grid-cols-6">
            <Field label="Zone">{c.header.zone ?? "—"}</Field>
            <Field label="Store">{c.header.store ?? "—"}</Field>
            <Field label="Customer Since">{fmtDate(c.header.customerSince)}</Field>
            <Field label="Collection Agent">{c.header.collectionAgent ?? "—"}</Field>
            <Field label="Status"><StatusBadge status={c.header.status} /></Field>
            <Field label="Risk"><StatusBadge status={c.header.risk} /></Field>
          </div>

          {/* Executive KPI row */}
          <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
            <StatCard label="Lifetime Revenue" value={inr(c.health.lifetimeRevenue)} accent="green" />
            <StatCard label="Total Orders" value={c.health.orders} />
            <StatCard label="Outstanding" value={inr(c.health.outstanding)} accent="gold" />
            <StatCard label="Available Credit" value={inr(c.creditIntelligence.availableCredit ?? 0)} />
            <StatCard
              label="Collection Efficiency"
              value={c.health.collectionEfficiency == null ? "—" : `${c.health.collectionEfficiency}%`}
              accent="green"
            />
            <StatCard label="VS Score" value={c.health.vsScore ?? "—"} />
            <StatCard label="Monthly Spend" value={inr(c.orderAnalytics.monthlySpend)} />
            <StatCard
              label="Recovery Probability"
              value={`${Math.round((c.financialExposure.recoveryProbability ?? 0) * 100)}%`}
              accent={c.header.risk === "low" ? "green" : c.header.risk === "medium" ? "gold" : "red"}
            />
          </div>

          {/* Tabbed workspace */}
          <Tabs defaultValue="Overview" className="mt-2">
            <TabsList className="flex-wrap">
              {TABS.map((t) => (
                <TabsTrigger key={t} value={t}>{t}</TabsTrigger>
              ))}
            </TabsList>
            <TabsContent value="Overview"><OverviewTab data={c} /></TabsContent>
            <TabsContent value="Credit"><CreditTab credit={c.creditIntelligence} customerId={id} /></TabsContent>
            <TabsContent value="Orders"><OrdersTab orders={c.orderAnalytics} /></TabsContent>
            <TabsContent value="Collections"><CollectionsTab col={c.collectionAnalytics} /></TabsContent>
            <TabsContent value="KYC"><KycTab v={c.verification} /></TabsContent>
            <TabsContent value="Network"><NetworkTab net={c.network} /></TabsContent>
            <TabsContent value="Support"><SupportTab s={c.support} /></TabsContent>
            <TabsContent value="Timeline"><TimelineTab events={c.timeline} /></TabsContent>
            <TabsContent value="Notes">
              <NotesTab
                notes={c.notes}
                adding={addNote.isPending}
                onAdd={(category, body) => addNote.mutate({ body, category })}
              />
            </TabsContent>
          </Tabs>
        </>
      )}

      {/* Adjust limit dialog */}
      <Dialog open={limitOpen} onOpenChange={setLimitOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Adjust Credit Limit</DialogTitle>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label htmlFor="limit">New credit limit (₹)</Label>
            <Input id="limit" type="number" min={0} value={limit} onChange={(e) => setLimit(e.target.value)} />
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setLimitOpen(false)} disabled={action.isPending}>Cancel</Button>
            <Button
              onClick={() => action.mutate({ action: "set_limit", limit: Number(limit || 0) }, { onSuccess: () => setLimitOpen(false) })}
              disabled={action.isPending}
            >
              {action.isPending && <Loader2 className="size-4 animate-spin" />} Save
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Create ticket dialog */}
      <Dialog open={ticketOpen} onOpenChange={setTicketOpen}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Create Support Ticket</DialogTitle>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label htmlFor="subject">Subject</Label>
            <Input id="subject" value={ticketSubject} onChange={(e) => setTicketSubject(e.target.value)} placeholder="Overdue follow-up" />
          </div>
          <DialogFooter className="gap-2">
            <Button variant="outline" onClick={() => setTicketOpen(false)} disabled={action.isPending}>Cancel</Button>
            <Button
              onClick={() => action.mutate(
                { action: "create_support_ticket", subject: ticketSubject || "Opened by admin" },
                { onSuccess: () => { setTicketOpen(false); setTicketSubject(""); } }
              )}
              disabled={action.isPending}
            >
              {action.isPending && <Loader2 className="size-4 animate-spin" />} Create
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {confirm && (
        <ConfirmDialog
          open
          onOpenChange={(o) => !o && setConfirm(null)}
          title={confirm.title}
          description={confirm.description}
          confirmLabel={confirm.confirmLabel}
          destructive
          loading={action.isPending}
          onConfirm={() => action.mutate({ action: confirm.action })}
        />
      )}
    </>
  );
}
