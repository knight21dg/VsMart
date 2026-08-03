from django.contrib import admin

from .models import Category, Product, ProductImage, ProductVariant


class ProductImageInline(admin.TabularInline):
    model = ProductImage
    extra = 1


class ProductVariantInline(admin.TabularInline):
    model = ProductVariant
    extra = 0


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    list_display = ["name", "parent", "product_count", "sort_order", "is_active"]
    list_filter = ["is_active", "parent"]
    search_fields = ["name", "slug"]
    prepopulated_fields = {"slug": ("name",)}


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ["name", "brand", "category", "price", "mrp", "in_stock", "is_active"]
    list_filter = ["is_active", "in_stock", "category", "brand"]
    search_fields = ["name", "brand"]
    list_editable = ["price", "in_stock", "is_active"]
    inlines = [ProductImageInline, ProductVariantInline]
