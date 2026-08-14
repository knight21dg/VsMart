"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Loader2, Megaphone, Send, Ticket, Users } from "lucide-react";
import { api, useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { RequirePerm } from "@/components/permission-gate";
import { ImageUpload } from "@/components/image-upload";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { useStore } from "@/lib/store/store-context";
import { inr } from "@/lib/utils";

export default function MarketingPage() {
  return (
    <RequirePerm perm="marketing.send">
      <Inner />
    </RequirePerm>
  );
}

function Inner() {
  const { me } = useStore();
  const storeName = me?.store.name;
  const [title, setTitle] = React.useState("");
  const [body, setBody] = React.useState("");
  const [image, setImage] = React.useState<string | null>(null);

  const audience = useQuery({
    queryKey: ["store", "marketing", "audience"],
    queryFn: () => api.get<{ customerCount: number }>("/store/marketing/notify"),
  });
  const count = audience.data?.customerCount ?? 0;

  const send = useApiMutation(
    () => api.post<{ sent: number }>("/store/marketing/notify", { title, body, imageUrl: image || undefined }),
    { successMessage: "Notification sent to your customers", onDone: () => { setTitle(""); setBody(""); setImage(null); } },
  );

  return (
    <div className="space-y-5">
      <PageHeader
        title="Notify Customers"
        description="Send a push notification to your store's customers to bring them back."
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader className="py-3">
            <CardTitle className="flex items-center gap-2 text-sm"><Megaphone className="size-4" /> Compose</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <div className="space-y-1.5"><Label>Title</Label>
              <Input value={title} onChange={(e) => setTitle(e.target.value)} maxLength={65} placeholder="Fresh stock just in! 🥬" /></div>
            <div className="space-y-1.5"><Label>Message</Label>
              <Textarea rows={3} value={body} onChange={(e) => setBody(e.target.value)} maxLength={180} placeholder="Get 20% off on today's fresh arrivals. Order now!" /></div>
            <div className="space-y-1.5"><Label>Image (optional — shown big in the notification)</Label>
              <ImageUpload value={image} onChange={setImage} uploadPath="/store/marketing/image" /></div>

            <div className="flex items-center gap-2 rounded-md border bg-muted/40 px-3 py-2 text-sm text-muted-foreground">
              <Users className="size-4" />
              {audience.isLoading ? "Counting your customers…" : `Reaches ${count} customer${count === 1 ? "" : "s"} of ${storeName ?? "your store"}.`}
            </div>

            <Button className="w-full" onClick={() => send.mutate(undefined)} disabled={send.isPending || !title || count === 0}>
              {send.isPending ? <Loader2 className="size-4 animate-spin" /> : <Send className="size-4" />} Send notification
            </Button>
          </CardContent>
        </Card>

        {/* Live preview of how the push will look on a phone. */}
        <Card>
          <CardHeader className="py-3"><CardTitle className="text-sm">Preview</CardTitle></CardHeader>
          <CardContent>
            <div className="rounded-xl border bg-background p-3 shadow-sm">
              <div className="flex items-start gap-3">
                <div className="grid size-10 shrink-0 place-items-center overflow-hidden rounded-lg bg-primary/10">
                  {image ? (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src={api.assetUrl(image)} alt="" className="size-full object-cover" />
                  ) : (
                    // eslint-disable-next-line @next/next/no-img-element
                    <img src="/vsmart-logo.png" alt="VS Mart" className="size-7 object-contain" />
                  )}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-medium text-muted-foreground">VS Mart</span>
                    <span className="text-xs text-muted-foreground">now</span>
                  </div>
                  <p className="truncate text-sm font-semibold">{title || "Your title appears here"}</p>
                  <p className="line-clamp-2 text-sm text-muted-foreground">{body || "Your message appears here."}</p>
                </div>
              </div>
              {image && (
                <div className="mt-2 overflow-hidden rounded-lg border">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={api.assetUrl(image)} alt="" className="aspect-video w-full object-cover" />
                </div>
              )}
            </div>
            <p className="mt-3 text-xs text-muted-foreground">
              The VS Mart logo shows on every notification. Add an image to make it stand out.
            </p>
          </CardContent>
        </Card>
      </div>

      <ActiveCoupons />
    </div>
  );
}

interface StoreCoupon {
  id: string;
  code: string;
  discountType: string;
  value: number;
  minOrder: number | null;
  maxDiscount: number | null;
  validTo: string | null;
}

/**
 * Live coupon codes, read-only.
 *
 * `/store/marketing/coupons` has always existed but nothing rendered it, so
 * staff had no way to see which codes were running and answer "does VSNEW100
 * still work?" at the counter. Coupons are platform-wide — a code isn't scoped
 * to one store — so this is deliberately a list, not a form: the panel says
 * plainly who owns them instead of offering a Create button that would 403.
 */
function ActiveCoupons() {
  const q = useQuery({
    queryKey: ["store", "marketing", "coupons"],
    queryFn: () => api.get<StoreCoupon[]>("/store/marketing/coupons"),
  });
  const rows = q.data ?? [];

  const describe = (c: StoreCoupon) =>
    c.discountType === "percent" ? `${c.value}% off` : `${inr(c.value)} off`;

  return (
    <Card>
      <CardHeader className="py-3">
        <CardTitle className="flex items-center gap-2 text-sm">
          <Ticket className="size-4" /> Active coupon codes
        </CardTitle>
      </CardHeader>
      <CardContent>
        {q.isLoading ? (
          <p className="py-6 text-center text-sm text-muted-foreground">Loading coupons…</p>
        ) : q.isError ? (
          <div className="py-6 text-center text-sm">
            <p className="text-muted-foreground">Couldn&apos;t load coupons.</p>
            <Button variant="outline" size="sm" className="mt-2" onClick={() => q.refetch()}>
              Retry
            </Button>
          </div>
        ) : rows.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">
            No coupon codes are running right now.
          </p>
        ) : (
          <ul className="divide-y text-sm">
            {rows.map((c) => (
              <li key={c.id} className="flex flex-wrap items-center justify-between gap-2 py-2">
                <span className="font-mono font-semibold">{c.code}</span>
                <span className="text-muted-foreground">
                  {describe(c)}
                  {c.minOrder ? ` · min ${inr(c.minOrder)}` : ""}
                  {c.maxDiscount ? ` · max ${inr(c.maxDiscount)}` : ""}
                  {c.validTo ? ` · till ${new Date(c.validTo).toLocaleDateString()}` : ""}
                </span>
              </li>
            ))}
          </ul>
        )}
        <p className="mt-3 text-xs text-muted-foreground">
          Coupon codes apply across every VS Mart store, so they&apos;re created and
          withdrawn centrally by head office. Quote these to customers at the counter.
        </p>
      </CardContent>
    </Card>
  );
}
