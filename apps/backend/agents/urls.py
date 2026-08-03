from django.urls import path

from .auth_views import AgentSendOtpView, AgentVerifyOtpView
from .history_views import AgentHistoryView
from .views import (
    AdminAgentLeaderboardView,
    AdminAgentRosterView,
    AdminAttendanceView,
    AgentAttendanceHistoryView,
    AgentAttendanceMeView,
    AgentCheckInView,
    AgentCheckOutView,
    AgentEarningsView,
    AgentIncentivesView,
    AgentMeView,
    AgentPerformanceView,
    LiveOperationsView,
)

urlpatterns = [
    # Gated agent login (phone must be a registered agent → OTP)
    path("agents/auth/send-otp", AgentSendOtpView.as_view()),
    path("agents/auth/verify-otp", AgentVerifyOtpView.as_view()),
    path("agents/me", AgentMeView.as_view()),
    path("agents/performance", AgentPerformanceView.as_view()),
    # Closed work — the complement of the three active agent queues.
    path("agents/history", AgentHistoryView.as_view()),
    path("agents/earnings", AgentEarningsView.as_view()),
    path("agents/incentives", AgentIncentivesView.as_view()),
    # attendance (agent app)
    path("agents/attendance/me", AgentAttendanceMeView.as_view()),
    path("agents/attendance/history", AgentAttendanceHistoryView.as_view()),
    path("agents/attendance/check-in", AgentCheckInView.as_view()),
    path("agents/attendance/check-out", AgentCheckOutView.as_view()),
    # live operations + attendance roster (admin)
    path("admin/agents", AdminAgentRosterView.as_view()),
    path("admin/agents/leaderboard", AdminAgentLeaderboardView.as_view()),
    path("admin/ops/live", LiveOperationsView.as_view()),
    path("admin/ops/attendance", AdminAttendanceView.as_view()),
]
