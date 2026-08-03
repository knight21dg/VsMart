import { toast } from "sonner";

import { API_BASE } from "@/lib/api/client";
import { getAccessToken } from "@/lib/auth/session";

/**
 * Download a PDF the API serves as a binary body (invoices, receipts).
 *
 * These endpoints return `application/pdf`, not the JSON envelope `api.get`
 * unwraps, and they need the bearer token — so they can't go through the normal
 * client. Kept in one place because POS sales, store orders and anything else
 * that prints must behave identically (same auth, same failure toast, same
 * object-URL cleanup).
 */
export async function downloadPdf(path: string, filename: string): Promise<void> {
  let url: string | null = null;
  try {
    const res = await fetch(`${API_BASE}${path}`, {
      headers: { Authorization: `Bearer ${getAccessToken()}` },
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const blob = await res.blob();
    url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = filename;
    a.click();
  } catch {
    toast.error("Couldn't download the PDF.");
  } finally {
    // Revoke in `finally` so a failure mid-click can't leak the object URL.
    if (url) URL.revokeObjectURL(url);
  }
}
