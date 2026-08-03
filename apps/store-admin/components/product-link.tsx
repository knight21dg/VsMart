"use client";

import Link from "next/link";
import { Badge } from "@/components/ui/badge";

/**
 * Canonical way to render a product name in the store panel.
 *
 * Every product name should be clickable through to the product's detail page —
 * a real `<a>` rather than a row `onClick`, so middle-click / open-in-new-tab /
 * "copy link" all behave the way an operator expects.
 *
 * Unlike the admin console there is no read-only product page here: the store
 * panel's product surface IS the edit form at `/inventory/products/<id>/edit`,
 * which is what the Inventory table's Edit button already routes to. It loads
 * `/store/inventory/products/<id>` for company and store-owned products alike,
 * so it's a valid destination for any product this store can see.
 *
 * `id` is the Product PK. When it's missing (POS receipt lines and some reports
 * only carry a name snapshot), the name renders as plain text instead of a dead
 * link.
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
      href={`/inventory/products/${id}/edit`}
      // Row-level onClick handlers are common in these tables; stop the click
      // here so the link navigates once rather than racing the row handler.
      onClick={(e) => e.stopPropagation()}
      className={`hover:text-primary hover:underline underline-offset-2 ${className}`}
    >
      {label}
    </Link>
  );
}
