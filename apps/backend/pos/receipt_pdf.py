"""80mm thermal-style POS receipt PDF (reportlab). Reuses the `build_receipt`
payload so the printed receipt matches the JSON receipt exactly."""
from io import BytesIO

from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

from .services import build_receipt


def _money(v):
    return f"{float(v or 0):.2f}"


def build_pos_receipt_pdf(txn) -> bytes:
    """Render a POS transaction as a narrow (80mm) receipt PDF. Height grows with
    the line count so nothing clips."""
    r = build_receipt(txn)
    width = 80 * mm
    line_h = 4.2 * mm
    # Rough height budget: header + items + tax/tenders + footer.
    rows = 16 + len(r["items"]) + len(r["payments"])
    height = max(120 * mm, rows * line_h + 30 * mm)

    buf = BytesIO()
    c = canvas.Canvas(buf, pagesize=(width, height))
    x = 4 * mm
    right = width - 4 * mm
    y = height - 8 * mm

    def text(s, *, size=8, bold=False, center=False, rightal=False):
        nonlocal y
        c.setFont("Helvetica-Bold" if bold else "Helvetica", size)
        if center:
            c.drawCentredString(width / 2, y, s)
        elif rightal:
            c.drawRightString(right, y, s)
        else:
            c.drawString(x, y, s)
        y -= line_h

    def row(left, rightval, *, bold=False):
        nonlocal y
        c.setFont("Helvetica-Bold" if bold else "Helvetica", 8)
        c.drawString(x, y, left[:34])
        c.drawRightString(right, y, rightval)
        y -= line_h

    def rule():
        nonlocal y
        y += line_h * 0.4
        c.setDash(1, 2)
        c.line(x, y, right, y)
        c.setDash()
        y -= line_h * 0.8

    store = r["store"]
    text(store.get("name") or "VS Mart", size=11, bold=True, center=True)
    if store.get("address"):
        text(store["address"], size=7, center=True)
    line2 = " | ".join(filter(None, [
        f"GSTIN: {store['gstin']}" if store.get("gstin") else "",
        store.get("phone") or "",
    ]))
    if line2:
        text(line2, size=7, center=True)
    rule()

    text(f"Receipt: {r['receipt_no']}", size=8, bold=True)
    if r.get("datetime"):
        text(r["datetime"][:19].replace("T", " "), size=7)
    if r.get("type") and r["type"] != "sale":
        text(f"Type: {r['type'].upper()}", size=8, bold=True)
    rule()

    row("Item  Qty x Rate", "Amount", bold=True)
    for it in r["items"]:
        c.setFont("Helvetica", 8)
        c.drawString(x, y, str(it["name"])[:32])
        y -= line_h
        row(f"   {it['qty']} x {_money(it['rate'])}"
            + (f"  (-{_money(it['discount'])})" if it.get("discount") else ""),
            _money(it["amount"]))
    rule()

    row("Subtotal", _money(r["subtotal"]))
    if r.get("discount"):
        row("Discount", f"-{_money(r['discount'])}")
    tax = r["tax"]
    row("CGST", _money(tax["cgst"]))
    row("SGST", _money(tax["sgst"]))
    row("TOTAL", _money(r["total"]), bold=True)
    rule()

    for p in r["payments"]:
        label = f"Paid ({p['method']})" + (f" {p['reference']}" if p.get("reference") else "")
        row(label, _money(p["amount"]))
    if r.get("change_due"):
        row("Change", _money(r["change_due"]))
    rule()

    if r.get("is_voided"):
        text("*** VOIDED ***", size=10, bold=True, center=True)
    text(r.get("footer") or "Thank you!", size=8, center=True)

    c.showPage()
    c.save()
    return buf.getvalue()
