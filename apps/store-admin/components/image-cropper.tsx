"use client";

import * as React from "react";
import { Loader2, Minus, Plus } from "lucide-react";
import {
  Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

const FRAME = 320; // on-screen crop frame (square), px
const OUT = 1024; // exported square size, px

/**
 * Crop each selected image to a perfect 1:1 square, one at a time.
 *
 * The user pans (drag) and zooms (buttons / wheel / slider) the image inside a
 * fixed square frame; on "Next"/"Done" the framed region is drawn to a square
 * canvas and returned as a WebP blob. Enforces 1:1 for every image so the
 * product gallery is uniform.
 */
export function ImageCropDialog({ files, onComplete, onCancel }: {
  files: File[];
  onComplete: (blobs: Blob[]) => void;
  onCancel: () => void;
}) {
  const [index, setIndex] = React.useState(0);
  const [img, setImg] = React.useState<HTMLImageElement | null>(null);
  const [zoom, setZoom] = React.useState(1);
  const [offset, setOffset] = React.useState({ x: 0, y: 0 });
  const results = React.useRef<Blob[]>([]);
  const drag = React.useRef<{ x: number; y: number; ox: number; oy: number } | null>(null);

  const file = files[index];

  // Load the current file and reset the view to centered cover.
  React.useEffect(() => {
    if (!file) return;
    const url = URL.createObjectURL(file);
    const image = new Image();
    image.onload = () => {
      setImg(image);
      setZoom(1);
      // Center the cover-fit image in the frame.
      const cover = FRAME / Math.min(image.naturalWidth, image.naturalHeight);
      setOffset({
        x: (FRAME - image.naturalWidth * cover) / 2,
        y: (FRAME - image.naturalHeight * cover) / 2,
      });
    };
    image.src = url;
    return () => URL.revokeObjectURL(url);
  }, [file]);

  const cover = img ? FRAME / Math.min(img.naturalWidth, img.naturalHeight) : 1;
  const scale = cover * zoom;
  const dw = img ? img.naturalWidth * scale : 0;
  const dh = img ? img.naturalHeight * scale : 0;

  const clamp = React.useCallback(
    (o: { x: number; y: number }) => ({
      x: Math.min(0, Math.max(FRAME - dw, o.x)),
      y: Math.min(0, Math.max(FRAME - dh, o.y)),
    }),
    [dw, dh],
  );

  // Change zoom AND re-clamp the offset for the new size in one handler (no effect).
  const applyZoom = React.useCallback((z: number) => {
    const nz = Math.min(5, Math.max(1, z));
    setZoom(nz);
    if (!img) return;
    const s = (FRAME / Math.min(img.naturalWidth, img.naturalHeight)) * nz;
    const w = img.naturalWidth * s;
    const h = img.naturalHeight * s;
    setOffset((o) => ({
      x: Math.min(0, Math.max(FRAME - w, o.x)),
      y: Math.min(0, Math.max(FRAME - h, o.y)),
    }));
  }, [img]);

  function onPointerDown(e: React.PointerEvent) {
    (e.target as Element).setPointerCapture(e.pointerId);
    drag.current = { x: e.clientX, y: e.clientY, ox: offset.x, oy: offset.y };
  }
  function onPointerMove(e: React.PointerEvent) {
    if (!drag.current) return;
    setOffset(clamp({
      x: drag.current.ox + (e.clientX - drag.current.x),
      y: drag.current.oy + (e.clientY - drag.current.y),
    }));
  }
  function onPointerUp() { drag.current = null; }

  function exportSquare(): Promise<Blob> {
    return new Promise((resolve, reject) => {
      if (!img) return reject(new Error("no image"));
      const sSize = FRAME / scale;                // source square side (px)
      const sx = -offset.x / scale;
      const sy = -offset.y / scale;
      const canvas = document.createElement("canvas");
      canvas.width = OUT;
      canvas.height = OUT;
      const ctx = canvas.getContext("2d");
      if (!ctx) return reject(new Error("no ctx"));
      ctx.imageSmoothingQuality = "high";
      ctx.drawImage(img, sx, sy, sSize, sSize, 0, 0, OUT, OUT);
      canvas.toBlob(
        (b) => (b ? resolve(b) : reject(new Error("toBlob failed"))),
        "image/webp",
        0.9,
      );
    });
  }

  async function next() {
    const blob = await exportSquare();
    results.current.push(blob);
    if (index + 1 < files.length) {
      setIndex((i) => i + 1);
    } else {
      onComplete(results.current);
    }
  }

  return (
    <Dialog open onOpenChange={(o) => !o && onCancel()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle>
            Crop image {index + 1} of {files.length}
          </DialogTitle>
        </DialogHeader>

        <p className="text-xs text-muted-foreground">Drag to reposition · pinch/scroll or use −/＋ to zoom. Every image is saved as a 1:1 square.</p>

        <div
          className="relative mx-auto touch-none overflow-hidden rounded-lg border bg-muted"
          style={{ width: FRAME, height: FRAME }}
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
            <div className="grid size-full place-items-center"><Loader2 className="size-5 animate-spin text-muted-foreground" /></div>
          )}
          {/* Framing guides */}
          <div className="pointer-events-none absolute inset-0 border-2 border-white/70" />
        </div>

        <div className="flex items-center gap-3">
          <Button type="button" variant="outline" size="icon" className="size-8" onClick={() => applyZoom(zoom - 0.2)}><Minus className="size-4" /></Button>
          <input
            type="range" min={1} max={5} step={0.01} value={zoom}
            onChange={(e) => applyZoom(Number(e.target.value))}
            className="flex-1 accent-[var(--color-primary)]"
          />
          <Button type="button" variant="outline" size="icon" className="size-8" onClick={() => applyZoom(zoom + 0.2)}><Plus className="size-4" /></Button>
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={onCancel}>Cancel</Button>
          <Button type="button" onClick={next} disabled={!img}>
            {index + 1 < files.length ? "Next image" : "Done"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
