import { Badge, type BadgeProps } from "@/components/ui/badge";
import { titleize } from "@/lib/utils";

const MAP: Record<string, BadgeProps["variant"]> = {
  // KYC
  verified: "success",
  approved: "success",
  pending: "warning",
  under_review: "warning",
  rejected: "destructive",
  not_started: "secondary",
  new: "secondary",
  assigned: "default",
  // credit / generic
  active: "success",
  frozen: "warning",
  suspended: "destructive",
  // orders / fulfilment
  delivered: "success",
  posted: "success",
  received: "success",
  confirmed: "default",
  packed: "default",
  out_for_delivery: "default",
  cancelled: "destructive",
  returned: "warning",
  draft: "secondary",
  open: "default",
  overdue: "destructive",
};

export function StatusBadge({ status }: { status?: string | null }) {
  if (!status) return <span className="text-muted-foreground">—</span>;
  const variant = MAP[status.toLowerCase()] ?? "secondary";
  return <Badge variant={variant}>{titleize(status)}</Badge>;
}

export function BoolBadge({ value, trueLabel = "Yes", falseLabel = "No" }: { value?: boolean; trueLabel?: string; falseLabel?: string }) {
  return <Badge variant={value ? "success" : "secondary"}>{value ? trueLabel : falseLabel}</Badge>;
}
