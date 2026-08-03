from django.urls import path

from .views import (
    InvoiceDetailView,
    InvoiceListView,
    InvoicePdfView,
    ReceiptDetailView,
    ReceiptListView,
)

urlpatterns = [
    path("billing/invoices", InvoiceListView.as_view()),
    path("billing/invoices/<int:pk>", InvoiceDetailView.as_view()),
    path("billing/invoices/<int:pk>/pdf", InvoicePdfView.as_view()),
    path("billing/receipts", ReceiptListView.as_view()),
    path("billing/receipts/<int:pk>", ReceiptDetailView.as_view()),
]
