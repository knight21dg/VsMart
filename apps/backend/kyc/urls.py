from django.urls import path

from .views import (
    AadhaarOtpInitView,
    AadhaarOtpSubmitView,
    AdminKycDecisionView,
    AdminKycQueueView,
    AgentKycQueueView,
    AgentReviewView,
    CreditOnboardCheckView,
    CreditOnboardOtpView,
    CreditOnboardSubmitView,
    DigiLockerStartView,
    DigiLockerStatusView,
    DocumentFileView,
    DocumentUrlView,
    KycRetryView,
    KycStatusView,
    KycSubmitView,
    VerifyBankView,
    VerifyPanView,
)

urlpatterns = [
    path("kyc/status", KycStatusView.as_view()),
    path("kyc/submit", KycSubmitView.as_view()),
    path("kyc/retry", KycRetryView.as_view()),
    # Credit-bureau onboarding (Aadhaar name + DOB + PAN + phone OTP → CIBIL)
    path("kyc/credit/check", CreditOnboardCheckView.as_view()),
    path("kyc/credit/send-otp", CreditOnboardOtpView.as_view()),
    path("kyc/credit/submit", CreditOnboardSubmitView.as_view()),
    path("kyc/documents/<int:pk>/url", DocumentUrlView.as_view()),
    path("kyc/documents/<int:pk>/file", DocumentFileView.as_view()),
    # API verification (gov-source) — customer-driven, server-side only
    path("kyc/pan/verify", VerifyPanView.as_view()),
    path("kyc/aadhaar/send-otp", AadhaarOtpInitView.as_view()),
    path("kyc/aadhaar/verify-otp", AadhaarOtpSubmitView.as_view()),
    path("kyc/aadhaar/digilocker/start", DigiLockerStartView.as_view()),
    path("kyc/aadhaar/digilocker/<str:reference_id>/status",
         DigiLockerStatusView.as_view()),
    path("kyc/bank/verify", VerifyBankView.as_view()),
    # Agent / admin review (manual fallback + final decision)
    path("agent/kyc/queue", AgentKycQueueView.as_view()),
    path("agent/kyc/<int:pk>/review", AgentReviewView.as_view()),
    path("admin/kyc/queue", AdminKycQueueView.as_view()),
    path("admin/kyc/<int:pk>/decision", AdminKycDecisionView.as_view()),
]
