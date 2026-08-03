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
                  onClick={onRowClick ? () => onRowClick(row.original) : undefined}
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
