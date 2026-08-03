"use client";

import { ShieldAlert } from "lucide-react";
import { useStore } from "@/lib/store/store-context";
import { LoadingState } from "@/components/states";

/** Wraps a page body and shows an access notice if the staff member lacks the
 * permission. The sidebar already hides links and the backend returns 403 — this
 * is defense-in-depth + a friendly message for deep links. */
export function RequirePerm({ perm, children }: { perm: string; children: React.ReactNode }) {
  const { hasPerm, loading } = useStore();
  if (loading) return <LoadingState />;
  if (!hasPerm(perm)) {
    return (
      <div className="flex flex-col items-center justify-center gap-3 py-24 text-center">
        <div className="flex size-12 items-center justify-center rounded-full bg-warning/10 text-warning">
          <ShieldAlert className="size-6" />
        </div>
        <div>
          <p className="font-semibold">No access to this section</p>
          <p className="mt-1 max-w-sm text-sm text-muted-foreground">
            Your role doesn&apos;t include this permission. Ask your store manager if you need it.
          </p>
        </div>
      </div>
    );
  }
  return <>{children}</>;
}
