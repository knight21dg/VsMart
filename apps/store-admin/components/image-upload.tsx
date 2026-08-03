"use client";

import * as React from "react";
import { ImageIcon, Loader2, Upload, X } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError } from "@/lib/types";
import { Button } from "@/components/ui/button";

/**
 * Image picker that uploads the chosen file to VS Mart's media engine (the VPS) and
 * returns the stored URL via `onChange`. No external URLs are typed. The store panel
 * uploads product photos to `/store/inventory/products/image`.
 */
export function ImageUpload({
  value,
  onChange,
  uploadPath = "/store/inventory/products/image",
  disabled,
}: {
  value?: string | null;
  onChange: (url: string | null) => void;
  uploadPath?: string;
  disabled?: boolean;
}) {
  const [busy, setBusy] = React.useState(false);
  const inputRef = React.useRef<HTMLInputElement>(null);

  async function pick(file: File | null) {
    if (!file) return;
    setBusy(true);
    try {
      const fd = new FormData();
      fd.append("file", file);
      const res = await api.upload<{ url: string }>(uploadPath, fd);
      onChange(res.url);
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Image upload failed.");
    } finally {
      setBusy(false);
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  const preview = value ? api.assetUrl(value) : null;

  return (
    <div className="flex items-center gap-3">
      <div className="relative grid size-20 shrink-0 place-items-center overflow-hidden rounded-md border bg-muted">
        {preview ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={preview} alt="" className="size-full object-cover" />
        ) : (
          <ImageIcon className="size-6 text-muted-foreground" />
        )}
        {busy && (
          <div className="absolute inset-0 grid place-items-center bg-background/60">
            <Loader2 className="size-5 animate-spin" />
          </div>
        )}
      </div>
      <div className="flex flex-col items-start gap-1.5">
        <input
          ref={inputRef}
          type="file"
          accept="image/png,image/jpeg,image/webp"
          className="hidden"
          onChange={(e) => pick(e.target.files?.[0] ?? null)}
        />
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={busy || disabled}
          onClick={() => inputRef.current?.click()}
        >
          <Upload className="size-4" /> {value ? "Replace image" : "Upload image"}
        </Button>
        {value && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            disabled={busy || disabled}
            onClick={() => onChange(null)}
          >
            <X className="size-4" /> Remove
          </Button>
        )}
        <p className="text-xs text-muted-foreground">PNG, JPG or WebP · stored on VS Mart</p>
      </div>
    </div>
  );
}
