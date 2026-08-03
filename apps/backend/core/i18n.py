"""Content localization.

The app's ARB/`AppLocalizations` files translate **UI chrome**. Catalog *content*
— product names, descriptions, category names — lives in the database, so no
amount of client-side localization can translate it. Those models carry per
-language columns (``name_te`` / ``name_hi`` …) and the API resolves them
server-side into the ordinary ``name`` / ``description`` keys.

Resolving on the server rather than shipping every translation to the client
means every consumer gets it for free — search results, cart lines, order
history, invoices, push notifications — with no change to the Flutter models.

Language is taken from an explicit ``?lang=`` query param, else the standard
``Accept-Language`` header, and falls back to English.
"""

#: Languages the catalog is translated into. English is the base column.
SUPPORTED_LANGS = ("en", "te", "hi")
DEFAULT_LANG = "en"


def resolve_lang(request) -> str:
    """Best supported language for ``request``: ?lang → Accept-Language → en."""
    if request is None:
        return DEFAULT_LANG

    explicit = ""
    params = getattr(request, "query_params", None) or getattr(request, "GET", None)
    if params is not None:
        explicit = (params.get("lang") or "").strip().lower()
    if explicit[:2] in SUPPORTED_LANGS:
        return explicit[:2]

    header = (request.META.get("HTTP_ACCEPT_LANGUAGE") or "").lower()
    # "te-IN,te;q=0.9,en;q=0.8" -> first supported tag, honouring the order the
    # client asked for (q-values are already in preference order in practice).
    for part in header.split(","):
        tag = part.split(";")[0].strip()[:2]
        if tag in SUPPORTED_LANGS:
            return tag
    return DEFAULT_LANG


def pick(obj, field: str, lang: str) -> str:
    """Localized ``field`` on ``obj``, falling back to the base column.

    A blank translation falls back rather than rendering an empty name — a
    half-translated catalog must never show a product with no title.
    """
    base = getattr(obj, field, "") or ""
    if lang == DEFAULT_LANG:
        return base
    return (getattr(obj, f"{field}_{lang}", "") or "").strip() or base


class LocalizedFieldsMixin:
    """Serializer mixin: resolve declared fields for the request's language.

    Set ``localized_fields`` to the base field names. Each becomes a method
    field returning the right language, so the wire shape is unchanged.
    """

    localized_fields: tuple = ()

    @property
    def _lang(self) -> str:
        return resolve_lang(self.context.get("request"))

    def localized(self, obj, field: str) -> str:
        return pick(obj, field, self._lang)
