"use client";

import Link from "next/link";
import { Badge } from "@/components/ui/badge";

/**
 * Canonical way to render a product name in the console.
 *
 * Every product name should be clickable through to the product's detail page —
 * a real `<a>` rather than a row `onClick`, so middle-click / open-in-new-tab /
 * "copy link" all behave the way an operator expects.
 *
 * `id` is the numeric Product PK. When it's missing (a few reports only carry a
 * name snapshot, e.g. OrderItem.name), the name renders as plain text instead of
 * a dead link.
 */
export function ProductLink({
  id,
  name,
  archived = false,
  className = "",
}: {
  id?: string | number | null;
  name: string;
  archived?: boolean;
  className?: string;
}) {
  const label = (
    <>
      {name}
      {archived && (
        <Badge variant="outline" className="ml-2 align-middle text-[10px]">
          Archived
        </Badge>
      )}
    </>
  );

  if (id === null || id === undefined || id === "") {
    return <span className={className}>{label}</span>;
  }

  return (
    <Link
      href={`/inventory/product/${id}`}
      // Row-level onClick handlers are common in these tables; stop the click
      // here so the link navigates once rather than racing the row handler.
      onClick={(e) => e.stopPropagation()}
      className={`hover:text-primary hover:underline underline-offset-2 ${className}`}
    >
      {label}
    </Link>
  );
}
