"use client";

import * as React from "react";
import { ImagePlus, Loader2, Star, X } from "lucide-react";
import { toast } from "sonner";
import { api } from "@/lib/api/client";
import { ApiError } from "@/lib/types";
import { ImageCropDialog } from "@/components/image-cropper";

/**
 * Multi-image gallery picker. Selected files are cropped to 1:1 one-by-one (see
 * ImageCropDialog), uploaded to the VPS, and their URLs kept in `value`. The first
 * image is the cover. No external image URLs are ever typed.
 */
export function MultiImageUpload({
  value,
  onChange,
  uploadPath = "/store/inventory/products/image",
  max = 6,
}: {
  value: string[];
  onChange: (urls: string[]) => void;
  uploadPath?: string;
  max?: number;
}) {
  const [queue, setQueue] = React.useState<File[] | null>(null);
  const [busy, setBusy] = React.useState(false);
  const inputRef = React.useRef<HTMLInputElement>(null);

  function pick(files: FileList | null) {
    if (!files || files.length === 0) return;
    const room = max - value.length;
    const chosen = Array.from(files).slice(0, Math.max(0, room));
    if (chosen.length === 0) {
      toast.error(`You can add up to ${max} images.`);
      return;
    }
    setQueue(chosen); // opens the 1:1 cropper for the batch
  }

  async function onCropped(blobs: Blob[]) {
    setQueue(null);
    setBusy(true);
    try {
      const urls: string[] = [];
      for (const b of blobs) {
        const fd = new FormData();
        fd.append("file", new File([b], "image.webp", { type: "image/webp" }));
        const res = await api.upload<{ url: string }>(uploadPath, fd);
        urls.push(res.url);
      }
      onChange([...value, ...urls]);
    } catch (e) {
      toast.error(e instanceof ApiError ? e.message : "Image upload failed.");
    } finally {
      setBusy(false);
      if (inputRef.current) inputRef.current.value = "";
    }
  }

  function remove(i: number) {
    onChange(value.filter((_, j) => j !== i));
  }
  function makeCover(i: number) {
    if (i === 0) return;
    const next = [...value];
    const [x] = next.splice(i, 1);
    next.unshift(x);
    onChange(next);
  }

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        {value.map((u, i) => (
          <div key={u} className="group relative size-20 overflow-hidden rounded-md border">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={api.assetUrl(u)} alt="" className="size-full object-cover" />
            {i === 0 && (
              <span className="absolute left-1 top-1 rounded bg-primary px-1 text-[10px] font-medium text-primary-foreground">
                Cover
              </span>
            )}
            <div className="absolute inset-0 flex items-center justify-center gap-1 bg-black/40 opacity-0 transition-opacity group-hover:opacity-100">
              {i !== 0 && (
                <button type="button" onClick={() => makeCover(i)} title="Make cover"
                  className="grid size-6 place-items-center rounded bg-background/90 text-foreground">
                  <Star className="size-3.5" />
                </button>
              )}
              <button type="button" onClick={() => remove(i)} title="Remove"
                className="grid size-6 place-items-center rounded bg-background/90 text-foreground">
                <X className="size-3.5" />
              </button>
            </div>
          </div>
        ))}
        {value.length < max && (
          <button type="button" onClick={() => inputRef.current?.click()} disabled={busy}
            className="grid size-20 place-items-center rounded-md border border-dashed text-muted-foreground hover:border-primary hover:text-primary">
            {busy ? <Loader2 className="size-5 animate-spin" /> : <ImagePlus className="size-5" />}
          </button>
        )}
      </div>
      <input ref={inputRef} type="file" accept="image/png,image/jpeg,image/webp" multiple className="hidden"
        onChange={(e) => pick(e.target.files)} />
      <p className="text-xs text-muted-foreground">
        Up to {max} images · each cropped to a 1:1 square · first image is the cover.
      </p>
      {queue && (
        <ImageCropDialog
          files={queue}
          onComplete={onCropped}
          onCancel={() => { setQueue(null); if (inputRef.current) inputRef.current.value = ""; }}
        />
      )}
    </div>
  );
}
