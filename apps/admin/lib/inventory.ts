// Types for the enterprise inventory command center (camelCase per the API envelope).

export interface InvOverview {
  totalInventoryValue: number;
  totalSkus: number;
  totalUnits: number;
  lowStock: number;
  outOfStock: number;
  damagedUnits: number;
  damagedValue: number;
  deadStockCount: number;
  deadStockValue: number;
  nearExpiryValue: number;
  pendingPurchaseOrders: number;
  pendingTransfers: number;
  consumptionToday: number;
  replenishmentToday: number;
}

export interface StoreRollup {
  storeId: string;
  storeName: string;
  warehouseId: string;
  status: string;
  inventoryValue: number;
  skuCount: number;
  lowStock: number;
  outOfStock: number;
  fillRate: number;
  healthScore: number;
  salesToday: number;
  pendingTransfers: number;
}

export interface Mover {
  productId: string;
  name: string;
  /** Product was archived (soft-deleted) but still holds stock / ledger history. */
  archived?: boolean;
  unitsSold: number;
  revenue: number;
  onHand: number;
  value: number;
  lastSale: string | null;
}

export interface DeadStockItem {
  productId: string;
  name: string;
  archived?: boolean;
  quantity: number;
  value: number;
  lastSale: string | null;
  daysSinceSale: number | null;
}

export interface AgingBucket {
  bucket: string;
  quantity: number;
  value: number;
}
export interface NearExpiry {
  productId: string;
  name: string;
  warehouseId: string;
  batchNo: string;
  expiryDate: string;
  quantity: number;
  value: number;
  daysToExpiry: number;
}

export interface Finance {
  periodDays: number;
  inventoryValue: number;
  cogsPeriod: number;
  cogsAnnualized: number;
  grossMarginPeriod: number;
  turnoverRatio: number;
  gmroi: number;
  holdingCost: number;
  shrinkageUnits: number;
  shrinkageValue: number;
  shrinkagePct: number;
  deadStockValue: number;
  expectedRevenue: number;
  marginPotential: number;
  assumptions: { carryingRate: number; leadTimeDays: number };
}

export interface ReorderItem {
  productId: string;
  name: string;
  warehouseId: string;
  warehouse: string;
  available: number;
  avgDailySales: number;
  daysRemaining: number | null;
  safetyStock: number;
  suggestedQty: number;
}

export interface TransferSuggestion {
  productId: string;
  name: string;
  fromWarehouseId: string;
  fromWarehouse: string;
  toWarehouseId: string;
  toWarehouse: string;
  quantity: number;
  reason: string;
}

export interface HeatmapData {
  stores: { warehouseId: string; storeName: string }[];
  products: { productId: string; name: string; cells: Record<string, number> }[];
}

export interface AuditRow {
  id: string;
  product: string;
  delta: number;
  newCount: number;
  reason: string;
  by: string;
  createdAt: string;
}

export interface ProductOverview {
  summary: {
    id: string;
    name: string;
    brand: string;
    category: string;
    unit: string;
    sellingPrice: number;
    mrp: number;
    creditPrice: number | null;
    avgCost: number;
    margin: number;
    marginPct: number;
  };
  totals: { onHand: number; reserved: number; available: number; damaged: number; networkValue: number };
  distribution: { warehouseId: string; warehouse: string; onHand: number; reserved: number; available: number; damaged: number }[];
  velocity: { units7d: number; units30d: number; units90d: number; avgDaily: number; lastSale: string | null };
  reorder: { avgDaily: number; daysRemaining: number | null; suggestedQty: number; leadTimeDays: number };
  suppliers: { supplier: string; totalQty: number; avgCost: number; orders: number; lastOrder: string | null }[];
  ledger: { id: string; warehouseId: string; type: string; quantity: number; balanceAfter: number; note: string; createdAt: string }[];
}
