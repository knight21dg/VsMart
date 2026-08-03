// Shared API types mirroring the VS Mart backend contract.

export type Role = "superadmin" | "admin" | "agent" | "customer";

export interface ApiUser {
  id: string;
  phone: string;
  name: string;
  email?: string;
  role: Role;
  avatar_url?: string;
  kyc_status?: "not_started" | "pending" | "verified" | "rejected";
  credit_enabled?: boolean;
  created_at?: string;
}

/** Backend success envelope: { success, message, data, meta? }. */
export interface Envelope<T = unknown> {
  success: boolean;
  message?: string;
  data?: T;
  meta?: PageMeta | CursorMeta | Record<string, unknown>;
  // RFC 9457 error members (present on errors)
  error?: { code: string; message: string; fields?: Record<string, string[]> };
  detail?: string;
  status?: number;
}

// Admin endpoints render through the camelCase envelope, so meta keys are camelCase.
export interface PageMeta {
  page: number;
  pageSize: number;
  total: number;
  totalPages: number;
}

export interface CursorMeta {
  pageSize: number;
  nextCursor: string | null;
  previousCursor: string | null;
}

export interface Paged<T> {
  rows: T[];
  meta?: PageMeta | CursorMeta;
}

/** Typed error thrown by the API client. */
export class ApiError extends Error {
  code: string;
  status: number;
  fields?: Record<string, string[]>;
  constructor(message: string, opts: { code?: string; status?: number; fields?: Record<string, string[]> } = {}) {
    super(message);
    this.name = "ApiError";
    this.code = opts.code ?? "error";
    this.status = opts.status ?? 0;
    this.fields = opts.fields;
  }
}
