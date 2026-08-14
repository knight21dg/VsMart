/**
 * Regression: a table must not strand the operator on a page the server no longer has.
 *
 * The page number lives in the caller's state and the total lives in the response,
 * so anything that shrinks the result set behind a stationary page cursor — deleting
 * the last row on page 5, a filter that narrows, another operator working the same
 * list — left the table rendering "Page 5 of 4" over "No records found." Next is
 * disabled at that point, so the deleted row looked like it had taken the whole
 * table with it.
 *
 * The store panel carries the same table and the same test; the two consoles keep
 * separate copies of the component, so they need separate proof.
 */
import * as React from "react";
import { describe, expect, it, vi } from "vitest";
import { render, screen, waitFor } from "@testing-library/react";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table";

interface Row { id: string; name: string }
const columns: ColumnDef<Row, unknown>[] = [
  { accessorKey: "name", header: "Name", cell: ({ row }) => row.original.name },
];

function meta(page: number, totalPages: number, total: number) {
  return { page, totalPages, total, pageSize: 10 };
}

describe("DataTable pagination", () => {
  it("clamps back to the last real page when the result set shrinks", async () => {
    const onPageChange = vi.fn();
    render(
      <DataTable
        columns={columns}
        data={[]}
        page={5}
        pageMeta={meta(5, 4, 38)}
        onPageChange={onPageChange}
      />,
    );
    await waitFor(() => expect(onPageChange).toHaveBeenCalledWith(4));
  });

  it("falls back to page 1 when every row is gone", async () => {
    const onPageChange = vi.fn();
    render(
      <DataTable
        columns={columns}
        data={[]}
        page={3}
        pageMeta={meta(3, 0, 0)}
        onPageChange={onPageChange}
      />,
    );
    // `Math.max(totalPages, 1)` — page 0 is not a page anyone can be on.
    await waitFor(() => expect(onPageChange).toHaveBeenCalledWith(1));
  });

  it("leaves a page that is still in range alone", async () => {
    const onPageChange = vi.fn();
    render(
      <DataTable
        columns={columns}
        data={[{ id: "1", name: "Row one" }]}
        page={2}
        pageMeta={meta(2, 4, 38)}
        onPageChange={onPageChange}
      />,
    );
    expect(await screen.findByText("Row one")).toBeTruthy();
    await new Promise((r) => setTimeout(r, 20));
    expect(onPageChange).not.toHaveBeenCalled();
  });

  it("does not bounce the page while the next page is still loading", async () => {
    const onPageChange = vi.fn();
    // Mid-flight the PREVIOUS page's meta is still mounted, so an unguarded clamp
    // would fire against stale totals and undo the operator's own click.
    render(
      <DataTable
        columns={columns}
        data={[]}
        loading
        page={5}
        pageMeta={meta(1, 1, 4)}
        onPageChange={onPageChange}
      />,
    );
    await new Promise((r) => setTimeout(r, 20));
    expect(onPageChange).not.toHaveBeenCalled();
  });
});
