"use client";

import * as React from "react";
import { ImageOff, Loader2 } from "lucide-react";
import { API_BASE } from "@/lib/api/client";
import { getAccessToken } from "@/lib/auth/session";
import { cn } from "@/lib/utils";

/**
 * Renders a private, auth-gated image (e.g. field-verification evidence) that a
 * plain `<img src>` can't load because the endpoint needs a Bearer token. Fetches
 * the bytes with the access token, turns them into an object URL, and revokes it on
 * unmount/path-change. `path` is relative to the API base.
 */
export function AuthImage({
  path, alt, className,
}: {
  path: string; alt: string; className?: string;
}) {
  const [url, setUrl] = React.useState<string | null>(null);
  const [state, setState] = React.useState<"loading" | "ok" | "error">("loading");

  React.useEffect(() => {
    let active = true;
    let objectUrl: string | null = null;

    (async () => {
      setState("loading");
      setUrl(null);
      try {
        const token = getAccessToken();
        const res = await fetch(`${API_BASE}${path}`, {
          headers: token ? { Authorization: `Bearer ${token}` } : {},
          cache: "no-store",
        });
        if (!res.ok) throw new Error(String(res.status));
        const blob = await res.blob();
        if (!active) return;
        objectUrl = URL.createObjectURL(blob);
        setUrl(objectUrl);
        setState("ok");
      } catch {
        if (active) setState("error");
      }
    })();

    return () => {
      active = false;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [path]);

  if (state === "loading") {
    return (
      <div className={cn("flex items-center justify-center bg-muted text-muted-foreground", className)}>
        <Loader2 className="size-5 animate-spin" />
      </div>
    );
  }
  if (state === "error" || !url) {
    return (
      <div className={cn("flex flex-col items-center justify-center gap-1 bg-muted text-muted-foreground", className)}>
        <ImageOff className="size-5" />
        <span className="text-[10px]">Unavailable</span>
      </div>
    );
  }
  return (
    <a href={url} target="_blank" rel="noopener noreferrer" className="block">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={url} alt={alt} className={cn("object-cover", className)} />
    </a>
  );
}
