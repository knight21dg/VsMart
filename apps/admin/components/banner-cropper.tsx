"use client";

import * as React from "react";
import { AlertTriangle, Loader2, Minus, Plus, RotateCcw } from "lucide-react";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

/** Normalized crop rect on the *source* image, all values 0..1. */
export type CropRect = { x: number; y: number; w: number; h: number };

const FRAME_W = 460; // on-screen crop frame width, px

/**
 * Aspect-locked banner cropper.
 *
 * The frame is locked to the target placement's ratio (16:10 for the home hero,
 * 16:9 for the strips, 1:1 for spotlight), so what marketing frames here is
 * exactly what renders in the app — the server crops the *original* file to this
 * rect, then resizes to the placement's master size.
 *
 * It deliberately returns a rect rather than a canvas blob: exporting from canvas
 * would bake in the on-screen resolution (460px wide) and throw away the source
 * pixels before the server ever sees them.
 */
export function BannerCropDialog({
  file, aspect, aspectLabel, minWidth, minHeight, placementLabel,
  initialRect, onCancel, onDone,
}: {
  file: File;
  aspect: number;              // width / height
  aspectLabel: string;         // "16:10"
  minWidth: number;
  minHeight: number;
  placementLabel: string;
  initialRect?: CropRect | null;
  onCancel: () => void;
  /**
   * `resized` is set only when the operator chose to re-render the image at the
   * placement's exact resolution — upload that file instead of the original,
   * and note the rect will be the full frame.
   */
  onDone: (rect: CropRect, resized?: File) => void;
}) {
  const frameH = Math.round(FRAME_W / aspect);
  const [img, setImg] = React.useState<HTMLImageElement | null>(null);
  const [zoom, setZoom] = React.useState(1);
  const [resizing, setResizing] = React.useState(false);
  const [offset, setOffset] = React.useState({ x: 0, y: 0 });
  const drag = React.useRef<{ x: number; y: number; ox: number; oy: number } | null>(null);

  // "cover" scale: the smallest scale at which the image still fills the frame.
  const coverScale = React.useCallback(
    (image: HTMLImageElement) =>
      Math.max(FRAME_W / image.naturalWidth, frameH / image.naturalHeight),
    [frameH],
  );

  const reset = React.useCallback((image: HTMLImageElement, rect?: CropRect | null) => {
    const cover = coverScale(image);
    if (rect && rect.w > 0 && rect.h > 0) {
      // Restore a previously saved crop: the rect's width drives the zoom.
      const s = FRAME_W / (rect.w * image.naturalWidth);
      setZoom(Math.max(1, s / cover));
      setOffset({
        x: -rect.x * image.naturalWidth * s,
        y: -rect.y * image.naturalHeight * s,
      });
      return;
    }
    setZoom(1);
    setOffset({
      x: (FRAME_W - image.naturalWidth * cover) / 2,
      y: (frameH - image.naturalHeight * cover) / 2,
    });
  }, [coverScale, frameH]);

  React.useEffect(() => {
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => { setImg(image); reset(image, initialRect); };
    image.src = url;
    return () => URL.revokeObjectURL(url);
    // initialRect is only an entry condition — re-running on identity change
    // would yank the frame out from under the user mid-drag.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [file, reset]);

  const scale = img ? coverScale(img) * zoom : 1;
  const dw = img ? img.naturalWidth * scale : 0;
  const dh = img ? img.naturalHeight * scale : 0;

  // The image must always cover the frame — no letterboxing into the crop.
  const clampTo = React.useCallback(
    (o: { x: number; y: number }, w: number, h: number) => ({
      x: Math.min(0, Math.max(FRAME_W - w, o.x)),
      y: Math.min(0, Math.max(frameH - h, o.y)),
    }),
    [frameH],
  );

  // Zoom and re-clamp in one handler so the offset never lands out of bounds.
  const applyZoom = React.useCallback((z: number) => {
    const nz = Math.min(6, Math.max(1, z));
    setZoom(nz);
    if (!img) return;
    const s = coverScale(img) * nz;
    setOffset((o) => clampTo(o, img.naturalWidth * s, img.naturalHeight * s));
  }, [img, coverScale, clampTo]);

  function onPointerDown(e: React.PointerEvent) {
    (e.target as Element).setPointerCapture(e.pointerId);
    drag.current = { x: e.clientX, y: e.clientY, ox: offset.x, oy: offset.y };
  }
  function onPointerMove(e: React.PointerEvent) {
    if (!drag.current) return;
    setOffset(clampTo({
      x: drag.current.ox + (e.clientX - drag.current.x),
      y: drag.current.oy + (e.clientY - drag.current.y),
    }, dw, dh));
  }
  function onPointerUp() { drag.current = null; }

  /**
   * Render exactly what's framed to a canvas at the placement's master size.
   *
   * This is the "resize to the needed resolution" path. Normally we hand the
   * server the untouched original plus a rect (see the note on this component)
   * because that keeps every source pixel. But the server hard-rejects anything
   * below the placement minimum, which left a slightly-undersized image with
   * nowhere to go. Resizing here produces a file that is, by construction,
   * exactly the required resolution.
   *
   * Upscaling cannot invent detail — the dialog says so plainly before this runs.
   */
  function exportResized(): Promise<File> {
    return new Promise((resolve, reject) => {
      if (!img) return reject(new Error("no image"));
      const nw = img.naturalWidth;
      const nh = img.naturalHeight;
      // Source rect currently under the frame, in natural pixels.
      const sx = -offset.x / scale;
      const sy = -offset.y / scale;
      const sw = FRAME_W / scale;
      const sh = frameH / scale;
      const canvas = document.createElement("canvas");
      canvas.width = minWidth;
      canvas.height = minHeight;
      const ctx = canvas.getContext("2d");
      if (!ctx) return reject(new Error("no ctx"));
      ctx.imageSmoothingEnabled = true;
      ctx.imageSmoothingQuality = "high";
      ctx.drawImage(
        img,
        Math.max(0, sx), Math.max(0, sy),
        Math.min(sw, nw), Math.min(sh, nh),
        0, 0, minWidth, minHeight,
      );
      canvas.toBlob(
        (b) => {
          if (!b) return reject(new Error("toBlob failed"));
          const base = file.name.replace(/\.[^.]+$/, "");
          resolve(new File([b], `${base}-${minWidth}x${minHeight}.webp`, {
            type: "image/webp",
          }));
        },
        "image/webp",
        0.92,
      );
    });
  }

  async function useResized() {
    setResizing(true);
    try {
      const resized = await exportResized();
      // The canvas already applied the crop, so the server must take the whole
      // frame — passing the original rect would crop a second time.
      onDone({ x: 0, y: 0, w: 1, h: 1 }, resized);
    } catch {
      setResizing(false);
    }
  }

  /** Map the on-screen frame back to a normalized rect on the source image. */
  function toRect(): CropRect {
    if (!img) return { x: 0, y: 0, w: 1, h: 1 };
    const nw = img.naturalWidth;
    const nh = img.naturalHeight;
    const clamp01 = (v: number) => Math.min(1, Math.max(0, v));
    const x = clamp01(-offset.x / scale / nw);
    const y = clamp01(-offset.y / scale / nh);
    // Keep the rect inside the image; the frame is always covered, so the
    // remaining width/height can only be trimmed by rounding.
    return {
      x, y,
      w: Math.min(1 - x, clamp01(FRAME_W / scale / nw)),
      h: Math.min(1 - y, clamp01(frameH / scale / nh)),
    };
  }

  const tooSmall = !!img && (img.naturalWidth < minWidth || img.naturalHeight < minHeight);

  return (
    <Dialog open onOpenChange={(o) => !o && onCancel()}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>Crop for {placementLabel}</DialogTitle>
        </DialogHeader>

        <p className="text-xs text-muted-foreground">
          Locked to <strong>{aspectLabel}</strong> — exactly how this slot renders in the
          app. Drag to reposition, scroll or use −/＋ to zoom. Saved at{" "}
          {minWidth}×{minHeight}px.
        </p>

        {tooSmall && (
          <div className="flex items-start gap-2 rounded-md border border-amber-500/40 bg-amber-500/10 p-2 text-xs text-amber-700 dark:text-amber-400">
            <AlertTriangle className="mt-0.5 size-4 shrink-0" />
            <span>
              This image is {img?.naturalWidth}×{img?.naturalHeight}px — below the{" "}
              {minWidth}×{minHeight}px minimum. Use{" "}
              <strong>Resize to {minWidth}×{minHeight}</strong> to upload it anyway,
              but it will be scaled up and will look softer than a larger source.
            </span>
          </div>
        )}

        <div
          className="relative mx-auto touch-none overflow-hidden rounded-lg border bg-muted"
          style={{ width: FRAME_W, height: frameH }}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onWheel={(e) => applyZoom(zoom - e.deltaY * 0.001)}
        >
          {img ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              src={img.src}
              alt=""
              draggable={false}
              className="pointer-events-none absolute max-w-none select-none"
              style={{ left: offset.x, top: offset.y, width: dw, height: dh }}
            />
          ) : (
            <div className="grid size-full place-items-center">
              <Loader2 className="size-5 animate-spin text-muted-foreground" />
            </div>
          )}
          {/* Rule-of-thirds guides + the safe area for overlay copy. */}
          <div className="pointer-events-none absolute inset-0">
            <div className="absolute inset-y-0 left-1/3 w-px bg-white/30" />
            <div className="absolute inset-y-0 left-2/3 w-px bg-white/30" />
            <div className="absolute inset-x-0 top-1/3 h-px bg-white/30" />
            <div className="absolute inset-x-0 top-2/3 h-px bg-white/30" />
            <div className="absolute inset-[6%] rounded border border-dashed border-white/50" />
          </div>
        </div>

        <div className="flex items-center gap-3">
          <Button type="button" variant="outline" size="icon" className="size-8"
                  onClick={() => applyZoom(zoom - 0.2)}>
            <Minus className="size-4" />
          </Button>
          <input
            type="range" min={1} max={6} step={0.01} value={zoom}
            onChange={(e) => applyZoom(Number(e.target.value))}
            className="flex-1 accent-[var(--color-primary)]"
          />
          <Button type="button" variant="outline" size="icon" className="size-8"
                  onClick={() => applyZoom(zoom + 0.2)}>
            <Plus className="size-4" />
          </Button>
          <Button type="button" variant="ghost" size="icon" className="size-8"
                  title="Reset crop"
                  onClick={() => img && reset(img, null)}>
            <RotateCcw className="size-4" />
          </Button>
        </div>

        <p className="text-center text-[11px] text-muted-foreground">
          Dashed area = safe zone. Keep faces, logos and prices inside it — the app
          rounds the corners and overlays the headline at the bottom.
        </p>

        <DialogFooter className="gap-2 sm:gap-2">
          <Button type="button" variant="outline" onClick={onCancel}>Cancel</Button>
          {/* Always offered, not just for undersized images: it also lets an
              operator ship an exact-resolution file when they'd rather not
              upload a 12MP original over a slow connection. */}
          <Button
            type="button"
            variant={tooSmall ? "default" : "outline"}
            onClick={useResized}
            disabled={!img || resizing}
          >
            {resizing && <Loader2 className="mr-2 size-4 animate-spin" />}
            Resize to {minWidth}×{minHeight}
          </Button>
          <Button
            type="button"
            onClick={() => onDone(toRect())}
            disabled={!img || tooSmall || resizing}
          >
            Use this crop
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
