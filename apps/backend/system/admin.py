from django.contrib import admin

from .models import Feedback, FeatureFlag


@admin.register(FeatureFlag)
class FeatureFlagAdmin(admin.ModelAdmin):
    list_display = ["key", "enabled", "description", "updated_at"]
    list_filter = ["enabled"]
    search_fields = ["key", "description"]


@admin.register(Feedback)
class FeedbackAdmin(admin.ModelAdmin):
    list_display = ["__str__", "user", "rating", "created_at"]
    list_filter = ["rating"]
    search_fields = ["message"]
