"use client";

import * as React from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, KeyRound, Loader2, ShieldCheck, UserPlus } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { useAuth } from "@/lib/auth/auth-context";
import { PageHeader } from "@/components/page-header";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { StatusBadge } from "@/components/status-badge";
import { LoadingState, ErrorState } from "@/components/states";

interface Store { id: string; name: string; code: string }
interface StoreAdmin {
  id: string;
  name: string;
  email: string | null;
  phone: string | null;
  title: string;
  isActive: boolean;
}

export default function StoreAdminPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user } = useAuth();
  const canWrite = user?.role === "superadmin";

  const store = useQuery({ queryKey: ["admin", "store", id], queryFn: () => api.get<Store>(`/admin/stores/${id}`) });
  const admins = useQuery({
    queryKey: ["admin", "store-admins", id],
    queryFn: () => api.get<StoreAdmin[]>(`/admin/stores/${id}/admin`),
  });

  const [email, setEmail] = React.useState("");
  const [name, setName] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [phone, setPhone] = React.useState("");
  const [resetFor, setResetFor] = React.useState<string | null>(null);
  const [resetPw, setResetPw] = React.useState("");

  const onboard = useApiMutation<void>(
    () => api.post(`/admin/stores/${id}/admin`, { email: email.trim(), password, name: name.trim(), phone: phone.trim() }),
    {
      invalidate: [["admin", "store-admins", id]],
      successMessage: "Store admin onboarded. They can now sign in to the Store panel.",
      onDone: () => { setEmail(""); setName(""); setPassword(""); setPhone(""); },
    }
  );

  const reset = useApiMutation<string>(
    (targetEmail) => api.post(`/admin/stores/${id}/admin/reset-password`, { email: targetEmail, password: resetPw }),
    {
      invalidate: [["admin", "store-admins", id]],
      successMessage: "Password reset.",
      onDone: () => { setResetFor(null); setResetPw(""); },
    }
  );

  const canOnboard = email.trim().length > 3 && password.length >= 8;

  if (store.isLoading) return <LoadingState label="Loading store…" />;
  if (store.isError) return <ErrorState message="Failed to load store." onRetry={() => store.refetch()} />;

  return (
    <div className="space-y-6">
      <PageHeader
        title={`Store Admin — ${store.data?.name ?? ""}`}
        description="Manager logins that can sign into the Store panel and run only this store."
        actions={
          <Button variant="outline" onClick={() => router.push("/stores")}>
            <ArrowLeft className="size-4" /> Back to stores
          </Button>
        }
      />

      <div className="grid gap-6 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2 text-base"><ShieldCheck className="size-4" /> Current admins</CardTitle>
          </CardHeader>
          <CardContent>
            {admins.isLoading ? (
              <LoadingState />
            ) : (admins.data?.length ?? 0) === 0 ? (
              <p className="py-6 text-center text-sm text-muted-foreground">No admin onboarded yet for this store.</p>
            ) : (
              <ul className="divide-y">
                {admins.data!.map((a) => (
                  <li key={a.id} className="space-y-2 py-3">
                    <div className="flex items-center justify-between gap-2">
                      <div>
                        <span className="font-medium">{a.name}</span>{" "}
                        <span className="font-mono text-xs text-muted-foreground">{a.email}</span>
                        <p className="text-xs text-muted-foreground">{a.title}{a.phone ? ` · ${a.phone}` : ""}</p>
                      </div>
                      <div className="flex items-center gap-2">
                        <StatusBadge status={a.isActive ? "active" : "inactive"} />
                        {canWrite && a.email && (
                          <Button variant="ghost" size="sm" onClick={() => { setResetFor(resetFor === a.email ? null : a.email); setResetPw(""); }}>
                            <KeyRound className="size-3.5" /> Reset
                          </Button>
                        )}
                      </div>
                    </div>
                    {canWrite && resetFor === a.email && (
                      <div className="flex items-center gap-2 rounded-md bg-muted/40 p-2">
                        <Input type="password" value={resetPw} onChange={(e) => setResetPw(e.target.value)} placeholder="New password (min 8)" className="h-9" />
                        <Button size="sm" disabled={reset.isPending || resetPw.length < 8} onClick={() => a.email && reset.mutate(a.email)}>
                          {reset.isPending && <Loader2 className="size-4 animate-spin" />} Set
                        </Button>
                      </div>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>

        {canWrite && (
          <Card>
            <CardHeader>
              <CardTitle className="flex items-center gap-2 text-base"><UserPlus className="size-4" /> Onboard / re-credential admin</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <p className="text-xs text-muted-foreground">Creates an email + password login bound to a manager membership for this store. Re-using an existing email resets that admin&apos;s password.</p>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Full name"><Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Store Manager" /></Field>
                <Field label="Mobile (optional)"><Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="9XXXXXXXXX" /></Field>
              </div>
              <Field label="Email (login id)"><Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="admin@store.example" /></Field>
              <Field label="Password (min 8 chars)"><Input type="password" value={password} onChange={(e) => setPassword(e.target.value)} placeholder="••••••••" /></Field>
              <div className="flex justify-end pt-1">
                <Button onClick={() => onboard.mutate()} disabled={onboard.isPending || !canOnboard}>
                  {onboard.isPending && <Loader2 className="size-4 animate-spin" />} Onboard admin
                </Button>
              </div>
            </CardContent>
          </Card>
        )}
      </div>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <Label>{label}</Label>
      {children}
    </div>
  );
}
