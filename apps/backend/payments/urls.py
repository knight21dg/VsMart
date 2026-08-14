from django.urls import path

from .cashbook_views import (
    AdminCashDepositActionView,
    AdminCashDepositDetailView,
    AdminCashDepositListView,
    AdminCashInHandView,
    AdminCashReconciliationView,
    AdminPaymentReceiptView,
    AgentCashView,
    AgentOnlineHandoverCancelView,
    AgentOnlineHandoverConfirmView,
    AgentOnlineHandoverView,
    PaymentReceiptView,
)

from .admin_views import (
    AdminPaymentDetailView,
    AdminPaymentListView,
    AdminPaymentSummaryView,
    AdminConfirmCapturedView,
    AdminConfirmNotCapturedView,
    AdminReconciliationListView,
)
from .views import (
    CashCollectionRequestView,
    PaymentDetailView,
    PaymentHistoryView,
    ConfirmPaymentView,
    RepayView,
    StartPaymentView,
    WebhookView,
)

urlpatterns = [
    path("payments", StartPaymentView.as_view()),
    path("payments/history", PaymentHistoryView.as_view()),
    path("payments/<int:pk>/confirm", ConfirmPaymentView.as_view()),
    path("payments/<int:pk>/receipt", PaymentReceiptView.as_view()),
    path("payments/<int:pk>", PaymentDetailView.as_view()),
    path("webhooks/razorpay", WebhookView.as_view()),
    # ── Admin payments ledger (M: finance / reconciliation) ──
    # NOTE: keep /summary before /<pk> so it isn't captured as an id.
    # ── Cash book (collected cash -> deposit -> verified) ──
    path("agent/cash", AgentCashView.as_view()),
    path("agent/cash/online", AgentOnlineHandoverView.as_view()),
    path("agent/cash/online/<int:pk>/confirm",
         AgentOnlineHandoverConfirmView.as_view()),
    path("agent/cash/online/<int:pk>/cancel",
         AgentOnlineHandoverCancelView.as_view()),
    # NOTE: literal routes before /<pk> so they aren't captured as ids.
    path("admin/cash/reconciliation", AdminCashReconciliationView.as_view()),
    path("admin/cash/in-hand", AdminCashInHandView.as_view()),
    path("admin/cash/deposits", AdminCashDepositListView.as_view()),
    path("admin/cash/deposits/<int:pk>/<str:action>", AdminCashDepositActionView.as_view()),
    path("admin/cash/deposits/<int:pk>", AdminCashDepositDetailView.as_view()),
    path("admin/payments/summary", AdminPaymentSummaryView.as_view()),
    path("admin/payments/reconciliation", AdminReconciliationListView.as_view()),
    path("admin/payments/<int:pk>/confirm-captured", AdminConfirmCapturedView.as_view()),
    path("admin/payments/<int:pk>/confirm-not-captured", AdminConfirmNotCapturedView.as_view()),
    path("admin/payments", AdminPaymentListView.as_view()),
    path("admin/payments/<int:pk>/receipt", AdminPaymentReceiptView.as_view()),
    path("admin/payments/<int:pk>", AdminPaymentDetailView.as_view()),
    path("credit/repay", RepayView.as_view()),
    path("credit/cash-collection", CashCollectionRequestView.as_view()),
    # NOTE: "agent/collections" + "agent/collections/<pk>/collect" used to live
    # here — a pre-OTP legacy path superseded by cashcollections' properly
    # state-machined, OTP-gated "collections/<pk>/collect" (the one the app
    # actually calls). The legacy pair called payments.services.collect_cash()
    # directly with NO otp_verified check at all: any authenticated agent could
    # mark ANY collection COLLECTED — no visit, no OTP, no state-machine
    # transitions — which silently credited their cash-in-hand for money that
    # was never actually recovered. Removed rather than left as a live bypass.
]
