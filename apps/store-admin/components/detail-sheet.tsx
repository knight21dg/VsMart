import * as React from "react";

/**
 * Shared building blocks for the right-side "detail drawer" pattern (orders,
 * customers, returns…). The drawer itself is the shadcn Dialog with these
 * positioning overrides; `tailwind-merge` lets them beat the centered defaults.
 */
export const sheetClass =
  "left-auto right-0 top-0 max-w-xl translate-x-0 translate-y-0 h-full max-h-screen rounded-none rounded-l-xl";

export function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <p className="text-xs font-semibold uppercase tracking-wider text-muted-foreground">{title}</p>
      {children}
    </div>
  );
}

export function KV({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className="text-right font-medium">{value}</span>
    </div>
  );
}
