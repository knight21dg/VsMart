"""Branded, detailed VS Märt tax-invoice PDF (reportlab) — logo header, company +
store block, bill-to/ship-to, itemised lines with HSN + CGST/SGST split, totals,
amount-in-words, payment details, and terms."""
import io
import os

LOGO_PATH = os.path.join(os.path.dirname(__file__), "assets", "vsmart_logo.png")

# Last-resort display defaults, used only when neither the store nor the platform
# config supplies a value. Deliberately contains NO GSTIN: a tax identifier is
# never a sensible default (see `resolve_seller`).
COMPANY = {
    "name": "VS Märt — Groceries & Daily Needs",
    "email": "support@vsmart.app",
    "phone": "+91 90000 00000",
    "address": "VS Mart Retail Pvt. Ltd., Vijayawada, Andhra Pradesh",
}

TEAL = "#1D7D6E"
DARK = "#0F3D3A"
LIGHT = "#F2F7F5"

# Resolved at first build: a Unicode TTF (for the ₹ glyph) + the symbol to use.
_FONT = None
_FONT_BOLD = None
_RUPEE = "Rs. "


def _ensure_font():
    """Register a Unicode font that has the ₹ glyph (Windows Nirmala/Arial/Segoe,
    else a bundled DejaVu). Returns (regular, bold) font names, or Helvetica."""
    global _FONT, _FONT_BOLD, _RUPEE
    if _FONT is not None:
        return _FONT, _FONT_BOLD
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    pairs = [
        (r"C:\Windows\Fonts\Nirmala.ttf", r"C:\Windows\Fonts\NirmalaB.ttf"),
        (r"C:\Windows\Fonts\arial.ttf", r"C:\Windows\Fonts\arialbd.ttf"),
        (r"C:\Windows\Fonts\segoeui.ttf", r"C:\Windows\Fonts\segoeuib.ttf"),
    ]
    for reg, bold in pairs:
        if os.path.exists(reg):
            try:
                pdfmetrics.registerFont(TTFont("VSUni", reg))
                pdfmetrics.registerFont(TTFont("VSUni-Bold", bold if os.path.exists(bold) else reg))
                pdfmetrics.registerFontFamily(
                    "VSUni", normal="VSUni", bold="VSUni-Bold",
                    italic="VSUni", boldItalic="VSUni-Bold",
                )
                _FONT, _FONT_BOLD, _RUPEE = "VSUni", "VSUni-Bold", "₹"
                return _FONT, _FONT_BOLD
            except Exception:
                continue
    _FONT, _FONT_BOLD = "Helvetica", "Helvetica-Bold"  # ₹ unavailable → keep "Rs. "
    return _FONT, _FONT_BOLD


def _money(v):
    return f"{_RUPEE}{float(v or 0):,.2f}"


def resolve_seller(store):
    """Who is issuing this invoice: the serving store, falling back to the platform
    identity in ``PlatformConfig`` — never to a hardcoded placeholder.

    This matters most for a store selling its OWN private products: that store is
    the supplier on the invoice, so its GSTIN is the one that must be printed.

    ``gstin`` may come back empty. It previously fell back to a dummy value
    (``36ABCDE1234F1Z5``), which put a fabricated tax identifier on a document
    headed "TAX INVOICE" for every store that hadn't set one. Callers must treat an
    empty GSTIN as "not a tax invoice" (see :func:`is_tax_invoice`) rather than
    inventing one.
    """
    from siteconfig.models import PlatformConfig

    cfg = PlatformConfig.load()

    def pick(attr, cfg_value, default=""):
        return (getattr(store, attr, "") or "") or (cfg_value or "") or default

    return {
        "name": pick("name", cfg.store_name, COMPANY["name"]),
        "address": pick("address", cfg.store_address, COMPANY["address"]),
        "phone": pick("phone", cfg.support_phone, COMPANY["phone"]),
        "email": cfg.support_email or COMPANY["email"],
        # No default: absent means absent.
        "gstin": pick("gstin", cfg.store_gstin),
    }


def is_tax_invoice(seller) -> bool:
    """A GST tax invoice requires the supplier's GSTIN. Without one the document is
    still a valid bill of supply / receipt — it just may not claim to be a tax
    invoice, and no CGST/SGST breakdown should be presented as recoverable."""
    return bool(seller.get("gstin"))


def seller_block(seller) -> str:
    """The header address block. The GSTIN line is omitted entirely when unknown."""
    lines = [f"<b>{seller['name']}</b>", seller["address"]]
    contact = (
        f"GSTIN: {seller['gstin']} &nbsp; | &nbsp; {seller['phone']}"
        if seller["gstin"]
        else seller["phone"]
    )
    lines.append(contact)
    lines.append(seller["email"])
    return "<br/>".join(x for x in lines if x)


# ── Amount in words (Indian numbering) ───────────────────
_ONES = ["", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight",
         "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen",
         "Sixteen", "Seventeen", "Eighteen", "Nineteen"]
_TENS = ["", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy",
         "Eighty", "Ninety"]


def _two(n):
    if n < 20:
        return _ONES[n]
    return (_TENS[n // 10] + (" " + _ONES[n % 10] if n % 10 else "")).strip()


def _three(n):
    h = n // 100
    r = n % 100
    out = (_ONES[h] + " Hundred" if h else "")
    if r:
        out += (" " if out else "") + _two(r)
    return out


def rupees_in_words(amount) -> str:
    n = int(round(float(amount or 0)))
    if n == 0:
        return "Zero Rupees Only"
    parts = []
    crore, n = divmod(n, 10000000)
    lakh, n = divmod(n, 100000)
    thousand, n = divmod(n, 1000)
    hundred = n
    if crore:
        parts.append(_two(crore) + " Crore")
    if lakh:
        parts.append(_two(lakh) + " Lakh")
    if thousand:
        parts.append(_two(thousand) + " Thousand")
    if hundred:
        parts.append(_three(hundred))
    return " ".join(parts).strip() + " Rupees Only"


def build_invoice_pdf(order) -> bytes:
    from reportlab.lib import colors
    from reportlab.lib.enums import TA_RIGHT
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

    teal = colors.HexColor(TEAL)
    dark = colors.HexColor(DARK)
    light = colors.HexColor(LIGHT)

    buf = io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=A4, topMargin=14 * mm, bottomMargin=16 * mm,
        leftMargin=15 * mm, rightMargin=15 * mm, title=f"Invoice {order.code}",
    )
    font, font_bold = _ensure_font()
    s = getSampleStyleSheet()
    small = ParagraphStyle("small", parent=s["Normal"], fontSize=8, leading=11, fontName=font)
    smallR = ParagraphStyle("smallR", parent=small, alignment=TA_RIGHT)
    h_company = ParagraphStyle("co", parent=s["Normal"], fontSize=14,
                               textColor=dark, leading=16, fontName=font_bold)
    flow = []

    seller = resolve_seller(order.store)
    store_name = seller["name"]
    taxable_doc = is_tax_invoice(seller)

    # ── Header: logo + company ──
    logo = Image(LOGO_PATH, width=28 * mm, height=28 * mm) if os.path.exists(LOGO_PATH) else Paragraph("", small)
    company = Paragraph(seller_block(seller), small)
    header = Table([[logo, company]], colWidths=[32 * mm, 148 * mm])
    header.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (1, 0), (1, 0), 8),
    ]))
    flow.append(header)
    flow.append(Spacer(1, 6))

    # ── Title band ──
    title = Table(
        [[Paragraph(f"<b>{'TAX INVOICE' if taxable_doc else 'INVOICE'}</b>", ParagraphStyle("t", parent=s["Title"], fontSize=15, textColor=colors.white, fontName=font_bold)),
          Paragraph(f"<b>Invoice No:</b> {order.code}<br/><b>Date:</b> {order.placed_at:%d %b %Y, %I:%M %p}",
                    ParagraphStyle("tr", parent=smallR, textColor=colors.white))]],
        colWidths=[110 * mm, 70 * mm],
    )
    title.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), teal),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 6), ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ("LEFTPADDING", (0, 0), (0, 0), 10), ("RIGHTPADDING", (1, 0), (1, 0), 10),
    ]))
    flow.append(title)
    flow.append(Spacer(1, 8))

    # ── Bill To / Ship To / meta ──
    addr = order.address_snapshot or {}
    cust = order.user
    bill = Paragraph(
        f"<b>Bill To</b><br/>{(cust.name if cust else '') or addr.get('name', '')}<br/>"
        f"{(cust.phone if cust else '') or addr.get('phone', '')}", small)
    ship = Paragraph(
        f"<b>Ship To</b><br/>{addr.get('name', '')}<br/>{addr.get('formatted', '')}<br/>"
        f"{('PIN ' + addr.get('pincode', '')) if addr.get('pincode') else ''}", small)
    meta = Paragraph(
        f"<b>Order Status:</b> {order.status}<br/>"
        f"<b>Payment:</b> {order.payment_method.upper()} ({order.payment_status})<br/>"
        f"<b>Zone:</b> {order.zone.name if order.zone else '-'}", small)
    box = Table([[bill, ship, meta]], colWidths=[60 * mm, 65 * mm, 55 * mm])
    box.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#D7E3DF")),
        ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#D7E3DF")),
        ("BACKGROUND", (0, 0), (-1, -1), light),
        ("TOPPADDING", (0, 0), (-1, -1), 7), ("BOTTOMPADDING", (0, 0), (-1, -1), 7),
        ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ]))
    flow.append(box)
    flow.append(Spacer(1, 10))

    # ── Items with HSN + line tax ──
    gst_total = float(order.gst or 0)
    subtotal = float(order.subtotal or 0)
    discount = float(order.discount or 0)
    # GST is levied on the FULL subtotal (see core.pricing.compute_bill), so that is
    # the taxable value to print. Deducting the coupon discount first both
    # understated the taxable value and inflated the derived rate (a 5% order with a
    # 20% coupon printed "CGST @ 3.13%"), and left the totals column summing to
    # `total - discount` because Discount was ALSO listed as a separate deduction.
    taxable_total = subtotal
    rate_pct = round(gst_total / taxable_total * 100) if taxable_total else 0
    data = [["#", "Item Description", "HSN", "Qty", "MRP", "Rate", "Disc", "Taxable", "Amount"]]
    for i, it in enumerate(order.items.select_related("product").all(), 1):
        line = float(it.price) * it.quantity
        disc = (float(it.mrp) - float(it.price)) * it.quantity
        # No invented HSN. The old "2106" fallback classified every product without
        # a code as instant food — which is most store-created private products,
        # since HSN is optional in the store panel's add-product form.
        hsn = getattr(getattr(it, "product", None), "hsn", "") or "—"
        data.append([
            str(i), it.name, hsn, str(it.quantity), _money(it.mrp), _money(it.price),
            _money(disc), _money(line), _money(line),
        ])
    items = Table(data, colWidths=[8 * mm, 56 * mm, 14 * mm, 11 * mm, 20 * mm, 20 * mm, 18 * mm, 20 * mm, 20 * mm], repeatRows=1)
    items.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), dark),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTSIZE", (0, 0), (-1, -1), 7.5),
        ("FONTNAME", (0, 0), (-1, -1), font),
        ("FONTNAME", (0, 0), (-1, 0), font_bold),
        ("ALIGN", (3, 0), (-1, -1), "RIGHT"),
        ("ALIGN", (0, 0), (0, -1), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#CBD9D4")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, light]),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]))
    flow.append(items)
    flow.append(Spacer(1, 8))

    # ── Totals (right) ──
    # These rows must ADD UP to the Grand Total, so a customer (or an auditor) can
    # reconcile the invoice by reading down the column:
    #   subtotal + CGST + SGST + delivery + platform − discount = total
    # which is exactly `compute_bill`'s formula.
    cgst = round(gst_total / 2, 2)
    sgst = round(gst_total - cgst, 2)
    rows = [["Taxable Value", _money(taxable_total)]]
    if taxable_doc:
        rows += [
            [f"CGST @ {rate_pct / 2:g}%", _money(cgst)],
            [f"SGST @ {rate_pct / 2:g}%", _money(sgst)],
        ]
    else:
        # No GSTIN → the tax collected isn't presented as a recoverable CGST/SGST
        # split, but it is still part of what the customer paid, so it stays visible.
        rows.append(["Tax", _money(gst_total)])
    rows += [
        ["Delivery Charge", _money(order.delivery_fee)],
        ["Platform Fee", _money(order.platform_fee)],
    ]
    if discount:
        rows.append(["Discount", f"- {_money(discount)}"])
    rows.append(["Grand Total", _money(order.total)])
    totals = Table(rows, colWidths=[40 * mm, 30 * mm], hAlign="RIGHT")
    totals.setStyle(TableStyle([
        ("ALIGN", (0, 0), (-1, -1), "RIGHT"),
        ("FONTSIZE", (0, 0), (-1, -1), 8.5),
        ("FONTNAME", (0, 0), (-1, -1), font),
        ("LINEABOVE", (0, -1), (-1, -1), 1, dark),
        ("BACKGROUND", (0, -1), (-1, -1), teal),
        ("TEXTCOLOR", (0, -1), (-1, -1), colors.white),
        ("FONTNAME", (0, -1), (-1, -1), font_bold),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 8), ("RIGHTPADDING", (0, 0), (-1, -1), 8),
    ]))
    flow.append(totals)
    flow.append(Spacer(1, 6))
    flow.append(Paragraph(f"<b>Amount in words:</b> {rupees_in_words(order.total)}", small))

    if order.payment_method == "credit" and order.credit_used:
        flow.append(Spacer(1, 4))
        due = f" · Due {order.credit_due_date:%d %b %Y}" if order.credit_due_date else ""
        flow.append(Paragraph(f"<b>VS Credit:</b> {_money(order.credit_used)} on the "
                              f"{(order.credit_plan or 'weekend').replace('_', ' ')} plan{due}", small))

    # ── Footer ──
    flow.append(Spacer(1, 16))
    foot = Table([[
        Paragraph("<b>Terms &amp; Conditions</b><br/>"
                  "1. Goods once sold are subject to our returns policy.<br/>"
                  "2. Perishables are non-returnable once delivered in good condition.<br/>"
                  "3. This is a computer-generated invoice and needs no signature.", small),
        Paragraph(f"<br/><br/><br/>For <b>{store_name}</b><br/>Authorised Signatory", smallR),
    ]], colWidths=[120 * mm, 60 * mm])
    foot.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]))
    flow.append(foot)
    flow.append(Spacer(1, 6))
    flow.append(Paragraph(
        "<para align='center'><font color='#1D7D6E'><b>Thank you for shopping with VS Märt!</b></font></para>",
        small))

    doc.build(flow)
    return buf.getvalue()
