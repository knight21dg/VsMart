from django.contrib import admin

from .models import Coupon, CouponRedemption, Offer


@admin.register(Offer)
class OfferAdmin(admin.ModelAdmin):
    list_display = ["title", "type", "code", "is_active", "sort_order", "valid_to"]
    list_filter = ["type", "is_active"]
    search_fields = ["title", "code"]


@admin.register(Coupon)
class CouponAdmin(admin.ModelAdmin):
    list_display = ["code", "discount_type", "value", "min_order", "is_active", "valid_to"]
    list_filter = ["discount_type", "is_active"]
    search_fields = ["code"]


@admin.register(CouponRedemption)
class CouponRedemptionAdmin(admin.ModelAdmin):
    list_display = ["coupon", "user", "order_code", "amount", "created_at"]
    search_fields = ["coupon__code", "order_code"]
