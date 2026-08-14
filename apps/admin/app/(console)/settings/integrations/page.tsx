"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Check, Copy, Eye, EyeOff, KeyRound, Loader2, Lock } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { useAuth } from "@/lib/auth/auth-context";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Switch } from "@/components/ui/switch";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { LoadingState, ErrorState } from "@/components/states";

/**
 * Every integration credential, shown in clear text.
 *
 * Secrets used to be write-only — the API returned a `<field>Set` boolean and the
 * inputs were always blank, so nobody could read back or verify what was
 * configured. That is deliberately reversed (owner decision, 2026-08-11) so the
 * platform can be handed over with its credentials visible.
 *
 * The page is driven by whatever the server sends rather than a hardcoded field
 * list. The previous version enumerated ~20 fields by hand and silently omitted
 * every KYC and credit-bureau setting, which is how the Payon key ended up with
 * nowhere in the UI to live. Anything the server returns that isn't placed in a
 * group below still renders, under "Other" — a new integration can be missing a
 * nice label, but it can no longer be invisible.
 */

type Scalar = string | number | boolean | null;

interface Payload extends Record<string, unknown> {
  /** snake_case names of the sensitive fields, straight from the backend. */
  secretFields?: string[];
  updatedAt?: string;
}

type FieldKind = "text" | "number" | "bool" | "select" | "long";

interface FieldSpec {
  key: string;
  label: string;
  kind?: FieldKind;
  options?: { value: string; label: string }[];
  placeholder?: string;
  hint?: string;
}

interface GroupSpec {
  title: string;
  note?: string;
  fields: FieldSpec[];
}

/** Server keys arrive camelCased by the envelope renderer; `secretFields` doesn't. */
function toCamel(s: string) {
  return s.replace(/_([a-z0-9])/g, (_, c: string) => c.toUpperCase());
}

const GROUPS: GroupSpec[] = [
  {
    title: "SMS / OTP",
    note:
      "Under TRAI rules the smslogin.co body must match the registered DLT template exactly — only {code} varies.",
    fields: [
      {
        key: "smsProvider",
        label: "SMS provider",
        kind: "select",
        options: [
          { value: "console", label: "Console (log only)" },
          { value: "msg91", label: "MSG91" },
          { value: "smslogin", label: "smslogin.co" },
          { value: "off", label: "Off" },
        ],
      },
      { key: "msg91AuthKey", label: "MSG91 auth key" },
      { key: "msg91TemplateId", label: "MSG91 template id" },
      { key: "smsloginUsername", label: "smslogin username" },
      { key: "smsloginApiKey", label: "smslogin API key" },
      { key: "smsloginSenderId", label: "Sender id", placeholder: "e.g. VSMRTS" },
      { key: "smsloginTemplateId", label: "DLT template id" },
      {
        key: "smsloginOtpMessage",
        label: "OTP message body",
        kind: "long",
        placeholder: "{code} is your VS Mart verification code.",
      },
      {
        key: "otpBypassCode",
        label: "OTP bypass code",
        hint: "Accepted instead of a real OTP. Clear this before going live.",
      },
    ],
  },
  {
    title: "Email (SMTP)",
    fields: [
      { key: "emailHost", label: "Host", placeholder: "smtp.example.com" },
      { key: "emailPort", label: "Port", kind: "number", placeholder: "587" },
      { key: "emailUser", label: "Username" },
      { key: "emailPassword", label: "Password" },
      { key: "emailUseTls", label: "Use TLS", kind: "bool" },
      { key: "emailFrom", label: "From address", placeholder: "no-reply@thevsmart.com" },
    ],
  },
  {
    title: "Payments — Razorpay",
    fields: [
      { key: "razorpayKeyId", label: "Key id", placeholder: "rzp_live_..." },
      { key: "razorpayKeySecret", label: "Key secret" },
      { key: "razorpayWebhookSecret", label: "Webhook secret" },
    ],
  },
  {
    title: "Push — FCM",
    fields: [{ key: "fcmServerKey", label: "Server key" }],
  },
  {
    title: "Maps — Google (server)",
    note: "Server-side APIs only (directions, geocoding). The in-app map key is set at build time.",
    fields: [{ key: "googleMapsKey", label: "Server API key" }],
  },
  {
    title: "Credit bureau & DigiLocker — Payon",
    note:
      "One Payon account serves both the CIBIL score pull and DigiLocker, so the API key below is used by both. Reseller keys must go to reseller.apipayon.in — the bare host rejects a valid key as 'Invalid API key'.",
    fields: [
      {
        key: "creditBureauProvider",
        label: "Provider",
        kind: "select",
        options: [
          { value: "payon", label: "Payon (live)" },
          { value: "mock", label: "Mock" },
        ],
      },
      {
        key: "creditBureauBaseUrl",
        label: "Base URL",
        placeholder: "https://reseller.apipayon.in/api/v1/serv2/check_credit_score.php",
      },
      {
        key: "creditBureauApiKey",
        label: "API key",
        hint: "Also used for DigiLocker. Needs wallet balance on the Payon account.",
      },
    ],
  },
  {
    title: "KYC — provider",
    note:
      "PAN, Aadhaar OTP and bank verification use this selection. Leaving it blank/mock returns FABRICATED 'verified' results — do not ship that. DigiLocker is not affected: it always uses Payon.",
    fields: [
      {
        key: "kycProvider",
        label: "Active provider",
        kind: "select",
        options: [
          { value: "mock", label: "Mock — fabricated results, dev only" },
          { value: "signzy", label: "Signzy" },
          { value: "setu", label: "Setu" },
          { value: "cashfree", label: "Cashfree Secure ID" },
        ],
      },
    ],
  },
  {
    title: "KYC — Signzy",
    fields: [
      { key: "signzyBaseUrl", label: "Base URL" },
      { key: "signzyApiKey", label: "API key" },
      { key: "signzyUsername", label: "Username" },
      { key: "signzyPassword", label: "Password" },
    ],
  },
  {
    title: "KYC — Setu",
    fields: [
      { key: "setuBaseUrl", label: "Base URL" },
      { key: "setuDgBaseUrl", label: "DigiLocker base URL" },
      { key: "setuClientId", label: "Client id" },
      { key: "setuClientSecret", label: "Client secret" },
      { key: "setuPanProductId", label: "PAN product id" },
      { key: "setuDigilockerProductId", label: "DigiLocker product id" },
      { key: "setuAadhaarProductId", label: "Aadhaar product id" },
      { key: "setuBankProductId", label: "Bank product id" },
    ],
  },
  {
    title: "KYC — Cashfree Secure ID",
    note: "Needs the Verification Suite enabled on the account; plain payment-gateway keys won't reach /verification/*.",
    fields: [
      { key: "cashfreeBaseUrl", label: "Base URL" },
      { key: "cashfreeAppId", label: "App id" },
      { key: "cashfreeSecretKey", label: "Secret key" },
      { key: "cashfreeApiVersion", label: "API version" },
    ],
  },
];

/** Keys the page handles itself — anything else the server sends is a real field. */
const NON_FIELD_KEYS = new Set(["secretFields", "updatedAt"]);

function CopyButton({ value }: { value: string }) {
  const [done, setDone] = React.useState(false);
  if (!value) return null;
  return (
    <Button
      type="button"
      variant="ghost"
      size="icon"
      className="size-7 shrink-0"
      aria-label="Copy value"
      onClick={() => {
        void navigator.clipboard.writeText(value).then(() => {
          setDone(true);
          setTimeout(() => setDone(false), 1200);
        });
      }}
    >
      {done ? <Check className="size-3.5 text-emerald-600" /> : <Copy className="size-3.5" />}
    </Button>
  );
}

function FieldRow({
  spec,
  value,
  secret,
  masked,
  onChange,
}: {
  spec: FieldSpec;
  value: Scalar;
  secret: boolean;
  masked: boolean;
  onChange: (v: Scalar) => void;
}) {
  const str = value == null ? "" : String(value);

  if (spec.kind === "bool") {
    return (
      <div className="flex items-center justify-between rounded-md border border-input px-3 py-2">
        <Label htmlFor={spec.key} className="cursor-pointer">
          {spec.label}
        </Label>
        <Switch id={spec.key} checked={!!value} onCheckedChange={(v) => onChange(v)} />
      </div>
    );
  }

  return (
    <div className="space-y-1.5">
      <div className="flex items-center justify-between gap-2">
        <Label htmlFor={spec.key}>{spec.label}</Label>
        {secret ? (
          str ? (
            <Badge variant="success">Configured</Badge>
          ) : (
            <Badge variant="secondary">Not set</Badge>
          )
        ) : null}
      </div>
      <div className="flex items-center gap-1">
        {spec.kind === "select" ? (
          <Select value={str} onValueChange={(v) => onChange(v)}>
            <SelectTrigger id={spec.key} className="flex-1">
              <SelectValue placeholder="Select…" />
            </SelectTrigger>
            <SelectContent>
              {(spec.options ?? []).map((o) => (
                <SelectItem key={o.value} value={o.value}>
                  {o.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        ) : (
          <Input
            id={spec.key}
            className="flex-1 font-mono text-xs"
            // Secrets render readable by default so they can be handed over; the
            // header toggle flips every one at once for screen-sharing.
            type={secret && masked ? "password" : spec.kind === "number" ? "number" : "text"}
            autoComplete="off"
            spellCheck={false}
            placeholder={spec.placeholder}
            value={str}
            onChange={(e) =>
              onChange(spec.kind === "number" ? (e.target.value === "" ? null : Number(e.target.value)) : e.target.value)
            }
          />
        )}
        {spec.kind !== "select" && <CopyButton value={str} />}
      </div>
      {spec.hint && <p className="text-xs text-muted-foreground">{spec.hint}</p>}
    </div>
  );
}

export default function IntegrationsPage() {
  const { user } = useAuth();
  const isSuper = user?.role === "superadmin";

  const query = useQuery({
    queryKey: ["admin", "integrations"],
    queryFn: () => api.get<Payload>("/admin/settings/integrations"),
    enabled: isSuper,
  });

  const [form, setForm] = React.useState<Record<string, Scalar>>({});
  const [masked, setMasked] = React.useState(false);

  React.useEffect(() => {
    if (!query.data) return;
    const next: Record<string, Scalar> = {};
    Object.entries(query.data).forEach(([k, v]) => {
      if (NON_FIELD_KEYS.has(k) || k.endsWith("Set")) return;
      next[k] = (v ?? "") as Scalar;
    });
    setForm(next);
  }, [query.data]);

  const save = useApiMutation(
    (body: Record<string, Scalar>) => api.patch<Payload>("/admin/settings/integrations", body),
    { invalidate: [["admin", "integrations"]], successMessage: "Integrations saved." }
  );

  if (!isSuper) {
    return (
      <>
        <PageHeader title="Integrations" description="Third-party credentials and secrets." />
        <Card>
          <CardContent className="flex flex-col items-center gap-2 py-12 text-center">
            <Lock className="size-6 text-muted-foreground" />
            <p className="text-sm font-medium">Super-admin only</p>
            <p className="text-xs text-muted-foreground">
              You don&apos;t have permission to manage integration secrets.
            </p>
          </CardContent>
        </Card>
      </>
    );
  }

  const secretKeys = new Set((query.data?.secretFields ?? []).map(toCamel));
  const placed = new Set(GROUPS.flatMap((g) => g.fields.map((f) => f.key)));
  // Anything the server knows about that no group claims. Renders generically so
  // a new backend setting is never silently unreachable from the panel.
  const orphans = Object.keys(form)
    .filter((k) => !placed.has(k))
    .sort();

  const groups: GroupSpec[] = orphans.length
    ? [
        ...GROUPS,
        {
          title: "Other",
          note: "Settings the server exposes that this page has no label for yet.",
          fields: orphans.map((k) => ({ key: k, label: k })),
        },
      ]
    : GROUPS;

  return (
    <>
      <PageHeader
        title="Integrations"
        description="Every third-party credential, in clear text. Changes take effect immediately — no redeploy."
        actions={
          <div className="flex items-center gap-2">
            <Button type="button" variant="outline" onClick={() => setMasked((m) => !m)}>
              {masked ? <Eye className="size-4" /> : <EyeOff className="size-4" />}
              {masked ? "Show keys" : "Hide keys"}
            </Button>
            <Button onClick={() => save.mutate(form)} disabled={save.isPending || query.isLoading}>
              {save.isPending ? (
                <Loader2 className="size-4 animate-spin" />
              ) : (
                <KeyRound className="size-4" />
              )}
              Save changes
            </Button>
          </div>
        }
      />

      {query.isLoading ? (
        <LoadingState />
      ) : query.isError ? (
        <ErrorState message="Couldn't load integrations." onRetry={() => query.refetch()} />
      ) : (
        <div className="grid items-start gap-4 lg:grid-cols-2">
          {groups.map((g) => (
            <Card key={g.title}>
              <CardHeader>
                <CardTitle>{g.title}</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                {g.note && <p className="text-xs text-muted-foreground">{g.note}</p>}
                {g.fields
                  // A field the server didn't send doesn't exist — don't offer it.
                  .filter((f) => f.key in form)
                  .map((f) => (
                    <FieldRow
                      key={f.key}
                      spec={f}
                      value={form[f.key]}
                      secret={secretKeys.has(f.key)}
                      masked={masked}
                      onChange={(v) => setForm((s) => ({ ...s, [f.key]: v }))}
                    />
                  ))}
              </CardContent>
            </Card>
          ))}
        </div>
      )}

      {query.data?.updatedAt && (
        <p className="text-xs text-muted-foreground">
          Last updated {new Date(query.data.updatedAt).toLocaleString("en-IN")}.
        </p>
      )}
    </>
  );
}
