"""Branded A4 tax-invoice PDF for a POS sale — same look as the order invoice
(logo header, store block, bill-to, itemised lines with CGST/SGST split, totals,
amount-in-words, payment lines, terms), adapted to a POSTransaction.
"""
import io
import os

# Reuse the order invoice's fonts/helpers/branding so both invoices look identical.
from orders.invoice import (
    DARK,
    LIGHT,
    LOGO_PATH,
    TEAL,
    _ensure_font,
    _money,
    is_tax_invoice,
    resolve_seller,
    rupees_in_words,
    seller_block,
)


def build_pos_invoice_pdf(txn, store) -> bytes:
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
        leftMargin=15 * mm, rightMargin=15 * mm, title=f"Invoice {txn.code}",
    )
    font, font_bold = _ensure_font()
    s = getSampleStyleSheet()
    small = ParagraphStyle("small", parent=s["Normal"], fontSize=8, leading=11, fontName=font)
    smallR = ParagraphStyle("smallR", parent=small, alignment=TA_RIGHT)
    flow = []

    # The till's own store is the supplier — including for its private products.
    seller = resolve_seller(store)
    store_name = seller["name"]
    taxable_doc = is_tax_invoice(seller)

    # ── Header: logo + store ──
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
    kind = (
        "CREDIT NOTE"
        if txn.type == "return"
        else ("TAX INVOICE" if taxable_doc else "INVOICE")
    )
    title = Table(
        [[Paragraph(f"<b>{kind}</b>", ParagraphStyle("t", parent=s["Title"], fontSize=15, textColor=colors.white, fontName=font_bold)),
          Paragraph(f"<b>Invoice No:</b> {txn.code}<br/><b>Date:</b> {txn.created_at:%d %b %Y, %I:%M %p}",
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

    # ── Bill To + meta ──
    cust = txn.customer
    pay_methods = ", ".join(sorted({p.method.upper() for p in txn.payments.all()})) or "-"
    bill = Paragraph(
        f"<b>Bill To</b><br/>{(cust.name or cust.phone) if cust else 'Walk-in Customer'}<br/>"
        f"{cust.phone if cust else ''}", small)
    meta = Paragraph(
        f"<b>Type:</b> {txn.type.title()}<br/>"
        f"<b>Payment:</b> {pay_methods}<br/>"
        f"<b>Counter:</b> {store.code if store else '-'}", small)
    box = Table([[bill, meta]], colWidths=[110 * mm, 70 * mm])
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

    # ── Items ──
    # "Amount" is the PRE-TAX taxable value (rate×qty − disc); GST is added once in
    # the totals block below, so Subtotal + CGST + SGST = Grand Total reconciles.
    data = [["#", "Item Description", "Qty", "Rate", "Disc", "Amount"]]
    for i, it in enumerate(txn.items.all(), 1):
        taxable = float(it.unit_price) * it.quantity - float(it.discount or 0)
        data.append([
            str(i), it.name, str(it.quantity), _money(it.unit_price),
            _money(it.discount), _money(taxable),
        ])
    items = Table(data, colWidths=[8 * mm, 86 * mm, 16 * mm, 24 * mm, 22 * mm, 24 * mm], repeatRows=1)
    items.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), dark),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTSIZE", (0, 0), (-1, -1), 8),
        ("FONTNAME", (0, 0), (-1, -1), font),
        ("FONTNAME", (0, 0), (-1, 0), font_bold),
        ("ALIGN", (2, 0), (-1, -1), "RIGHT"),
        ("ALIGN", (0, 0), (0, -1), "CENTER"),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#CBD9D4")),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, light]),
        ("TOPPADDING", (0, 0), (-1, -1), 4), ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]))
    flow.append(items)
    flow.append(Spacer(1, 8))

    # ── Totals ──
    gst_total = float(txn.tax or 0)
    taxable_total = float(txn.subtotal or 0)
    bill_discount = float(txn.discount or 0)
    # Tax is levied per line on `unit_price×qty − line_discount`, summed into
    # `subtotal`; the BILL-level discount comes off after tax (see pos.services
    # .checkout). So the rate base is `subtotal` — netting the bill discount off it
    # first inflated the printed rate.
    rate_pct = round(gst_total / taxable_total * 100) if taxable_total else 0
    cgst = round(gst_total / 2, 2)
    sgst = round(gst_total - cgst, 2)
    rows = [["Subtotal", _money(taxable_total)]]
    if bill_discount:
        rows.append(["Discount", f"- {_money(bill_discount)}"])
    if taxable_doc:
        rows += [
            [f"CGST @ {rate_pct / 2:g}%", _money(cgst)],
            [f"SGST @ {rate_pct / 2:g}%", _money(sgst)],
        ]
    else:
        rows.append(["Tax", _money(gst_total)])
    rows.append(["Grand Total", _money(txn.total)])
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
    flow.append(Paragraph(f"<b>Amount in words:</b> {rupees_in_words(txn.total)}", small))

    # ── Payments ──
    if txn.payments.all():
        pay_lines = "  ·  ".join(f"{p.method.upper()} {_money(p.amount)}" for p in txn.payments.all())
        flow.append(Spacer(1, 4))
        flow.append(Paragraph(f"<b>Paid:</b> {pay_lines}"
                              + (f"  ·  <b>Change:</b> {_money(txn.change_due)}" if float(txn.change_due or 0) > 0 else ""), small))

    # ── Footer ──
    flow.append(Spacer(1, 16))
    foot = Table([[
        Paragraph("<b>Terms &amp; Conditions</b><br/>"
                  "1. Goods once sold are subject to our returns policy.<br/>"
                  "2. Perishables are non-returnable once sold in good condition.<br/>"
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
