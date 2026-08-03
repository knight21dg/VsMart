from django.db import connection
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView


class HealthView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        return Response({"status": "ok", "service": "vsmart-api"})


class ReadinessView(APIView):
    permission_classes = [AllowAny]
    authentication_classes = []

    def get(self, request):
        checks = {"database": False, "cache": False}
        try:
            with connection.cursor() as cur:
                cur.execute("SELECT 1")
            checks["database"] = True
        except Exception:
            pass
        try:
            from django.core.cache import cache

            cache.set("_ready", "1", 5)
            checks["cache"] = cache.get("_ready") == "1"
        except Exception:
            pass
        ok = all(checks.values())
        return Response({"status": "ready" if ok else "degraded", "checks": checks})
