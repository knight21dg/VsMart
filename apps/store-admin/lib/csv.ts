export type CsvRow = Record<string, unknown>;

/** RFC-4180 cell escaping: quote when the value contains a comma, quote, or newline. */
function cell(value: unknown): string {
  if (value === null || value === undefined) return "";
  const s = String(value);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** Serialise rows to CSV text using an explicit column order. */
export function toCsv<T extends object>(columns: string[], rows: readonly T[]): string {
  const header = columns.map(cell).join(",");
  const body = rows.map((r) => columns.map((c) => cell((r as Record<string, unknown>)[c])).join(","));
  return [header, ...body].join("\r\n");
}

/**
 * Build a CSV from `rows` and trigger a browser download. Client-side only —
 * no server round-trip, so it exports exactly what's on screen.
 */
export function downloadCsv<T extends object>(filename: string, columns: string[], rows: readonly T[]): void {
  if (typeof window === "undefined") return;
  // BOM so Excel opens UTF-8 (₹, names) correctly.
  const blob = new Blob(["﻿" + toCsv(columns, rows)], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

/**
 * Parse RFC-4180 CSV text into rows of cells.
 *
 * Hand-rolled rather than pulling in a parser dependency: the format is small
 * and this is the exact set of cases a real spreadsheet export produces —
 * quoted fields, commas and NEWLINES inside quotes, "" escapes, CRLF or LF, and
 * Excel's UTF-8 BOM. A naive `split(",")` mangles every one of them, and an
 * address or product name with a comma in it is not an edge case.
 */
export function parseCsv(text: string): string[][] {
  // Excel prepends a BOM; left in place it corrupts the first header name.
  const src = text.replace(/^﻿/, "");
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;

  for (let i = 0; i < src.length; i++) {
    const c = src[i];

    if (quoted) {
      if (c === '"') {
        if (src[i + 1] === '"') { cell += '"'; i++; }  // "" -> a literal quote
        else quoted = false;                            // closing quote
      } else {
        cell += c;                                      // commas/newlines are data here
      }
      continue;
    }

    if (c === '"') { quoted = true; continue; }
    if (c === ",") { row.push(cell); cell = ""; continue; }
    if (c === "\r") continue;                           // CRLF -> handled on the \n
    if (c === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; continue; }
    cell += c;
  }
  // Flush the trailing cell/row (a file may not end with a newline).
  if (cell !== "" || row.length) { row.push(cell); rows.push(row); }
  // Drop blank trailing lines rather than importing a row of empty strings.
  return rows.filter((r) => r.some((v) => v.trim() !== ""));
}

/** Parse CSV into objects keyed by the header row (headers lower-cased/trimmed). */
export function parseCsvObjects(text: string): Record<string, string>[] {
  const rows = parseCsv(text);
  if (rows.length < 2) return [];
  const headers = rows[0].map((h) => h.trim().toLowerCase());
  return rows.slice(1).map((r) => {
    const o: Record<string, string> = {};
    headers.forEach((h, i) => { o[h] = (r[i] ?? "").trim(); });
    return o;
  });
}
