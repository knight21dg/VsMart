"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { KeyRound, Loader2, Lock } from "lucide-react";
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

/** Server-returned integration settings. Secrets are NEVER returned — only *Set flags. */
interface Integrations {
  smsProvider: string;
  msg91TemplateId: string;
  msg91AuthKeySet: boolean;
  smsloginUsername: string;
  smsloginSenderId: string;
  smsloginTemplateId: string;
  smsloginOtpMessage: string;
  smsloginApiKeySet: boolean;
  otpBypassCodeSet: boolean;
  emailHost: string;
  emailPort: number | null;
  emailUser: string;
  emailUseTls: boolean;
  emailFrom: string;
  emailPasswordSet: boolean;
  razorpayKeyId: string;
  razorpayKeySecretSet: boolean;
  razorpayWebhookSecretSet: boolean;
  fcmServerKeySet: boolean;
  googleMapsKeySet: boolean;
  updatedAt?: string;
}

/** PATCH body — every field optional; secrets only sent when newly typed. */
interface IntegrationsPatch {
  smsProvider?: string;
  msg91AuthKey?: string;
  msg91TemplateId?: string;
  smsloginUsername?: string;
  smsloginApiKey?: string;
  smsloginSenderId?: string;
  smsloginTemplateId?: string;
  smsloginOtpMessage?: string;
  otpBypassCode?: string;
  emailHost?: string;
  emailPort?: number | null;
  emailUser?: string;
  emailPassword?: string;
  emailUseTls?: boolean;
  emailFrom?: string;
  razorpayKeyId?: string;
  razorpayKeySecret?: string;
  razorpayWebhookSecret?: string;
  fcmServerKey?: string;
  googleMapsKey?: string;
}

/** Non-secret editable fields tracked in form state. */
interface PlainForm {
  smsProvider: string;
  msg91TemplateId: string;
  smsloginUsername: string;
  smsloginSenderId: string;
  smsloginTemplateId: string;
  smsloginOtpMessage: string;
  emailHost: string;
  emailPort: string;
  emailUser: string;
  emailUseTls: boolean;
  emailFrom: string;
  razorpayKeyId: string;
}

const EMPTY_PLAIN: PlainForm = {
  smsProvider: "console",
  msg91TemplateId: "",
  smsloginUsername: "",
  smsloginSenderId: "",
  smsloginTemplateId: "",
  smsloginOtpMessage: "",
  emailHost: "",
  emailPort: "",
  emailUser: "",
  emailUseTls: true,
  emailFrom: "",
  razorpayKeyId: "",
};

/** Secret inputs — keyed by their PATCH field name. Only sent if non-empty. */
type SecretKey =
  | "msg91AuthKey"
  | "smsloginApiKey"
  | "otpBypassCode"
  | "emailPassword"
  | "razorpayKeySecret"
  | "razorpayWebhookSecret"
  | "fcmServerKey"
  | "googleMapsKey";

const SECRET_PLACEHOLDER = "Leave blank to keep current";

function StatusChip({ configured }: { configured: boolean }) {
  return configured ? (
    <Badge variant="success">Configured</Badge>
  ) : (
    <Badge variant="secondary">Not set</Badge>
  );
}

export default function IntegrationsPage() {
  const { user } = useAuth();
  const isSuper = user?.role === "superadmin";

  const query = useQuery({
    queryKey: ["admin", "integrations"],
    queryFn: () => api.get<Integrations>("/admin/settings/integrations"),
    enabled: isSuper,
  });

  const [plain, setPlain] = React.useState<PlainForm>(EMPTY_PLAIN);
  const [secrets, setSecrets] = React.useState<Record<SecretKey, string>>({
    msg91AuthKey: "",
    smsloginApiKey: "",
    otpBypassCode: "",
    emailPassword: "",
    razorpayKeySecret: "",
    razorpayWebhookSecret: "",
    fcmServerKey: "",
    googleMapsKey: "",
  });

  React.useEffect(() => {
    if (!query.data) return;
    const d = query.data;
    setPlain({
      smsProvider: d.smsProvider || "console",
      msg91TemplateId: d.msg91TemplateId ?? "",
      smsloginUsername: d.smsloginUsername ?? "",
      smsloginSenderId: d.smsloginSenderId ?? "",
      smsloginTemplateId: d.smsloginTemplateId ?? "",
      smsloginOtpMessage: d.smsloginOtpMessage ?? "",
      emailHost: d.emailHost ?? "",
      emailPort: d.emailPort == null ? "" : String(d.emailPort),
      emailUser: d.emailUser ?? "",
      emailUseTls: !!d.emailUseTls,
      emailFrom: d.emailFrom ?? "",
      razorpayKeyId: d.razorpayKeyId ?? "",
    });
  }, [query.data]);

  const save = useApiMutation(
    (body: IntegrationsPatch) => api.patch<Integrations>("/admin/settings/integrations", body),
    {
      invalidate: [["admin", "integrations"]],
      successMessage: "Integrations saved.",
      onDone: () =>
        // Clear secret inputs after a successful save — they were write-only.
        setSecrets({
          msg91AuthKey: "",
          smsloginApiKey: "",
          otpBypassCode: "",
          emailPassword: "",
          razorpayKeySecret: "",
          razorpayWebhookSecret: "",
          fcmServerKey: "",
          googleMapsKey: "",
        }),
    }
  );

  function setSecret(key: SecretKey, value: string) {
    setSecrets((s) => ({ ...s, [key]: value }));
  }

  function submit() {
    const body: IntegrationsPatch = {
      smsProvider: plain.smsProvider,
      msg91TemplateId: plain.msg91TemplateId,
      smsloginUsername: plain.smsloginUsername,
      smsloginSenderId: plain.smsloginSenderId,
      smsloginTemplateId: plain.smsloginTemplateId,
      smsloginOtpMessage: plain.smsloginOtpMessage,
      emailHost: plain.emailHost,
      emailPort: plain.emailPort === "" ? null : Number(plain.emailPort),
      emailUser: plain.emailUser,
      emailUseTls: plain.emailUseTls,
      emailFrom: plain.emailFrom,
      razorpayKeyId: plain.razorpayKeyId,
    };
    // Only include secrets the user actually typed — blank means "keep current".
    (Object.keys(secrets) as SecretKey[]).forEach((k) => {
      const v = secrets[k].trim();
      if (v) body[k] = v;
    });
    save.mutate(body);
  }

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

  const d = query.data;

  return (
    <>
      <PageHeader
        title="Integrations"
        description="SMS, email, payment and push credentials. Secrets are write-only — they're never shown."
        actions={
          <Button onClick={submit} disabled={save.isPending || query.isLoading}>
            {save.isPending ? <Loader2 className="size-4 animate-spin" /> : <KeyRound className="size-4" />}
            Save changes
          </Button>
        }
      />

      {query.isLoading ? (
        <LoadingState />
      ) : query.isError ? (
        <ErrorState message="Couldn't load integrations." onRetry={() => query.refetch()} />
      ) : (
        <div className="grid gap-4 lg:grid-cols-2">
          {/* SMS / OTP */}
          <Card>
            <CardHeader>
              <CardTitle>SMS / OTP</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="space-y-1.5">
                <Label htmlFor="smsProvider">SMS provider</Label>
                <Select
                  value={plain.smsProvider}
                  onValueChange={(v) => setPlain((f) => ({ ...f, smsProvider: v }))}
                >
                  <SelectTrigger id="smsProvider">
                    <SelectValue placeholder="Select a provider" />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="console">Console (log only)</SelectItem>
                    <SelectItem value="msg91">MSG91</SelectItem>
                    <SelectItem value="smslogin">smslogin.co</SelectItem>
                    <SelectItem value="off">Off</SelectItem>
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <Label htmlFor="msg91AuthKey">MSG91 auth key</Label>
                  <StatusChip configured={!!d?.msg91AuthKeySet} />
                </div>
                <Input
                  id="msg91AuthKey"
                  type="password"
                  autoComplete="off"
                  placeholder={SECRET_PLACEHOLDER}
                  value={secrets.msg91AuthKey}
                  onChange={(e) => setSecret("msg91AuthKey", e.target.value)}
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="msg91TemplateId">MSG91 template id</Label>
                <Input
                  id="msg91TemplateId"
                  value={plain.msg91TemplateId}
                  onChange={(e) => setPlain((f) => ({ ...f, msg91TemplateId: e.target.value }))}
                />
              </div>

              {plain.smsProvider === "smslogin" && (
                <div className="space-y-3 rounded-lg border bg-muted/30 p-3">
                  <p className="text-xs text-muted-foreground">
                    smslogin.co takes the full message body plus a DLT template id.
                    Under TRAI rules the body must match the registered template
                    exactly — only <code className="font-mono">{"{code}"}</code> varies.
                    Sender id and template id are both required; without them the
                    gateway rejects every send.
                  </p>

                  <div className="space-y-1.5">
                    <Label htmlFor="smsloginUsername">Username</Label>
                    <Input
                      id="smsloginUsername"
                      value={plain.smsloginUsername}
                      onChange={(e) => setPlain((f) => ({ ...f, smsloginUsername: e.target.value }))}
                    />
                  </div>

                  <div className="space-y-1.5">
                    <div className="flex items-center justify-between">
                      <Label htmlFor="smsloginApiKey">API key</Label>
                      <StatusChip configured={!!d?.smsloginApiKeySet} />
                    </div>
                    <Input
                      id="smsloginApiKey"
                      type="password"
                      autoComplete="off"
                      placeholder={SECRET_PLACEHOLDER}
                      value={secrets.smsloginApiKey}
                      onChange={(e) => setSecret("smsloginApiKey", e.target.value)}
                    />
                  </div>

                  <div className="grid gap-3 sm:grid-cols-2">
                    <div className="space-y-1.5">
                      <Label htmlFor="smsloginSenderId">Sender id</Label>
                      <Input
                        id="smsloginSenderId"
                        value={plain.smsloginSenderId}
                        onChange={(e) => setPlain((f) => ({ ...f, smsloginSenderId: e.target.value }))}
                        placeholder="e.g. VSMART"
                      />
                    </div>
                    <div className="space-y-1.5">
                      <Label htmlFor="smsloginTemplateId">DLT template id</Label>
                      <Input
                        id="smsloginTemplateId"
                        value={plain.smsloginTemplateId}
                        onChange={(e) => setPlain((f) => ({ ...f, smsloginTemplateId: e.target.value }))}
                      />
                    </div>
                  </div>

                  <div className="space-y-1.5">
                    <Label htmlFor="smsloginOtpMessage">OTP message body</Label>
                    <Input
                      id="smsloginOtpMessage"
                      value={plain.smsloginOtpMessage}
                      onChange={(e) => setPlain((f) => ({ ...f, smsloginOtpMessage: e.target.value }))}
                      placeholder="{code} is your VS Mart verification code."
                    />
                  </div>
                </div>
              )}

              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <Label htmlFor="otpBypassCode">OTP bypass code</Label>
                  <StatusChip configured={!!d?.otpBypassCodeSet} />
                </div>
                <Input
                  id="otpBypassCode"
                  type="password"
                  autoComplete="off"
                  placeholder={SECRET_PLACEHOLDER}
                  value={secrets.otpBypassCode}
                  onChange={(e) => setSecret("otpBypassCode", e.target.value)}
                />
              </div>
            </CardContent>
          </Card>

          {/* Email (SMTP) */}
          <Card>
            <CardHeader>
              <CardTitle>Email (SMTP)</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="space-y-1.5">
                <Label htmlFor="emailHost">Host</Label>
                <Input
                  id="emailHost"
                  placeholder="smtp.example.com"
                  value={plain.emailHost}
                  onChange={(e) => setPlain((f) => ({ ...f, emailHost: e.target.value }))}
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="emailPort">Port</Label>
                <Input
                  id="emailPort"
                  type="number"
                  placeholder="587"
                  value={plain.emailPort}
                  onChange={(e) => setPlain((f) => ({ ...f, emailPort: e.target.value }))}
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="emailUser">Username</Label>
                <Input
                  id="emailUser"
                  autoComplete="off"
                  value={plain.emailUser}
                  onChange={(e) => setPlain((f) => ({ ...f, emailUser: e.target.value }))}
                />
              </div>

              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <Label htmlFor="emailPassword">Password</Label>
                  <StatusChip configured={!!d?.emailPasswordSet} />
                </div>
                <Input
                  id="emailPassword"
                  type="password"
                  autoComplete="off"
                  placeholder={SECRET_PLACEHOLDER}
                  value={secrets.emailPassword}
                  onChange={(e) => setSecret("emailPassword", e.target.value)}
                />
              </div>

              <div className="flex items-center justify-between rounded-md border border-input px-3 py-2">
                <Label htmlFor="emailUseTls" className="cursor-pointer">
                  Use TLS
                </Label>
                <Switch
                  id="emailUseTls"
                  checked={plain.emailUseTls}
                  onCheckedChange={(v) => setPlain((f) => ({ ...f, emailUseTls: v }))}
                />
              </div>

              <div className="space-y-1.5">
                <Label htmlFor="emailFrom">From address</Label>
                <Input
                  id="emailFrom"
                  type="email"
                  placeholder="no-reply@thevsmart.com"
                  value={plain.emailFrom}
                  onChange={(e) => setPlain((f) => ({ ...f, emailFrom: e.target.value }))}
                />
              </div>
            </CardContent>
          </Card>

          {/* Payments — Razorpay */}
          <Card>
            <CardHeader>
              <CardTitle>Payments — Razorpay</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="space-y-1.5">
                <Label htmlFor="razorpayKeyId">Key id</Label>
                <Input
                  id="razorpayKeyId"
                  autoComplete="off"
                  placeholder="rzp_live_..."
                  value={plain.razorpayKeyId}
                  onChange={(e) => setPlain((f) => ({ ...f, razorpayKeyId: e.target.value }))}
                />
              </div>

              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <Label htmlFor="razorpayKeySecret">Key secret</Label>
                  <StatusChip configured={!!d?.razorpayKeySecretSet} />
                </div>
                <Input
                  id="razorpayKeySecret"
                  type="password"
                  autoComplete="off"
                  placeholder={SECRET_PLACEHOLDER}
                  value={secrets.razorpayKeySecret}
                  onChange={(e) => setSecret("razorpayKeySecret", e.target.value)}
                />
              </div>

              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <Label htmlFor="razorpayWebhookSecret">Webhook secret</Label>
                  <StatusChip configured={!!d?.razorpayWebhookSecretSet} />
                </div>
                <Input
                  id="razorpayWebhookSecret"
                  type="password"
                  autoComplete="off"
                  placeholder={SECRET_PLACEHOLDER}
                  value={secrets.razorpayWebhookSecret}
                  onChange={(e) => setSecret("razorpayWebhookSecret", e.target.value)}
                />
              </div>
            </CardContent>
          </Card>

          {/* Push — FCM */}
          <Card>
            <CardHeader>
              <CardTitle>Push — FCM</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <Label htmlFor="fcmServerKey">Server key</Label>
                  <StatusChip configured={!!d?.fcmServerKeySet} />
                </div>
                <Input
                  id="fcmServerKey"
                  type="password"
                  autoComplete="off"
                  placeholder={SECRET_PLACEHOLDER}
                  value={secrets.fcmServerKey}
                  onChange={(e) => setSecret("fcmServerKey", e.target.value)}
                />
              </div>
            </CardContent>
          </Card>

          {/* Maps — Google (server-side) */}
          <Card>
            <CardHeader>
              <CardTitle>Maps — Google (server)</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              <div className="space-y-1.5">
                <div className="flex items-center justify-between">
                  <Label htmlFor="googleMapsKey">Server API key</Label>
                  <StatusChip configured={!!d?.googleMapsKeySet} />
                </div>
                <Input
                  id="googleMapsKey"
                  type="password"
                  autoComplete="off"
                  placeholder={SECRET_PLACEHOLDER}
                  value={secrets.googleMapsKey}
                  onChange={(e) => setSecret("googleMapsKey", e.target.value)}
                />
                <p className="text-xs text-muted-foreground">
                  Server-side Google APIs (directions, geocoding). The in-app map key is set at build time.
                </p>
              </div>
            </CardContent>
          </Card>
        </div>
      )}

      {d?.updatedAt && (
        <p className="text-xs text-muted-foreground">
          Last updated {new Date(d.updatedAt).toLocaleString("en-IN")}.
        </p>
      )}
    </>
  );
}
