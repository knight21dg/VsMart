"""Credit statement PDF (reportlab).

A customer-facing statement for one billing cycle: account holder, period, the
opening→closing rollup, the ledger movements inside the window, and the amount
due. Reuses the invoice module's Unicode-font helper (for the ₹ glyph) rather
than duplicating the font-registration dance.
"""
import io

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

from orders.invoice import _ensure_font

TEAL = colors.HexColor("#1D7D6E")
DARK = colors.HexColor("#0F3D3A")
MUTED = colors.HexColor("#6B7A77")


def _money(rupee, amount):
    return f"{rupee}{amount:,.2f}"


def build_statement_pdf(statement) -> bytes:
    """Render `statement` to PDF bytes. Pulls the account's ledger rows within the
    statement window so the summary is backed by the actual movements."""
    from .models import CreditLedgerEntry

    font, font_bold = _ensure_font()
    # The rupee symbol resolved alongside the font (falls back to "Rs. ").
    from orders.invoice import _RUPEE as rupee

    account = statement.account
    user = account.user

    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=A4)
    width, height = A4
    x = 18 * mm
    y = height - 22 * mm

    # ── Header ──
    c.setFillColor(TEAL)
    c.setFont(font_bold, 20)
    c.drawString(x, y, "VS Märt")
    c.setFont(font, 10)
    c.setFillColor(MUTED)
    c.drawRightString(width - x, y, "CREDIT STATEMENT")
    y -= 7 * mm
    c.setStrokeColor(TEAL)
    c.setLineWidth(1)
    c.line(x, y, width - x, y)
    y -= 10 * mm

    # ── Account holder + period ──
    c.setFillColor(DARK)
    c.setFont(font_bold, 11)
    c.drawString(x, y, user.name or user.phone)
    c.setFont(font, 9)
    c.setFillColor(MUTED)
    c.drawRightString(
        width - x, y,
        f"Period: {statement.period_start:%d %b %Y} – {statement.period_end:%d %b %Y}",
    )
    y -= 5 * mm
    c.drawString(x, y, user.phone)
    c.drawRightString(width - x, y, f"Due: {statement.due_date:%d %b %Y}")
    y -= 5 * mm
    c.drawString(x, y, f"Statement #{statement.pk}")
    c.drawRightString(width - x, y, f"Status: {statement.get_status_display()}")
    y -= 12 * mm

    # ── Summary rollup ──
    c.setFillColor(DARK)
    c.setFont(font_bold, 11)
    c.drawString(x, y, "Summary")
    y -= 7 * mm
    c.setFont(font, 10)
    rows = [
        ("Opening balance", statement.opening_balance),
        ("Purchases", statement.purchases),
        ("Payments", -statement.payments),
        ("Fees", statement.fees),
    ]
    for label, amount in rows:
        c.setFillColor(MUTED)
        c.drawString(x, y, label)
        c.setFillColor(DARK)
        c.drawRightString(width - x, y, _money(rupee, amount))
        y -= 6 * mm

    y -= 2 * mm
    c.setStrokeColor(colors.HexColor("#D6E2DF"))
    c.line(x, y, width - x, y)
    y -= 7 * mm
    c.setFont(font_bold, 12)
    c.setFillColor(DARK)
    c.drawString(x, y, "Amount due")
    c.setFillColor(TEAL)
    c.drawRightString(width - x, y, _money(rupee, statement.closing_balance))
    y -= 14 * mm

    # ── Movements inside the window ──
    entries = list(
        CreditLedgerEntry.objects.filter(
            account=account,
            created_at__date__gte=statement.period_start,
            created_at__date__lte=statement.period_end,
        ).order_by("created_at")
    )
    if entries:
        c.setFont(font_bold, 11)
        c.setFillColor(DARK)
        c.drawString(x, y, "Transactions")
        y -= 7 * mm
        c.setFont(font, 9)
        for entry in entries:
            if y < 25 * mm:  # new page when we run out of room
                c.showPage()
                y = height - 22 * mm
                c.setFont(font, 9)
            c.setFillColor(MUTED)
            c.drawString(x, y, f"{entry.created_at:%d %b}")
            c.setFillColor(DARK)
            label = entry.note or entry.get_type_display()
            c.drawString(x + 22 * mm, y, label[:52])
            c.drawRightString(width - x, y, _money(rupee, entry.amount))
            y -= 5.5 * mm

    # ── Footer ──
    c.setFont(font, 8)
    c.setFillColor(MUTED)
    c.drawCentredString(
        width / 2, 15 * mm,
        "This is a system-generated statement. Credit is provided via VS Mart's "
        "NBFC/LSP lending partner.",
    )

    c.showPage()
    c.save()
    return buf.getvalue()
