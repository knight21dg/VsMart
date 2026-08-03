import {
  BadgeCheck,
  BarChart3,
  Bike,
  Boxes,
  ClipboardList,
  CreditCard,
  HandCoins,
  ImageIcon,
  LayoutDashboard,
  type LucideIcon,
  Megaphone,
  Receipt,
  RotateCcw,
  Route,
  ScanLine,
  ScrollText,
  Settings,
  ShoppingCart,
  Truck,
  UserCog,
  Users,
  Wallet,
} from "lucide-react";

export interface NavItem {
  label: string;
  href: string;
  icon: LucideIcon;
  /** Visible only if the staff member holds ANY of these permission keys. */
  perms?: string[];
  /** Module exists in nav but isn't wired yet. */
  soon?: boolean;
}

export interface NavGroup {
  title: string;
  items: NavItem[];
}

/** Icon for the packing board / active-orders queue. */
export const QUEUE_ICON = ClipboardList;

export const NAV: NavGroup[] = [
  {
    title: "Overview",
    items: [{ label: "Dashboard", href: "/", icon: LayoutDashboard, perms: ["dashboard.view"] }],
  },
  {
    title: "Point of Sale",
    items: [
      { label: "POS / Billing", href: "/pos", icon: ScanLine, perms: ["pos.operate"] },
      { label: "POS Sales", href: "/pos/sales", icon: Receipt, perms: ["pos.operate"] },
      { label: "POS Drafts", href: "/pos/drafts", icon: ClipboardList, perms: ["pos.operate"] },
    ],
  },
  {
    title: "Orders",
    items: [
      { label: "Orders", href: "/orders", icon: ShoppingCart, perms: ["orders.view"] },
      { label: "Packing Board", href: "/orders/board", icon: QUEUE_ICON, perms: ["orders.view"] },
      { label: "Returns", href: "/returns", icon: RotateCcw, perms: ["returns.manage"] },
    ],
  },
  {
    title: "Inventory",
    items: [
      { label: "Inventory", href: "/inventory", icon: Boxes, perms: ["inventory.view"] },
      { label: "Procurement", href: "/procurement", icon: Receipt, perms: ["procurement.view"] },
    ],
  },
  {
    title: "Customers",
    items: [
      { label: "Customers", href: "/customers", icon: Users, perms: ["customers.view"] },
      { label: "Credit", href: "/credit", icon: CreditCard, perms: ["credit.view"] },
      { label: "Verification", href: "/verification", icon: BadgeCheck, perms: ["verification.view"] },
    ],
  },
  {
    title: "Operations",
    items: [
      { label: "Dispatch", href: "/dispatch", icon: Route, perms: ["delivery.view"] },
      { label: "Agents", href: "/agents", icon: Bike, perms: ["delivery.view"] },
      { label: "Agent Cash", href: "/agents/cash", icon: Wallet, perms: ["delivery.view"] },
      { label: "Delivery", href: "/delivery", icon: Truck, perms: ["delivery.view"] },
      { label: "Collections", href: "/collections", icon: HandCoins, perms: ["collections.view"] },
    ],
  },
  {
    title: "People",
    items: [{ label: "Employees", href: "/employees", icon: UserCog, perms: ["employees.view"] }],
  },
  {
    title: "Marketing",
    items: [
      { label: "Notify Customers", href: "/marketing", icon: Megaphone, perms: ["marketing.send"] },
      { label: "Store Banners", href: "/marketing/banners", icon: ImageIcon, perms: ["marketing.banners"] },
    ],
  },
  {
    title: "Reports",
    items: [{ label: "Reports", href: "/reports", icon: BarChart3, perms: ["reports.view"] }],
  },
  {
    title: "System",
    items: [
      { label: "Audit Log", href: "/audit", icon: ScrollText, perms: ["audit.view"] },
      { label: "Settings", href: "/settings", icon: Settings, perms: ["dashboard.view"] },
    ],
  },
];

