/**
 * Regression: a clickable row must not swallow its own action buttons.
 *
 * `DataTable` puts `onClick` on the whole `TableRow`, and almost every clickable
 * row also carries an actions cell. Without a guard both fire on one press: the
 * Delete button set its confirm state AND the row handler navigated away in the
 * same tick, so the dialog unmounted before it could render and nothing was ever
 * deleted. That is precisely how zone deletion broke — `stores/page.tsx` happened
 * to call `stopPropagation` by hand and `zones/page.tsx` did not.
 *
 * The guard lives in `DataTable` so no page has to remember.
 */
import * as React from "react";
import { describe, expect, it, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/data-table";

interface Row { id: string; name: string }

function setup(onRowClick: () => void, onDelete: () => void) {
  const columns: ColumnDef<Row, unknown>[] = [
    { accessorKey: "name", header: "Name", cell: ({ row }) => row.original.name },
    {
      id: "actions",
      header: "",
      cell: () => (
        <div>
          <button onClick={onDelete}>Delete</button>
          <a href="/somewhere">Open</a>
          <input type="checkbox" aria-label="Pick" />
        </div>
      ),
    },
  ];
  render(
    <DataTable
      columns={columns}
      data={[{ id: "z1", name: "Bengaluru South" }]}
      onRowClick={onRowClick}
    />,
  );
}

describe("DataTable row click", () => {
  it("fires the row handler when the row itself is clicked", async () => {
    const onRowClick = vi.fn();
    const onDelete = vi.fn();
    setup(onRowClick, onDelete);

    await userEvent.setup().click(screen.getByText("Bengaluru South"));
    expect(onRowClick).toHaveBeenCalledTimes(1);
    expect(onDelete).not.toHaveBeenCalled();
  });

  it("does NOT fire the row handler when a row action button is pressed", async () => {
    const onRowClick = vi.fn();
    const onDelete = vi.fn();
    setup(onRowClick, onDelete);

    await userEvent.setup().click(screen.getByRole("button", { name: "Delete" }));
    expect(onDelete).toHaveBeenCalledTimes(1);
    // The whole bug: this used to also fire and tear down the confirm dialog.
    expect(onRowClick).not.toHaveBeenCalled();
  });

  it("leaves links and checkboxes inside a row to themselves", async () => {
    const onRowClick = vi.fn();
    const onDelete = vi.fn();
    setup(onRowClick, onDelete);
    const user = userEvent.setup();

    await user.click(screen.getByRole("checkbox", { name: "Pick" }));
    expect(onRowClick).not.toHaveBeenCalled();

    await user.click(screen.getByRole("link", { name: "Open" }));
    expect(onRowClick).not.toHaveBeenCalled();
  });
});
