"""Store-Admin panel routes — all under /api/v1/store/*, store-scoped via membership."""
from django.urls import path

from . import (
    catalog_views,
    dispatch_views,
    extra_views,
    import_views,
    banner_views,
    marketing_views,
    pos_draft_views,
    pos_views,
    views,
)

urlpatterns = [
    # Identity & dashboard
    path("store/me", views.StoreMeView.as_view()),
    path("store/dashboard", views.StoreDashboardView.as_view()),

    # People (staff + permissions + attendance)
    path("store/permissions", views.StorePermissionCatalogView.as_view()),
    path("store/staff", views.StoreStaffListView.as_view()),
    path("store/staff/attendance", views.StoreAttendanceView.as_view()),
    path("store/staff/attendance/<str:action>", views.StoreAttendanceActionView.as_view()),
    path("store/staff/<int:staff_id>", views.StoreStaffDetailView.as_view()),

    # Orders
    path("store/orders", views.StoreOrderListView.as_view()),
    path("store/orders/queues", views.StoreOrderQueuesView.as_view()),
    # Before the <code> route, so "bulk-status" isn't swallowed as an order code.
    path("store/orders/bulk-status", views.StoreOrderBulkStatusView.as_view()),
    path("store/orders/<str:code>", views.StoreOrderDetailView.as_view()),
    path("store/orders/<str:code>/invoice", views.StoreOrderInvoiceView.as_view()),
    path("store/orders/<str:code>/status", views.StoreOrderStatusView.as_view()),

    # Inventory
    path("store/inventory", views.StoreInventoryView.as_view()),
    path("store/inventory/expiry", views.StoreExpiryView.as_view()),
    # Store catalog management (add / override items — belong to this store only)
    path("store/categories", catalog_views.StoreCategoriesView.as_view()),
    # Resolve a scanned pack BEFORE saving, so an existing code reads as
    # "this already exists" instead of creating a duplicate product.
    path("store/barcode", catalog_views.StoreBarcodeLookupView.as_view()),
    path("store/inventory/import", import_views.StoreCatalogImportView.as_view()),
    path("store/inventory/products", catalog_views.StoreCatalogCreateView.as_view()),
    path("store/inventory/products/image", catalog_views.StoreProductImageView.as_view()),
    path("store/inventory/products/<int:product_id>", catalog_views.StoreProductOverrideView.as_view()),
    path("store/inventory/<int:product_id>/adjust", views.StoreInventoryAdjustView.as_view()),

    # Procurement
    path("store/suppliers", views.StoreSupplierListView.as_view()),
    path("store/purchases", views.StorePurchaseListView.as_view()),
    path("store/products", views.StoreProductSearchView.as_view()),

    # Customers / credit / verification
    path("store/customers", views.StoreCustomerListView.as_view()),
    path("store/customers/<int:customer_id>", views.StoreCustomerDetailView.as_view()),
    path("store/credit", views.StoreCreditListView.as_view()),
    path("store/credit/<int:customer_id>", views.StoreCreditActionView.as_view()),
    path("store/credit/<int:customer_id>/cibil", views.StoreCibilView.as_view()),
    path("store/verification", views.StoreVerificationQueueView.as_view()),
    path("store/verification/agents", extra_views.StoreVerificationAgentsView.as_view()),
    path("store/verification/<int:app_id>", extra_views.StoreVerificationDetailView.as_view()),
    path("store/verification/<int:app_id>/assign", extra_views.StoreVerificationAssignView.as_view()),
    path("store/verification/<int:app_id>/documents/<int:doc_id>/file", extra_views.StoreVerificationDocumentFileView.as_view()),
    path("store/verification/<int:app_id>/evidence/<int:evidence_id>/file", extra_views.StoreVerificationEvidenceFileView.as_view()),
    path("store/verification/<int:app_id>/decision", extra_views.StoreVerificationDecisionView.as_view()),

    # Operations (delivery)
    path("store/delivery", views.StoreDeliveryListView.as_view()),
    path("store/delivery/agents", views.StoreDeliveryAgentsView.as_view()),
    path("store/delivery/<int:task_id>/status", views.StoreDeliveryStatusView.as_view()),
    path("store/delivery/<int:task_id>/reassign", views.StoreDeliveryReassignView.as_view()),
    path("store/delivery/returns", extra_views.StoreDeliveryReturnsView.as_view()),
    path("store/delivery/<int:task_id>/receive-return", extra_views.StoreDeliveryReturnReceiveView.as_view()),

    # Collections
    path("store/collections", extra_views.StoreCollectionsView.as_view()),
    path("store/credit/overdue", extra_views.StoreOverdueCreditView.as_view()),
    path("store/credit/overdue/assign", extra_views.StoreOverdueAssignView.as_view()),
    path("store/collections/<int:collection_id>/collect", extra_views.StoreCollectionCollectView.as_view()),
    path("store/collections/<int:collection_id>/reassign", extra_views.StoreCollectionReassignView.as_view()),
    path("store/collections/<int:collection_id>", extra_views.StoreCollectionDetailView.as_view()),

    # Returns
    path("store/returns", extra_views.StoreReturnsView.as_view()),
    path("store/returns/<str:code>", extra_views.StoreReturnDetailView.as_view()),
    path("store/returns/<str:code>/status", extra_views.StoreReturnStatusView.as_view()),

    # Reports
    path("store/reports/<str:name>", extra_views.StoreReportsView.as_view()),

    # POS (cashier billing)
    path("store/pos/session", pos_views.StorePOSSessionView.as_view()),
    path("store/pos/session/close", pos_views.StorePOSSessionCloseView.as_view()),
    path("store/pos/scan", pos_views.StorePOSScanView.as_view()),
    path("store/pos/search", pos_views.StorePOSSearchView.as_view()),
    path("store/pos/catalog", pos_views.StorePOSCatalogView.as_view()),
    path("store/pos/product/<int:product_id>", pos_views.StorePOSProductView.as_view()),
    path("store/pos/customer", pos_views.StorePOSCustomerView.as_view()),
    path("store/pos/customer/create", pos_views.StorePOSCustomerCreateView.as_view()),
    path("store/pos/coupon", pos_views.StorePOSCouponView.as_view()),
    # Counter card/UPI via a Razorpay payment link (no terminal at the till).
    path("store/pos/payment-link", pos_views.StorePOSPaymentLinkView.as_view()),
    path("store/pos/payment-link/<int:pk>",
         pos_views.StorePOSPaymentLinkStatusView.as_view()),
    path("store/pos/credit/request-otp", pos_views.StorePOSCreditOtpView.as_view()),
    path("store/pos/online/order", pos_views.StorePOSOnlineOrderView.as_view()),
    path("store/pos/drafts", pos_draft_views.StorePOSDraftListView.as_view()),
    path("store/pos/drafts/<int:draft_id>", pos_draft_views.StorePOSDraftDetailView.as_view()),
    path("store/pos/checkout", pos_views.StorePOSCheckoutView.as_view()),
    path("store/pos/transactions", pos_views.StorePOSTransactionsView.as_view()),
    path("store/pos/transactions/<str:code>/receipt", pos_views.StorePOSReceiptView.as_view()),
    path("store/pos/transactions/<str:code>/receipt-pdf", pos_views.StorePOSReceiptPdfView.as_view()),
    path("store/pos/transactions/<str:code>/invoice", pos_views.StorePOSInvoiceView.as_view()),
    path("store/pos/transactions/<str:code>/return", pos_views.StorePOSReturnView.as_view()),

    # Dispatch — assignment queue, engine, batches, agent capacity
    path("store/dispatch/queue", dispatch_views.StoreDispatchQueueView.as_view()),
    path("store/dispatch/auto-assign", dispatch_views.StoreDispatchAutoAssignView.as_view()),
    path("store/dispatch/manual", dispatch_views.StoreDispatchManualView.as_view()),
    path("store/dispatch/batches", dispatch_views.StoreBatchListView.as_view()),
    path("store/dispatch/batches/<int:batch_id>", dispatch_views.StoreBatchDetailView.as_view()),
    path("store/dispatch/batches/<int:batch_id>/cancel", dispatch_views.StoreBatchCancelView.as_view()),
    path("store/dispatch/batches/<int:batch_id>/reassign", dispatch_views.StoreBatchReassignView.as_view()),
    path("store/agents/live", dispatch_views.StoreAgentsLiveView.as_view()),
    path("store/agents/cash", dispatch_views.StoreAgentsCashView.as_view()),
    path("store/agents/cash/deposits/<int:deposit_id>/<str:action>",
         dispatch_views.StoreAgentsCashActionView.as_view()),
    path("store/agents", dispatch_views.StoreAgentsView.as_view()),
    path("store/agents/<int:agent_id>", dispatch_views.StoreAgentUpdateView.as_view()),

    # Marketing (notify this store's customers)
    path("store/marketing/notify", marketing_views.StoreNotifyView.as_view()),
    path("store/marketing/image", marketing_views.StoreNotifyImageView.as_view()),
    # Store-proposed banners (draft -> submit -> super-admin approves)
    path("store/marketing/banners", banner_views.StoreBannerListCreateView.as_view()),
    # NOTE: literal sub-routes must precede the generic /<pk> route.
    path("store/marketing/banners/<int:pk>/image", banner_views.StoreBannerImageView.as_view()),
    path("store/marketing/banners/<int:pk>/submit", banner_views.StoreBannerSubmitView.as_view()),
    path("store/marketing/banners/<int:pk>", banner_views.StoreBannerDetailView.as_view()),
    path("store/marketing/coupons", banner_views.StoreCouponListView.as_view()),

    path("store/brands", pos_views.StoreBrandsView.as_view()),

    # System
    path("store/audit", views.StoreAuditView.as_view()),
    path("store/settings", views.StoreSettingsView.as_view()),
]
