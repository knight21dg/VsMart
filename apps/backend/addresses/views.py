from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Address
from .serializers import AddressSerializer


class AddressViewSet(viewsets.ModelViewSet):
    serializer_class = AddressSerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Address.objects.none()
        return Address.objects.filter(user=self.request.user)

    def perform_create(self, serializer):
        first = not Address.objects.filter(user=self.request.user).exists()
        serializer.save(user=self.request.user, is_default=first or serializer.validated_data.get("is_default", False))

    @action(detail=True, methods=["post"])
    def default(self, request, pk=None):
        address = self.get_object()
        address.is_default = True
        address.save()
        return Response(AddressSerializer(address).data)
