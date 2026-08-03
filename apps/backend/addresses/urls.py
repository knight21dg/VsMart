from rest_framework.routers import SimpleRouter

from .views import AddressViewSet

router = SimpleRouter(trailing_slash=False)
router.register("addresses", AddressViewSet, basename="address")

urlpatterns = router.urls
