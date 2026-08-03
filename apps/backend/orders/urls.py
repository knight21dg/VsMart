from django.urls import path

from .admin_views import (
    AdminOrderAssignAgentView,
    AdminOrderDashboardView,
    AdminOrderDetailView,
    AdminOrderInvoiceView,
    AdminOrderListView,
    AdminOrderQueuesView,
    AdminOrderStatusView,
)
from .feedback_views import OrderFeedbackView
from .views import (
    AgentDeliveriesView,
    AgentDeliveryStatusView,
    CheckoutView,
    OrderCancelView,
    OrderDetailView,
    OrderInvoiceView,
    OrderListView,
    OrderReorderPreviewView,
    OrderReorderView,
    OrderTrackingView,
)

urlpatterns = [
    path("checkout", CheckoutView.as_view()),
    path("orders", OrderListView.as_view()),
    # admin orders module (before the customer <code> route)
    path("admin/orders/dashboard", AdminOrderDashboardView.as_view()),
    path("admin/orders/queues", AdminOrderQueuesView.as_view()),
    path("admin/orders", AdminOrderListView.as_view()),
    path("admin/orders/<str:code>", AdminOrderDetailView.as_view()),
    path("admin/orders/<str:code>/invoice", AdminOrderInvoiceView.as_view()),
    path("admin/orders/<str:code>/status", AdminOrderStatusView.as_view()),
    path("admin/orders/<str:code>/assign-agent", AdminOrderAssignAgentView.as_view()),
    # customer
    path("orders/<str:code>", OrderDetailView.as_view()),
    path("orders/<str:code>/invoice", OrderInvoiceView.as_view()),
    path("orders/<str:code>/tracking", OrderTrackingView.as_view()),
    path("orders/<str:code>/cancel", OrderCancelView.as_view()),
    path("orders/<str:code>/reorder", OrderReorderView.as_view()),
    path("orders/<str:code>/reorder/preview", OrderReorderPreviewView.as_view()),
    path("orders/<str:code>/feedback", OrderFeedbackView.as_view()),
    # agent
    path("agent/deliveries", AgentDeliveriesView.as_view()),
    path("agent/deliveries/<str:code>/status", AgentDeliveryStatusView.as_view()),
]
