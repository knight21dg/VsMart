"""The Store-Admin panel permission catalog.

A single source of truth for the permission KEYS the panel understands, the
human labels (for the "assign permissions" UI), and the default permission
bundle granted to each built-in staff role. The Store Admin (``manager``)
implicitly holds every permission; ``custom`` staff hold exactly the keys a
manager assigns.

Keys are ``module.action``. ``view`` gates read access to a module; ``manage``
gates the write/operational actions inside it.
"""

# ── Permission keys grouped by module (order = sidebar order) ────────────
PERMISSION_GROUPS = [
    {
        "module": "Dashboard",
        "permissions": [
            ("dashboard.view", "View dashboard & KPIs"),
        ],
    },
    {
        "module": "Orders",
        "permissions": [
            ("orders.view", "View orders"),
            ("orders.manage", "Confirm / pack / cancel / refund orders"),
            ("returns.manage", "Process returns & refunds"),
        ],
    },
    {
        "module": "Inventory",
        "permissions": [
            ("inventory.view", "View stock, low-stock & expiry"),
            ("inventory.manage", "Adjust stock, mark waste, set reorder levels"),
        ],
    },
    {
        "module": "Procurement",
        "permissions": [
            ("procurement.view", "View suppliers & purchases"),
            ("procurement.manage", "Add suppliers, record purchases, upload invoices"),
        ],
    },
    {
        "module": "Customers",
        "permissions": [
            ("customers.view", "View store customers"),
            ("credit.view", "View credit & outstanding"),
            ("credit.manage", "Change limits, freeze credit"),
            ("verification.view", "View KYC queue"),
            ("verification.manage", "Approve / reject KYC"),
        ],
    },
    {
        "module": "Operations",
        "permissions": [
            ("delivery.view", "View delivery board"),
            ("delivery.manage", "Assign agents, update delivery status"),
            ("collections.view", "View collection queue"),
            ("collections.manage", "Assign & record collections"),
        ],
    },
    {
        "module": "Point of Sale",
        "permissions": [
            ("pos.operate", "Operate the POS / billing counter"),
        ],
    },
    {
        "module": "People",
        "permissions": [
            ("employees.view", "View staff & attendance"),
            ("employees.manage", "Add staff & assign permissions"),
        ],
    },
    {
        "module": "Reports",
        "permissions": [
            ("reports.view", "View store reports"),
        ],
    },
    {
        "module": "Marketing",
        "permissions": [
            ("marketing.send", "Send notifications to store customers"),
            ("marketing.banners", "Propose store banners for admin approval"),
        ],
    },
    {
        "module": "System",
        "permissions": [
            ("audit.view", "View the audit log"),
            ("settings.manage", "Edit store settings"),
        ],
    },
]

# Flat set of every valid permission key.
ALL_PERMISSIONS = [k for g in PERMISSION_GROUPS for (k, _label) in g["permissions"]]
PERMISSION_LABELS = {k: label for g in PERMISSION_GROUPS for (k, label) in g["permissions"]}

# Default permission bundle per built-in staff role. ``manager`` is special-cased
# in the model (holds all), so it isn't listed here.
ROLE_DEFAULT_PERMISSIONS = {
    "cashier": [
        "dashboard.view",
        "pos.operate",
        "orders.view",
        "customers.view",
    ],
    "inventory": [
        "dashboard.view",
        "inventory.view",
        "inventory.manage",
        "procurement.view",
        "procurement.manage",
    ],
    "delivery_coordinator": [
        "dashboard.view",
        "orders.view",
        "delivery.view",
        "delivery.manage",
        "collections.view",
        "collections.manage",
    ],
    "custom": [],
}


def default_permissions_for(staff_role: str) -> list:
    """The starter permission set for a freshly created staff member of this role."""
    return list(ROLE_DEFAULT_PERMISSIONS.get(staff_role, []))


def clean_permissions(keys) -> list:
    """Drop unknown keys; preserve catalog order so storage is deterministic."""
    given = set(keys or [])
    return [k for k in ALL_PERMISSIONS if k in given]
