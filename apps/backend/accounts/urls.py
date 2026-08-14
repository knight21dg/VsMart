from django.urls import path

from .admin_views import (
    AdminDeletionRequestDetailView,
    AdminDeletionRequestsView,
    AdminEmployeesView,
)
from .views import (
    AccountDeletionRequestView,
    AvatarUploadView,
    ChangePasswordView,
    DeviceTokenView,
    ForgotPasswordView,
    LoginView,
    LogoutView,
    MeView,
    RefreshTokenView,
    RegisterView,
    ResetPasswordView,
    SendOtpView,
    VerifyOtpView,
)

urlpatterns = [
    path("admin/employees", AdminEmployeesView.as_view()),
    path("admin/deletion-requests", AdminDeletionRequestsView.as_view()),
    path("admin/deletion-requests/<int:pk>", AdminDeletionRequestDetailView.as_view()),
    path("auth/otp/send", SendOtpView.as_view()),
    path("auth/otp/verify", VerifyOtpView.as_view()),
    path("auth/login", LoginView.as_view()),
    path("auth/password/forgot", ForgotPasswordView.as_view()),
    path("auth/password/reset", ResetPasswordView.as_view()),
    path("auth/password/change", ChangePasswordView.as_view()),
    path("auth/register", RegisterView.as_view()),
    path("auth/refresh", RefreshTokenView.as_view()),
    path("auth/logout", LogoutView.as_view()),
    path("users/me", MeView.as_view()),
    path("users/me/avatar", AvatarUploadView.as_view()),
    path("account/deletion-request", AccountDeletionRequestView.as_view()),
    path("notifications/device-token", DeviceTokenView.as_view()),
]
