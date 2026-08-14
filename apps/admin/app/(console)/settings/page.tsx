"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Loader2, Lock } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { useAuth } from "@/lib/auth/auth-context";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { LoadingState, ErrorState } from "@/components/states";

interface Config {
  gstRate: number;
  deliveryFee: number;
  freeDeliveryThreshold: number;
  minOrder: number;
  platformFeeType: string;
  platformFeeValue: number;
  platformFeeCap: number | null;
  creditDefaultLimit: number;
  lateFeeFlat: number;
  lateFeePercent: number;
  minCollectionAmount: number;
  currency: string;
  supportPhone: string;
  supportEmail: string;
  updatedAt?: string;
}

const NUMERIC: (keyof Config)[] = [
  "gstRate",
  "deliveryFee",
  "freeDeliveryThreshold",
  "minOrder",
  "platformFeeValue",
  "platformFeeCap",
  "creditDefaultLimit",
  "lateFeeFlat",
  "lateFeePercent",
  "minCollectionAmount",
];

const SECTIONS: { title: string; fields: { key: keyof Config; label: string }[] }[] = [
  {
    title: "Business",
    fields: [
      { key: "currency", label: "Currency" },
      // The API speaks percentages (18), not fractions. The old "0–1" label is
      // how 0.18-style values got typed in here and into product records.
      { key: "gstRate", label: "GST rate (%) — 0, 0.25, 3, 5, 12, 18 or 28" },
      { key: "supportPhone", label: "Support phone" },
      { key: "supportEmail", label: "Support email" },
    ],
  },
  {
    title: "Delivery & Fees",
    fields: [
      { key: "deliveryFee", label: "Delivery fee (₹)" },
      { key: "freeDeliveryThreshold", label: "Free delivery threshold (₹)" },
      { key: "minOrder", label: "Minimum order (₹)" },
      { key: "platformFeeType", label: "Platform fee type (percent/flat)" },
      { key: "platformFeeValue", label: "Platform fee value" },
      { key: "platformFeeCap", label: "Platform fee cap (₹)" },
    ],
  },
  {
    title: "Credit Rules",
    fields: [
      { key: "creditDefaultLimit", label: "Default credit limit (₹)" },
      { key: "lateFeeFlat", label: "Late fee (flat ₹)" },
      { key: "lateFeePercent", label: "Late fee (%)" },
      // 0 = no floor. Stops an agent being sent across town to collect ₹20,
      // and never blocks a payment that clears the account outright.
      { key: "minCollectionAmount", label: "Minimum cash collection (₹) — 0 for no limit" },
    ],
  },
];

export default function SettingsPage() {
  const { user } = useAuth();
  const canWrite = user?.role === "superadmin";
  const [form, setForm] = React.useState<Partial<Config>>({});

  const query = useQuery({ queryKey: ["admin", "config"], queryFn: () => api.get<Config>("/admin/config") });

  React.useEffect(() => {
    if (query.data) setForm(query.data);
  }, [query.data]);

  const save = useApiMutation((body: Partial<Config>) => api.patch<Config>("/admin/config", body), {
    invalidate: [["admin", "config"]],
    successMessage: "Settings saved.",
  });

  function set(key: keyof Config, value: string) {
    setForm((f) => ({ ...f, [key]: NUMERIC.includes(key) ? (value === "" ? null : Number(value)) : value }));
  }

  function submit() {
    const { updatedAt, ...body } = form;
    void updatedAt;
    save.mutate(body);
  }

  return (
    <>
      <PageHeader
        title="System Settings"
        description="Business, delivery, fee and credit rules."
        actions={
          canWrite ? (
            <Button onClick={submit} disabled={save.isPending}>
              {save.isPending && <Loader2 className="size-4 animate-spin" />}
              Save changes
            </Button>
          ) : (
            <span className="flex items-center gap-1.5 text-xs text-muted-foreground">
              <Lock className="size-3.5" /> Super Admin only
            </span>
          )
        }
      />

      {query.isLoading ? (
        <LoadingState />
      ) : query.isError ? (
        <ErrorState message="Couldn't load settings." onRetry={() => query.refetch()} />
      ) : (
        <div className="grid gap-4 lg:grid-cols-3">
          {SECTIONS.map((section) => (
            <Card key={section.title}>
              <CardHeader>
                <CardTitle>{section.title}</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {section.fields.map((f) => (
                  <div key={f.key} className="space-y-1.5">
                    <Label htmlFor={f.key}>{f.label}</Label>
                    <Input
                      id={f.key}
                      type={NUMERIC.includes(f.key) ? "number" : "text"}
                      value={(form[f.key] ?? "") as string | number}
                      onChange={(e) => set(f.key, e.target.value)}
                      disabled={!canWrite}
                    />
                  </div>
                ))}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
      {form.updatedAt && (
        <p className="text-xs text-muted-foreground">Last updated {new Date(form.updatedAt).toLocaleString("en-IN")}.</p>
      )}
    </>
  );
}
