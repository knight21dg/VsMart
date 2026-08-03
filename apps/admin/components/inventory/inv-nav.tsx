"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";

const TABS = [
  { label: "Command Center", href: "/inventory" },
  { label: "Reorder", href: "/inventory/reorder" },
  { label: "Expiry & Aging", href: "/inventory/expiry" },
  { label: "Finance", href: "/inventory/finance" },
  { label: "Audit", href: "/inventory/audit" },
  { label: "Transfers", href: "/inventory/transfers" },
  { label: "Operations", href: "/inventory/operations" },
];

export function InvNav() {
  const pathname = usePathname();
  return (
    <div className="flex flex-wrap gap-1.5 border-b pb-3">
      {TABS.map((t) => {
        const active = t.href === "/inventory" ? pathname === "/inventory" : pathname.startsWith(t.href);
        return (
          <Link
            key={t.href}
            href={t.href}
            className={cn(
              "rounded-full px-3.5 py-1.5 text-sm font-medium transition-colors",
              active ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:bg-accent hover:text-foreground"
            )}
          >
            {t.label}
          </Link>
        );
      })}
    </div>
  );
}
