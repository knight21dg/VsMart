// Shape of GET /admin/crm/customers/<id> — the 15-section Customer 360 payload.
export interface C360Header {
  vsId: string;
  name: string;
  phone: string;
  customerSince: string;
  zone: string | null;
  store: string | null;
  assignedAdmin: string | null;
  collectionAgent: string | null;
  deliveryAgent: string | null;
  status: string;
  risk: string;
  avatarUrl: string | null;
}

export interface C360Health {
  lifetimeRevenue: number;
  orders: number;
  creditUsed: number;
  collections: number;
  outstanding: number;
  vsScore: number | null;
  /** null when the customer has no credit account — nothing to measure. */
  collectionEfficiency: number | null;
  retentionMonths: number;
}

export interface C360Credit {
  hasAccount: boolean;
  status?: string;
  creditLimit?: number;
  availableCredit?: number;
  usedCredit?: number;
  outstanding?: number;
  overdue?: number;
  nextDueDate?: string | null;
  averageMonthlyUsage?: number;
  maximumUtilization?: number;
  repaymentRate?: number;
  latePayments?: number;
  missedPayments?: number;
  riskCategory?: string;
  usageTrend?: { period: string; purchases: number; payments: number; balance: number }[];
}

export interface C360Orders {
  totalOrders: number;
  delivered: number;
  cancelled: number;
  returned: number;
  averageOrderValue: number;
  highestOrder: number;
  monthlySpend: number;
  favoriteCategories: string[];
  favoriteBrands: string[];
  preferredPurchaseHour: number | null;
  charts: {
    byMonth: { month: string; orders: number; revenue: number }[];
    categorySpend: { category: string; spend: number }[];
  };
}

export interface C360Collections {
  totalCollections: number;
  totalCount: number;
  pending: number;
  failed: number;
  averageRecoveryDays: number;
  lastCollectionAt: string | null;
  collectionAgent: string | null;
}

export interface C360Verification {
  aadhaar: string;
  pan: string;
  selfie: string;
  house: string;
  gps: string;
  agentVerified: boolean;
  verifiedAt: string | null;
  verifiedBy: string | null;
  evidence: { kind: string; photoKey: string; lat: number | null; lng: number | null }[];
}

export interface C360Geo {
  customer: { lat: number | null; lng: number | null; address: string | null };
  store: { name: string | null; lat: number | null; lng: number | null } | null;
  zone: { name: string | null; polygon: unknown } | null;
}

export interface C360Note {
  id: string;
  body: string;
  author: string | null;
  at: string;
}

export interface C360Support {
  tickets: number;
  open: number;
  complaints: number;
  escalations: number;
  returns: number;
  refunds: number;
}

export interface C360Network {
  familyMembers: { phone: string; relationship: string; status: string }[];
  sameHousehold: { id: string; name: string; phone: string }[];
  referrals: { id: string; code: string; status: string }[];
  referredBy: string | null;
}

export interface C360Risk {
  score: number;
  level: string;
  factors: Record<string, unknown>;
}

export interface C360Exposure {
  hasExposure: boolean;
  totalExposure?: number;
  currentOutstanding?: number;
  overdueAmount?: number;
  expectedRecovery?: number;
  recoveryProbability?: number;
  daysPastDue?: number;
  riskBucket?: string;
  projectedLoss?: number;
}

export interface C360TimelineEvent {
  type: string;
  label: string;
  at: string;
  amount?: number;
}

export interface Customer360 {
  header: C360Header;
  health: C360Health;
  creditIntelligence: C360Credit;
  orderAnalytics: C360Orders;
  collectionAnalytics: C360Collections;
  timeline: C360TimelineEvent[];
  verification: C360Verification;
  geographic: C360Geo;
  notes: Record<string, C360Note[]>;
  support: C360Support;
  network: C360Network;
  risk: C360Risk;
  financialExposure: C360Exposure;
  aiInsights: Record<string, boolean | string>;
}

export const RISK_ACCENT: Record<string, "green" | "gold" | "red" | "slate"> = {
  low: "green",
  medium: "gold",
  high: "red",
  critical: "red",
};
