"""Invoice PDF generation.

``generate_invoice_pdf(invoice)`` renders an A4 invoice PDF with reportlab,
stores it in ``default_storage`` under a deterministic key, writes that key onto
``invoice.pdf_key`` and returns it. Regenerating overwrites the same key, so the
operation is idempotent.
"""
from decimal import Decimal
from io import BytesIO

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas

ZERO = Decimal("0.00")


def _money(value):
    try:
        return f"Rs. {Decimal(value):,.2f}"
    except Exception:
        return f"Rs. {value}"


def _draw_invoice(buf, invoice):
    width, height = A4
    c = canvas.Canvas(buf, pagesize=A4)

    left = 20 * mm
    right = width - 20 * mm
    y = height - 25 * mm

    # Header
    c.setFillColor(colors.HexColor("#1f7a4d"))
    c.setFont("Helvetica-Bold", 24)
    c.drawString(left, y, "VS Mart")
    c.setFillColor(colors.black)
    c.setFont("Helvetica", 10)
    c.drawRightString(right, y, "TAX INVOICE")
    y -= 6 * mm
    c.setStrokeColor(colors.HexColor("#1f7a4d"))
    c.setLineWidth(1.2)
    c.line(left, y, right, y)
    y -= 12 * mm

    # Invoice meta
    c.setFont("Helvetica-Bold", 11)
    c.drawString(left, y, f"Invoice No: {invoice.number or invoice.pk}")
    c.setFont("Helvetica", 10)
    issued = invoice.issued_at or invoice.created_at
    date_str = issued.strftime("%d %b %Y, %H:%M") if issued else "-"
    c.drawString(left, y - 6 * mm, f"Date: {date_str}")
    c.drawString(left, y - 12 * mm, f"Status: {invoice.get_status_display()}")
    c.drawRightString(
        right, y, f"Billed to: {getattr(invoice.user, 'name', '') or invoice.user.phone}"
    )
    y -= 24 * mm

    # Line-items table header
    col_name = left
    col_qty = left + 95 * mm
    col_price = left + 125 * mm
    col_total = right

    c.setFillColor(colors.HexColor("#eef5f0"))
    c.rect(left - 2 * mm, y - 2 * mm, (right - left) + 4 * mm, 8 * mm, fill=1, stroke=0)
    c.setFillColor(colors.black)
    c.setFont("Helvetica-Bold", 10)
    c.drawString(col_name, y, "Item")
    c.drawRightString(col_qty, y, "Qty")
    c.drawRightString(col_price, y, "Price")
    c.drawRightString(col_total, y, "Amount")
    y -= 10 * mm

    c.setFont("Helvetica", 10)
    items = list(invoice.items.all())
    if not items:
        c.drawString(col_name, y, "(no line items)")
        y -= 8 * mm
    for item in items:
        if y < 40 * mm:
            c.showPage()
            y = height - 25 * mm
            c.setFont("Helvetica", 10)
        line_total = (Decimal(item.price) * item.quantity).quantize(Decimal("0.01"))
        c.drawString(col_name, y, str(item.name)[:60])
        c.drawRightString(col_qty, y, str(item.quantity))
        c.drawRightString(col_price, y, _money(item.price))
        c.drawRightString(col_total, y, _money(line_total))
        y -= 7 * mm

    # Totals
    y -= 4 * mm
    c.setStrokeColor(colors.grey)
    c.setLineWidth(0.5)
    c.line(col_price - 10 * mm, y, right, y)
    y -= 8 * mm

    gst = getattr(invoice, "gst", ZERO) or ZERO
    if gst:
        c.setFont("Helvetica", 10)
        c.drawRightString(col_price, y, "GST")
        c.drawRightString(col_total, y, _money(gst))
        y -= 7 * mm

    c.setFont("Helvetica-Bold", 12)
    c.drawRightString(col_price, y, "Total")
    c.drawRightString(col_total, y, _money(invoice.amount))

    # Footer
    c.setFont("Helvetica-Oblique", 8)
    c.setFillColor(colors.grey)
    c.drawCentredString(
        width / 2, 15 * mm, "VS Mart - This is a computer generated invoice."
    )

    c.showPage()
    c.save()


def _store_overwrite(key, data) -> str:
    """Write ``data`` to ``key`` in default_storage at exactly that key.

    FileSystemStorage.save() refuses to clobber an existing name (it appends a
    random suffix), so for idempotency we delete first. On some platforms
    (Windows) a stale/open handle can make delete raise; in that case we
    truncate-and-rewrite the underlying path in place when the storage exposes a
    filesystem path, so the same deterministic key keeps a single fresh file.
    """
    if default_storage.exists(key):
        try:
            default_storage.delete(key)
        except OSError:
            try:
                path = default_storage.path(key)
            except (NotImplementedError, AttributeError):
                path = None
            if path:
                with open(path, "wb") as fh:
                    fh.write(data)
                return key
            # Last resort: let save() pick a new (suffixed) name.
            return default_storage.save(key, ContentFile(data))
    return default_storage.save(key, ContentFile(data))


def generate_invoice_pdf(invoice) -> str:
    """Render the invoice to a PDF, store it, set ``invoice.pdf_key`` and return
    the storage key. Idempotent: writes to a deterministic key, replacing any
    existing file at that key."""
    buf = BytesIO()
    _draw_invoice(buf, invoice)
    pdf_bytes = buf.getvalue()

    key = f"invoices/{invoice.number or invoice.pk}.pdf"
    saved_key = _store_overwrite(key, pdf_bytes)

    invoice.pdf_key = saved_key
    invoice.save(update_fields=["pdf_key"])
    return saved_key


# ── row creation (the half of this module that never existed) ────────────────
#
# Everything downstream — the customer invoices screen, the receipts list, the
# lazy PDF pipeline above — was fully built and permanently EMPTY, because no
# code ever created an Invoice or Receipt row. The app read an eternally-blank
# list. These two are the producers, hooked into order delivery and payment
# settlement (both fail-soft at the call sites: paperwork must never break the
# money flow it documents).

def invoice_for_order(order):
    """The ISSUED invoice row for a delivered order. Idempotent per order —
    a replayed delivery transition must not double-invoice."""
    from django.utils import timezone

    from .models import Invoice, InvoiceItem

    existing = Invoice.objects.filter(order=order).first()
    if existing is not None:
        return existing
    invoice = Invoice.objects.create(
        user=order.user,
        order=order,
        amount=order.total,
        gst=order.gst,
        status=Invoice.Status.ISSUED,
        issued_at=timezone.now(),
    )
    for item in order.items.all():
        InvoiceItem.objects.create(
            invoice=invoice, name=item.name,
            quantity=item.quantity, price=item.price,
        )
    return invoice


def receipt_for_payment(payment):
    """The receipt row for a SUCCESSFUL payment. Idempotent per payment."""
    from django.utils import timezone

    from .models import Receipt

    existing = Receipt.objects.filter(payment=payment).first()
    if existing is not None:
        return existing
    return Receipt.objects.create(
        user=payment.user,
        payment=payment,
        amount=payment.amount,
        method=payment.method,
        issued_at=timezone.now(),
    )
