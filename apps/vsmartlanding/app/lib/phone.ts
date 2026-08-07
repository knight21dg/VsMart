// Indian mobile normalisation, mirroring `accounts.serializers.normalize_phone`
// on the backend: numbers are stored E.164 (`+919876543210`).

/**
 * Normalise user input to E.164, or return `null` when it isn't a valid Indian
 * mobile number. Accepts `9876543210`, `09876543210`, `+91 98765 43210`, etc.
 */
export function normalizeIndianMobile(raw: string): string | null {
  const digits = (raw || "").replace(/\D/g, "");
  let local = digits;
  if (local.length === 12 && local.startsWith("91")) local = local.slice(2);
  else if (local.length === 11 && local.startsWith("0")) local = local.slice(1);
  // Indian mobile numbers are 10 digits starting 6–9.
  if (!/^[6-9]\d{9}$/.test(local)) return null;
  return `+91${local}`;
}

/** `+919876543210` → `+91 98765 43210` for display. */
export function formatIndianMobile(phone: string): string {
  const m = /^\+91(\d{5})(\d{5})$/.exec(phone || "");
  return m ? `+91 ${m[1]} ${m[2]}` : phone;
}
