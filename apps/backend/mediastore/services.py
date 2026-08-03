"""Asset lifecycle helpers shared by views and management commands."""
from django.core.files.storage import default_storage

from .pipeline import _variant_sizes


def delete_asset(asset) -> None:
    """Delete an asset's stored variant files, then the DB row. Best-effort on the
    files (a missing variant never blocks the row delete)."""
    for variant in _variant_sizes():
        try:
            default_storage.delete(asset.variant_key(variant))
        except Exception:
            pass
    asset.delete()
