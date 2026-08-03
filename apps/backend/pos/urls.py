from django.urls import path

from .admin_views import AdminPosTransactionsView
from .views import (
    CashDrawerView,
    CheckoutView,
    CustomerLookupView,
    DayClosingView,
    EventsView,
    HeldCartDetailView,
    HeldCartView,
    POSReportsView,
    ProductSearchView,
    ReceiptView,
    RefundView,
    ReturnView,
    ScanView,
    SessionCloseView,
    SessionOpenView,
    SessionView,
    TransactionDetailView,
    TransactionListView,
    TransactionVoidView,
)

urlpatterns = [
    # admin oversight (M12)
    path("admin/pos/transactions", AdminPosTransactionsView.as_view()),
    # session
    path("pos/session", SessionView.as_view()),
    path("pos/session/open", SessionOpenView.as_view()),
    path("pos/session/close", SessionCloseView.as_view()),
    path("pos/day-closing", DayClosingView.as_view()),
    # billing lookups
    path("pos/scan", ScanView.as_view()),
    path("pos/search", ProductSearchView.as_view()),
    path("pos/customer-lookup", CustomerLookupView.as_view()),
    # transactions
    path("pos/checkout", CheckoutView.as_view()),
    path("pos/transactions", TransactionListView.as_view()),
    path("pos/transactions/<int:pk>", TransactionDetailView.as_view()),
    path("pos/transactions/<int:pk>/receipt", ReceiptView.as_view()),
    path("pos/transactions/<int:pk>/void", TransactionVoidView.as_view()),
    path("pos/return", ReturnView.as_view()),
    path("pos/refund", RefundView.as_view()),
    # cash drawer + held carts
    path("pos/cash-drawer", CashDrawerView.as_view()),
    path("pos/cart", HeldCartView.as_view()),
    path("pos/cart/<int:pk>", HeldCartDetailView.as_view()),
    # events feed + reports
    path("pos/events", EventsView.as_view()),
    path("pos/reports/<str:name>", POSReportsView.as_view()),
]
