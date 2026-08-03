"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { NAV } from "@/lib/nav";
import { useStore } from "@/lib/store/store-context";
import { cn } from "@/lib/utils";

function isActive(pathname: string, href: string) {
  if (href === "/") return pathname === "/";
  return pathname === href || pathname.startsWith(href + "/");
}

export function Sidebar({ onNavigate }: { onNavigate?: () => void }) {
  const pathname = usePathname();
  const { me, hasAny } = useStore();

  return (
    <aside className="flex h-full w-64 flex-col bg-sidebar text-sidebar-foreground">
      <div className="flex h-14 items-center gap-2 border-b border-sidebar-border px-5">
        <div className="flex size-7 items-center justify-center rounded-md bg-primary text-sm font-bold text-primary-foreground">
          VS
        </div>
        <div className="leading-tight">
          <p className="text-sm font-semibold text-white">{me?.store.name || "VS Mart"}</p>
          <p className="text-[10px] uppercase tracking-wider text-sidebar-muted">Store Panel</p>
        </div>
      </div>

      <nav className="flex-1 space-y-5 overflow-y-auto px-3 py-4 scrollbar-none">
        {NAV.map((group) => {
          // Show an item if it has no perms gate, or the staff holds one of them.
          const items = group.items.filter((i) => !i.perms || hasAny(i.perms));
          if (items.length === 0) return null;
          return (
            <div key={group.title}>
              <p className="px-2 pb-1.5 text-[10px] font-semibold uppercase tracking-wider text-sidebar-muted">
                {group.title}
              </p>
              <ul className="space-y-0.5">
                {items.map((item) => {
                  const active = isActive(pathname, item.href);
                  const Icon = item.icon;
                  const content = (
                    <>
                      <Icon className="size-4 shrink-0" />
                      <span className="flex-1 truncate">{item.label}</span>
                      {item.soon && (
                        <span className="rounded bg-sidebar-accent px-1.5 py-0.5 text-[9px] font-medium uppercase text-sidebar-muted">
                          soon
                        </span>
                      )}
                    </>
                  );
                  const base =
                    "flex items-center gap-2.5 rounded-md px-2.5 py-2 text-sm transition-colors";
                  if (item.soon) {
                    return (
                      <li key={item.href}>
                        <span
                          className={cn(base, "cursor-not-allowed text-sidebar-muted/70")}
                          title="Coming soon"
                        >
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
                            ? "bg-primary text-primary-foreground"
                            : "text-sidebar-foreground hover:bg-sidebar-accent hover:text-white"
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

      {me && (
        <div className="border-t border-sidebar-border px-4 py-3 text-[11px] text-sidebar-muted">
          {me.store.code} · {me.staffRoleLabel}
        </div>
      )}
    </aside>
  );
}
