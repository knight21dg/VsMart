"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError } from "@/lib/types";

/** Shorthand for a mutation that invalidates queries + toasts on success/error. */
export function useApiMutation<TVars, TData = unknown>(
  fn: (vars: TVars) => Promise<TData>,
  opts: { invalidate?: unknown[][]; successMessage?: string; onDone?: (data: TData) => void } = {}
) {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: fn,
    onSuccess: (data) => {
      if (opts.successMessage) toast.success(opts.successMessage);
      opts.invalidate?.forEach((key) => qc.invalidateQueries({ queryKey: key }));
      opts.onDone?.(data);
    },
    onError: (err) => {
      const msg = err instanceof ApiError ? err.message : "Something went wrong.";
      toast.error(msg);
    },
  });
}

export { api };
