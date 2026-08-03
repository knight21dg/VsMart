"use client";

import { Toaster as Sonner } from "sonner";

export function Toaster() {
  return (
    <Sonner
      position="top-right"
      toastOptions={{
        classNames: {
          toast:
            "group rounded-lg border bg-card text-card-foreground shadow-lg text-sm p-4 flex gap-3 items-start",
          description: "text-muted-foreground",
          actionButton: "bg-primary text-primary-foreground rounded-md px-2 py-1 text-xs",
          error: "border-destructive/40",
          success: "border-[color-mix(in_oklab,var(--color-success)_40%,transparent)]",
        },
      }}
    />
  );
}
