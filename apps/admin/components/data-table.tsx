"use client";

import * as React from "react";
import {
  type ColumnDef,
  flexRender,
  getCoreRowModel,
  useReactTable,
} from "@tanstack/react-table";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { ErrorState } from "@/components/states";
import type { CursorMeta, PageMeta } from "@/lib/types";
import { cn } from "@/lib/utils";

/**
 * True when a click landed on a control inside the row rather than on the row.
 *
 * Rows that are themselves clickable almost always also carry an actions cell
 * (edit / delete icons). Without this guard the row handler fires for those
 * clicks too, so pressing Delete opened the confirm dialog *and* navigated away
 * in the same tick — the dialog unmounted before it could be seen and the record
 * was never deleted. The row click is the fallback for "clicked nothing in
 * particular", so anything with its own handler wins.
 */
function isInteractiveTarget(target: EventTarget | null): boolean {
  return (
    target instanceof Element &&
    !!target.closest('button, a, input, select, textarea, label, [role="button"], [role="checkbox"], [role="menuitem"], [data-row-click="ignore"]')
  );
}

interface DataTableProps<T> {
  columns: ColumnDef<T, unknown>[];
  data: T[];
  loading?: boolean;
  error?: string | null;
  onRetry?: () => void;
  emptyMessage?: string;
  toolbar?: React.ReactNode;
  onRowClick?: (row: T) => void;
  // page-based pagination
  pageMeta?: PageMeta;
  page?: number;
  onPageChange?: (page: number) => void;
  // cursor-based pagination
  cursorMeta?: CursorMeta;
  onCursor?: (cursor: string | null) => void;
}

export function DataTable<T>({
  columns,
  data,
  loading,
  error,
  onRetry,
  emptyMessage = "No records found.",
  toolbar,
  onRowClick,
  pageMeta,
  page,
  onPageChange,
  cursorMeta,
  onCursor,
}: DataTableProps<T>) {
  const table = useReactTable({
    data,
    columns,
    getCoreRowModel: getCoreRowModel(),
    manualPagination: true,
  });

  /*
   * Keep the requested page inside the range the server actually has.
   *
   * The page number lives in the caller's state while the total lives in the
   * response, so anything that shrinks the result set behind a stationary page
   * cursor strands the operator: deleting the last row on page 5 leaves them on
   * "Page 5 of 4" looking at "No records found." — the row they deleted appears
   * to have taken the whole table with it. Next is disabled at that point, so the
   * only way out is to notice the Prev arrow.
   *
   * Clamping here rather than in each page keeps all thirteen tables consistent,
   * and it covers every cause at once (delete, a filter that narrows, another
   * operator working the same list) instead of just the one that was reported.
   */
  const current = page ?? pageMeta?.page;
  const totalPages = pageMeta?.totalPages;
  React.useEffect(() => {
    if (!onPageChange || current == null || totalPages == null) return;
    // `loading` guards the gap between a page change and its response, where the
    // previous page's meta is still mounted and would bounce the page straight back.
    if (loading) return;
    const target = Math.max(totalPages, 1);
    if (current > target) onPageChange(target);
  }, [current, totalPages, loading, onPageChange]);

  const colCount = columns.length;

  return (
    <div className="space-y-3">
      {toolbar}
      <div className="rounded-xl border bg-card">
        <Table>
          <TableHeader>
            {table.getHeaderGroups().map((hg) => (
              <TableRow key={hg.id} className="hover:bg-transparent">
                {hg.headers.map((header) => (
                  <TableHead key={header.id}>
                    {header.isPlaceholder
                      ? null
                      : flexRender(header.column.columnDef.header, header.getContext())}
                  </TableHead>
                ))}
              </TableRow>
            ))}
          </TableHeader>
          <TableBody>
            {loading ? (
              Array.from({ length: 6 }).map((_, i) => (
                <TableRow key={`sk-${i}`} className="hover:bg-transparent">
                  {Array.from({ length: colCount }).map((__, j) => (
                    <TableCell key={j}>
                      <Skeleton className="h-4 w-full max-w-[160px]" />
                    </TableCell>
                  ))}
                </TableRow>
              ))
            ) : error ? (
              <TableRow className="hover:bg-transparent">
                <TableCell colSpan={colCount}>
                  <ErrorState message={error} onRetry={onRetry} />
                </TableCell>
              </TableRow>
            ) : data.length === 0 ? (
              <TableRow className="hover:bg-transparent">
                <TableCell colSpan={colCount} className="py-12 text-center text-sm text-muted-foreground">
                  {emptyMessage}
                </TableCell>
              </TableRow>
            ) : (
              table.getRowModel().rows.map((row) => (
                <TableRow
                  key={row.id}
                  onClick={onRowClick ? (e) => { if (!isInteractiveTarget(e.target)) onRowClick(row.original); } : undefined}
                  className={cn(onRowClick && "cursor-pointer")}
                >
                  {row.getVisibleCells().map((cell) => (
                    <TableCell key={cell.id}>
                      {flexRender(cell.column.columnDef.cell, cell.getContext())}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>

      {/* Page-based footer */}
      {pageMeta && onPageChange && (
        <div className="flex items-center justify-between text-sm text-muted-foreground">
          <span>
            {pageMeta.total.toLocaleString("en-IN")} record{pageMeta.total === 1 ? "" : "s"}
          </span>
          <div className="flex items-center gap-2">
            <span>
              Page {pageMeta.page} of {Math.max(pageMeta.totalPages, 1)}
            </span>
            <Button
              variant="outline"
              size="icon"
              disabled={(page ?? pageMeta.page) <= 1}
              onClick={() => onPageChange((page ?? pageMeta.page) - 1)}
            >
              <ChevronLeft />
            </Button>
            <Button
              variant="outline"
              size="icon"
              disabled={(page ?? pageMeta.page) >= pageMeta.totalPages}
              onClick={() => onPageChange((page ?? pageMeta.page) + 1)}
            >
              <ChevronRight />
            </Button>
          </div>
        </div>
      )}

      {/* Cursor-based footer */}
      {cursorMeta && onCursor && (
        <div className="flex items-center justify-end gap-2 text-sm">
          <Button
            variant="outline"
            size="sm"
            disabled={!cursorMeta.previousCursor}
            onClick={() => onCursor(cursorMeta.previousCursor)}
          >
            <ChevronLeft /> Prev
          </Button>
          <Button
            variant="outline"
            size="sm"
            disabled={!cursorMeta.nextCursor}
            onClick={() => onCursor(cursorMeta.nextCursor)}
          >
            Next <ChevronRight />
          </Button>
        </div>
      )}
    </div>
  );
}
