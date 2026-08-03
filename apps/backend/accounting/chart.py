"""The default chart of accounts, and the codes the auto-posting hooks use.

Codes follow the conventional Indian retail layout so an accountant can read the
ledger without a translation guide:

    1xxx assets · 2xxx liabilities · 3xxx equity · 4xxx income · 5xxx expenses
"""

# code: (name, type, is_control, description)
DEFAULT_ACCOUNTS = [
    # ── Assets ──
    ("1000", "Cash on Hand", "asset", False,
     "Notes physically held at a store or office."),
    ("1010", "Cash with Agents", "asset", True,
     "Collected by field agents but not yet handed over."),
    ("1100", "Bank Account", "asset", False, "Funds in the business bank account."),
    ("1150", "Payment Gateway Receivable", "asset", True,
     "Captured by the gateway, not yet settled to the bank."),
    ("1200", "Accounts Receivable", "asset", True,
     "Owed by customers on VS Credit."),
    ("1300", "Inventory", "asset", True, "Stock on hand at cost."),
    ("1400", "GST Input Credit", "asset", False, "Recoverable GST paid on purchases."),

    # ── Liabilities ──
    ("2000", "Accounts Payable", "liability", True, "Owed to suppliers."),
    ("2100", "GST Payable", "liability", False, "GST collected and owed to the government."),
    ("2200", "Customer Wallet / Credits", "liability", False,
     "Value owed back to customers (coupons, refunds pending)."),

    # ── Equity ──
    ("3000", "Owner's Capital", "equity", False, "Capital introduced."),
    ("3100", "Retained Earnings", "equity", False,
     "Accumulated profit. Derived by the balance sheet, not posted directly."),

    # ── Income ──
    ("4000", "Sales Revenue", "income", False, "Goods sold, excluding GST."),
    ("4100", "Delivery Income", "income", False, "Delivery fees charged."),
    ("4200", "Interest & Late Fees", "income", False, "Charged on overdue credit."),
    ("4900", "Other Income", "income", False, "Anything not covered above."),

    # ── Expenses ──
    ("5000", "Cost of Goods Sold", "expense", True, "Cost of stock sold."),
    ("5100", "Discounts & Coupons", "expense", False,
     "Value given away through offers."),
    ("5200", "Delivery Costs", "expense", False, "Agent payouts and logistics."),
    ("5300", "Payment Gateway Fees", "expense", False, "Charged by the gateway."),
    ("5400", "Salaries & Wages", "expense", False, "Staff and agent salaries."),
    ("5500", "Rent & Utilities", "expense", False, "Premises costs."),
    ("5600", "Cash Shortage", "expense", False,
     "Cash counted short against what an agent declared."),
    ("5700", "Bad Debts", "expense", False, "Credit written off as unrecoverable."),
    ("5900", "Other Expenses", "expense", False, "Anything not covered above."),
]

# ── Codes the auto-posting hooks reference, named so the intent is readable ──
CASH_ON_HAND = "1000"
CASH_WITH_AGENTS = "1010"
BANK = "1100"
GATEWAY_RECEIVABLE = "1150"
ACCOUNTS_RECEIVABLE = "1200"
GST_INPUT = "1400"
ACCOUNTS_PAYABLE = "2000"
GST_PAYABLE = "2100"
SALES_REVENUE = "4000"
INVENTORY = "1300"
CASH_SHORTAGE = "5600"


def seed(stdout=None):
    """Create any missing accounts. Safe to re-run — existing rows are left
    exactly as they are, so a renamed or re-parented account isn't clobbered."""
    from .models import Account

    created = 0
    for code, name, type_, is_control, description in DEFAULT_ACCOUNTS:
        _, made = Account.objects.get_or_create(
            code=code,
            defaults={"name": name, "type": type_, "is_control": is_control,
                      "description": description},
        )
        if made:
            created += 1
            if stdout:
                stdout.write(f"  + {code} {name}")
    return created
