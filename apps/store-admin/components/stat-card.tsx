import { Card } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

export function StatCard({
  label,
  value,
  icon,
  hint,
  accent = "teal",
  loading,
  className,
}: {
  label: string;
  value: React.ReactNode;
  icon?: React.ReactNode;
  hint?: string;
  accent?: "teal" | "green" | "gold" | "slate" | "red";
  loading?: boolean;
  className?: string;
}) {
  const accents: Record<string, string> = {
    teal: "bg-primary/10 text-primary",
    green: "bg-[color-mix(in_oklab,var(--color-brand-green)_18%,transparent)] text-[var(--color-success)]",
    gold: "bg-[color-mix(in_oklab,var(--color-brand-gold)_22%,transparent)] text-[var(--color-warning)]",
    slate: "bg-muted text-muted-foreground",
    red: "bg-destructive/10 text-destructive",
  };
  return (
    <Card className={cn("p-5", className)}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 space-y-1">
          <p className="truncate text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</p>
          {loading ? (
            <Skeleton className="h-7 w-24" />
          ) : (
            <p className="text-2xl font-bold tracking-tight">{value}</p>
          )}
          {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
        </div>
        {icon && (
          <div className={cn("flex size-9 shrink-0 items-center justify-center rounded-lg [&_svg]:size-5", accents[accent])}>
            {icon}
          </div>
        )}
      </div>
    </Card>
  );
}
