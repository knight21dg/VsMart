"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV } from "@/lib/nav";
import { useAuth } from "@/lib/auth/auth-context";
import { cn } from "@/lib/utils";

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(href + "/");
}

export function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const { user } = useAuth();
  const isSuper = user?.role === "superadmin";

  return (
    <aside className="flex h-full w-64 flex-col bg-sidebar text-sidebar-foreground">
      {/* Brand */}
      <div className="flex h-16 items-center gap-3 border-b border-sidebar-border px-5">
        <div className="flex size-9 shrink-0 items-center justify-center overflow-hidden rounded-xl bg-white shadow-sm ring-1 ring-black/5">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/vsmart-logo.png" alt="VS Mart" className="size-full object-contain p-0.5" />
        </div>
        <div className="leading-tight">
          <p className="font-display text-[15px] font-bold tracking-tight text-white">VS Mart</p>
          <p className="text-[10px] font-medium uppercase tracking-[0.16em] text-sidebar-muted">Operations Console</p>
        </div>
      </div>

      <nav className="flex-1 space-y-6 overflow-y-auto px-3 py-5 scrollbar-none">
        {NAV.map((group) => {
          const items = group.items.filter((i) => !i.superadminOnly || isSuper);
          if (items.length === 0) return null;
          return (
            <div key={group.title}>
              <p className="px-3 pb-2 text-[10px] font-semibold uppercase tracking-[0.14em] text-sidebar-muted/80">
                {group.title}
              </p>
              <ul className="space-y-0.5">
                {items.map((item) => {
                  const active = isActive(pathname, item.href);
                  const Icon = item.icon;
                  const content = (
                    <>
                      {active && <span className="absolute left-0 top-1/2 h-5 w-1 -translate-y-1/2 rounded-r-full bg-primary" />}
                      <Icon className={cn("size-[18px] shrink-0 transition-colors", active ? "text-primary" : "text-sidebar-muted group-hover/i:text-white")} />
                      <span className="flex-1 truncate">{item.label}</span>
                      {item.soon && (
                        <span className="rounded bg-sidebar-accent px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wide text-sidebar-muted">
                          soon
                        </span>
                      )}
                    </>
                  );
                  const base = "group/i relative flex items-center gap-3 rounded-lg px-3 py-2 text-[13px] font-medium transition-colors";
                  if (item.soon) {
                    return (
                      <li key={item.href}>
                        <span className={cn(base, "cursor-not-allowed text-sidebar-muted/60")} title="Coming in a later phase">
                          {content}
                        </span>
                      </li>
                    );
                  }
                  return (
                    <li key={item.href}>
                      <Link
                        href={item.href}
                        onClick={onNavigate}
                        className={cn(
                          base,
                          active
                            ? "bg-white/[0.07] text-white"
                            : "text-sidebar-foreground hover:bg-white/[0.04] hover:text-white"
                        )}
                      >
                        {content}
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </div>
          );
        })}
      </nav>

      {/* Footer */}
      <div className="border-t border-sidebar-border px-5 py-3.5">
        <div className="flex items-center gap-2 text-[11px] text-sidebar-muted">
          <span className="relative flex size-2">
            <span className="absolute inline-flex size-full animate-ping rounded-full bg-[var(--color-brand-green)] opacity-60" />
            <span className="relative inline-flex size-2 rounded-full bg-[var(--color-brand-green)]" />
          </span>
          All systems operational
        </div>
      </div>
    </aside>
  );
}
