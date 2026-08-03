import {
  BadgeCheck,
  Banknote,
  BarChart3,
  Boxes,
  CreditCard,
  FileText,
  FolderTree,
  Gift,
  HandCoins,
  IdCard,
  KeyRound,
  LayoutDashboard,
  LifeBuoy,
  type LucideIcon,
  Map,
  Megaphone,
  Package,
  Receipt,
  ScanLine,
  ScrollText,
  Settings,
  Share2,
  ShieldCheck,
  ShoppingCart,
  Sparkles,
  Star,
  Store,
  Truck,
  UserCog,
  Users,
  Wallet,
  UserX,
} from "lucide-react";

export interface NavItem {
  label: string;
  href: string;
  icon: LucideIcon;
  /** Phase-2 module: visible but not yet wired. */
  soon?: boolean;
  /** Only super-admins see this. */
  superadminOnly?: boolean;
  /** Module number for reference. */
  module?: string;
}

export interface NavGroup {
  title: string;
  items: NavItem[];
}

export const NAV: NavGroup[] = [
  {
    title: "Overview",
    items: [{ label: "Dashboard", href: "/", icon: LayoutDashboard, module: "M01" }],
  },
  {
    title: "Commerce",
    items: [
      { label: "Orders", href: "/orders", icon: ShoppingCart, module: "M06" },
      { label: "Catalog", href: "/catalog", icon: Package, module: "M10" },
      { label: "Categories", href: "/catalog/categories", icon: FolderTree, module: "M10" },
      { label: "Inventory", href: "/inventory", icon: Boxes, module: "M11" },
      { label: "Procurement", href: "/procurement", icon: Receipt, module: "M13" },
      { label: "POS", href: "/pos", icon: ScanLine, module: "M12" },
    ],
  },
  {
    title: "Fulfilment",
    items: [
      { label: "Delivery", href: "/delivery", icon: Truck, module: "M07" },
      { label: "Collections", href: "/collections", icon: HandCoins, module: "M08" },
    ],
  },
  {
    title: "Customers & Credit",
    items: [
      { label: "Customers", href: "/customers", icon: Users, module: "M04" },
      { label: "Credit", href: "/credit", icon: CreditCard, module: "M05" },
      { label: "Verification", href: "/verification", icon: BadgeCheck, module: "M09" },
      { label: "Reviews", href: "/reviews", icon: Star, module: "M04" },
    ],
  },
  {
    title: "Network",
    items: [
      { label: "Stores", href: "/stores", icon: Store, module: "M02" },
      { label: "Zones", href: "/zones", icon: Map, module: "M03" },
    ],
  },
  {
    title: "Growth & Support",
    items: [
      { label: "Marketing", href: "/marketing", icon: Megaphone, module: "M18" },
      { label: "Loyalty", href: "/loyalty", icon: Sparkles, module: "M18" },
      { label: "Redemptions", href: "/redemptions", icon: Gift, module: "M18" },
      { label: "Referrals", href: "/referrals", icon: Share2, module: "M18" },
      { label: "Support", href: "/support", icon: LifeBuoy, module: "M19" },
      { label: "Legal / CMS", href: "/legal", icon: FileText, module: "M23" },
      { label: "Account Deletions", href: "/account-deletions", icon: UserX, module: "M24" },
    ],
  },
  {
    title: "Finance & People",
    items: [
      { label: "Payments", href: "/payments", icon: Wallet, module: "M14" },
      { label: "Cash Book", href: "/cash", icon: Banknote, module: "M14" },
      { label: "Reports", href: "/reports", icon: BarChart3, module: "M17" },
      { label: "Accounting", href: "/accounting", icon: ScrollText, module: "M14" },
      { label: "Agents", href: "/agents", icon: IdCard, module: "M16" },
      { label: "Employees", href: "/employees", icon: UserCog, module: "M15" },
    ],
  },
  {
    title: "System",
    items: [
      { label: "Audit Log", href: "/audit", icon: ScrollText, module: "M20" },
      { label: "Settings", href: "/settings", icon: Settings, module: "M21" },
      {
        label: "Integrations",
        href: "/settings/integrations",
        icon: KeyRound,
        superadminOnly: true,
        module: "M21",
      },
      { label: "Security", href: "/security", icon: ShieldCheck, superadminOnly: true, module: "M22" },
    ],
  },
];
