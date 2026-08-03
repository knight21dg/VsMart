"use client";

import * as React from "react";
import { useQuery } from "@tanstack/react-query";
import { Loader2 } from "lucide-react";
import { api } from "@/lib/api/client";
import { useApiMutation } from "@/lib/api/hooks";
import { PageHeader } from "@/components/page-header";
import { Card, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { StatusBadge } from "@/components/status-badge";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { LoadingState, ErrorState, EmptyState } from "@/components/states";
import { cn, fmtDate } from "@/lib/utils";

interface DeletionRequest {
  id: string;
  name: string;
  contact: string;
  reason: string;
  status: string;
  note: string | null;
  created_at: string;
  processed_at: string | null;
}

interface RequestsResp {
  requests: DeletionRequest[];
}

const FILTERS = [
  { key: "", label: "All" },
  { key: "pending", label: "Pending" },
  { key: "in_review", label: "In review" },
  { key: "completed", label: "Completed" },
  { key: "rejected", label: "Rejected" },
];

const STATUS_OPTIONS = [
  { key: "pending", label: "Pending" },
  { key: "in_review", label: "In review" },
  { key: "completed", label: "Completed" },
  { key: "rejected", label: "Rejected" },
];

export default function AccountDeletionsPage() {
  const [status, setStatus] = React.useState("");
  const [noteFor, setNoteFor] = React.useState<DeletionRequest | null>(null);

  const query = useQuery({
    queryKey: ["admin", "deletion-requests", { status }],
    queryFn: () =>
      api.get<RequestsResp>("/admin/deletion-requests", { status: status || undefined }),
  });
  const requests = query.data?.requests ?? [];

  const update = useApiMutation(
    (vars: { id: string; body: { status?: string; note?: string } }) =>
      api.patch<DeletionRequest>(`/admin/deletion-requests/${vars.id}`, vars.body),
    { invalidate: [["admin", "deletion-requests"]], successMessage: "Request updated." }
  );

  return (
    <>
      <PageHeader
        title="Account Deletion Requests"
        description="Review and action customer requests to delete their account data."
      />

      <div className="flex flex-wrap items-center gap-2">
        {FILTERS.map((f) => (
          <button
            key={f.key}
            onClick={() => setStatus(f.key)}
            className={cn(
              "rounded-full border px-3.5 py-1.5 text-sm transition-colors",
              status === f.key
                ? "border-primary bg-primary text-primary-foreground"
                : "bg-card hover:bg-accent"
            )}
          >
            {f.label}
          </button>
        ))}
      </div>

      <Card>
        <CardContent className="p-0">
          {query.isLoading ? (
            <LoadingState />
          ) : query.isError ? (
            <ErrorState message="Couldn't load deletion requests." onRetry={() => query.refetch()} />
          ) : requests.length === 0 ? (
            <EmptyState
              title="No requests"
              description="No account deletion requests match this filter."
              className="py-16"
            />
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Contact</TableHead>
                  <TableHead>Reason</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Requested</TableHead>
                  <TableHead className="text-right">Action</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {requests.map((r) => {
                  const busy = update.isPending && update.variables?.id === r.id;
                  return (
                    <TableRow key={r.id}>
                      <TableCell className="font-medium">{r.name || "—"}</TableCell>
                      <TableCell className="font-mono text-xs">{r.contact}</TableCell>
                      <TableCell className="max-w-xs">
                        <span className="line-clamp-2 text-sm text-muted-foreground">
                          {r.reason || "—"}
                        </span>
                      </TableCell>
                      <TableCell>
                        <StatusBadge status={r.status} />
                      </TableCell>
                      <TableCell className="whitespace-nowrap text-xs text-muted-foreground">
                        {fmtDate(r.created_at, true)}
                      </TableCell>
                      <TableCell>
                        <div className="flex items-center justify-end gap-2">
                          {busy && <Loader2 className="size-4 animate-spin text-muted-foreground" />}
                          <Select
                            value={r.status}
                            onValueChange={(v) => update.mutate({ id: r.id, body: { status: v } })}
                          >
                            <SelectTrigger className="h-8 w-36">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {STATUS_OPTIONS.map((o) => (
                                <SelectItem key={o.key} value={o.key}>
                                  {o.label}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                          <Button variant="outline" size="sm" onClick={() => setNoteFor(r)}>
                            Note
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      {noteFor && (
        <NoteDialog
          request={noteFor}
          pending={update.isPending}
          onClose={() => setNoteFor(null)}
          onSave={(note) =>
            update.mutate(
              { id: noteFor.id, body: { note } },
              { onSuccess: () => setNoteFor(null) }
            )
          }
        />
      )}
    </>
  );
}

function NoteDialog({
  request,
  pending,
  onClose,
  onSave,
}: {
  request: DeletionRequest;
  pending: boolean;
  onClose: () => void;
  onSave: (note: string) => void;
}) {
  const [note, setNote] = React.useState(request.note ?? "");

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Internal note</DialogTitle>
        </DialogHeader>
        <div className="space-y-3">
          <div className="rounded-lg border bg-muted/30 p-3 text-sm">
            <p className="font-medium">{request.name || "—"}</p>
            <p className="font-mono text-xs text-muted-foreground">{request.contact}</p>
          </div>
          <div className="space-y-1.5">
            <Label htmlFor="del-note">Note</Label>
            <textarea
              id="del-note"
              value={note}
              onChange={(e) => setNote(e.target.value)}
              rows={5}
              placeholder="Add context about how this request was handled…"
              className="flex w-full rounded-md border border-input bg-card px-3 py-2 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose} disabled={pending}>
            Cancel
          </Button>
          <Button onClick={() => onSave(note)} disabled={pending}>
            {pending && <Loader2 className="size-4 animate-spin" />}
            Save note
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
