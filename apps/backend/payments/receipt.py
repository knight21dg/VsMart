"""Payment receipt PDF — proof that a customer paid.

Order invoices already had a real PDF pipeline; credit repayments only fired a
snackbar, so a customer who repaid their credit line had **no document** to show
for it. This reuses the invoice pipeline's fonts, logo and seller resolution so
the two documents look like they came from the same company.

Deliberately a *receipt*, not a tax invoice: a repayment settles an existing
liability, it isn't a fresh supply, so there is no GST line to show.
"""
import io
import os

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    Image,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

from orders.invoice import (
    LOGO_PATH,
    _ensure_font,
    _money,
    resolve_seller,
    rupees_in_words,
    seller_block,
)

BRAND = colors.HexColor("#16A34A")
MUTED = colors.HexColor("#6B7280")

#: What a payment was for, in words a customer recognises.
PURPOSE_LABEL = {
    "repayment": "VS Credit repayment",
    "order": "Order payment",
    "refund": "Refund",
}
METHOD_LABEL = {
    "upi": "UPI", "card": "Card", "netbanking": "Net banking", "cash": "Cash",
}


def build_receipt_pdf(payment) -> bytes:
    """Render a one-page receipt for a completed [payment]."""
    font, font_bold = _ensure_font()
    styles = getSampleStyleSheet()
    normal = ParagraphStyle("n", parent=styles["Normal"], fontName=font,
                            fontSize=9.5, leading=13)
    small = ParagraphStyle("s", parent=normal, fontSize=8, textColor=MUTED)
    h1 = ParagraphStyle("h1", parent=normal, fontName=font_bold, fontSize=16,
                        leading=20)
    label = ParagraphStyle("l", parent=small, fontName=font)
    value = ParagraphStyle("v", parent=normal, fontName=font_bold)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=A4,
        leftMargin=15 * mm, rightMargin=15 * mm,
        topMargin=14 * mm, bottomMargin=14 * mm,
        title=f"Receipt {payment.id}",
    )
    story = []

    seller = resolve_seller(getattr(payment, "store", None))
    logo = (
        Image(LOGO_PATH, width=26 * mm, height=26 * mm)
        if os.path.exists(LOGO_PATH) else Paragraph("", small)
    )
    story.append(Table(
        [[logo, Paragraph(seller_block(seller), normal)]],
        colWidths=[30 * mm, 150 * mm],
        style=TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]),
    ))
    story.append(Spacer(1, 8 * mm))

    story.append(Paragraph("Payment Receipt", h1))
    story.append(Paragraph(
        "This is a receipt for a payment received. It is not a tax invoice.",
        small,
    ))
    story.append(Spacer(1, 6 * mm))

    customer = payment.user
    meta = [
        [Paragraph("Receipt no.", label), Paragraph(f"VSR-{payment.id:08d}", value),
         Paragraph("Received from", label), Paragraph(customer.name or "—", value)],
        [Paragraph("Date", label),
         Paragraph(payment.created_at.strftime("%d %b %Y, %I:%M %p"), value),
         Paragraph("Mobile", label), Paragraph(customer.phone or "—", value)],
        [Paragraph("Paid via", label),
         Paragraph(METHOD_LABEL.get(payment.method, payment.method.title()), value),
         Paragraph("Reference", label),
         Paragraph(payment.gateway_payment_id or payment.gateway_order_id or "—",
                   small)],
    ]
    story.append(Table(
        meta, colWidths=[26 * mm, 58 * mm, 28 * mm, 68 * mm],
        style=TableStyle([
            ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ]),
    ))
    story.append(Spacer(1, 7 * mm))

    purpose = PURPOSE_LABEL.get(payment.purpose, payment.purpose.title())
    detail = purpose
    if payment.order_id and getattr(payment.order, "code", None):
        detail = f"{purpose} — order {payment.order.code}"

    amount_rows = [
        [Paragraph("Description", ParagraphStyle("th", parent=small,
                                                 fontName=font_bold,
                                                 textColor=colors.white)),
         Paragraph("Amount", ParagraphStyle("thr", parent=small,
                                            fontName=font_bold,
                                            textColor=colors.white,
                                            alignment=2))],
        [Paragraph(detail, normal),
         Paragraph(_money(payment.amount),
                   ParagraphStyle("r", parent=value, alignment=2))],
        [Paragraph("Total received", value),
         Paragraph(_money(payment.amount),
                   ParagraphStyle("rb", parent=value, alignment=2))],
    ]
    story.append(Table(
        amount_rows, colWidths=[130 * mm, 50 * mm],
        style=TableStyle([
            ("BACKGROUND", (0, 0), (-1, 0), BRAND),
            ("LINEBELOW", (0, 1), (-1, 1), 0.4, colors.HexColor("#E5E7EB")),
            ("BACKGROUND", (0, 2), (-1, 2), colors.HexColor("#F3F4F6")),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ]),
    ))
    story.append(Spacer(1, 4 * mm))
    story.append(Paragraph(
        f"Amount in words: <b>{rupees_in_words(payment.amount)}</b>", normal))
    story.append(Spacer(1, 10 * mm))

    story.append(Paragraph(
        "Payment received and credited to your VS Mart account. "
        "Keep this receipt for your records.", small))
    story.append(Spacer(1, 12 * mm))
    story.append(Paragraph(
        "This is a computer-generated receipt and does not require a signature.",
        small))

    doc.build(story)
    return buf.getvalue()
