"""Seed a demo grocery catalog so the API returns real, image-rich data.

    python manage.py seed_demo

Idempotent — safe to run repeatedly (get_or_create by name+category). Images use
the public DummyJSON groceries CDN (stable, loads on-device).
"""
from django.core.management.base import BaseCommand
from django.utils.text import slugify

from catalog.models import Category, Product
from offers.models import Coupon, Offer
from support.models import Faq

CDN = "https://cdn.dummyjson.com/product-images/groceries"


def img(slug):
    return f"{CDN}/{slug}/thumbnail.webp"


# name, icon, representative image slug  (top-level departments)
CATEGORIES = [
    ("Fruits & Vegetables", "eco", "apple"),
    ("Dairy & Eggs", "egg", "milk"),
    ("Meat & Seafood", "set_meal", "chicken-meat"),
    ("Beverages", "local_cafe", "juice"),
    ("Staples & Cooking", "rice_bowl", "cooking-oil"),
    ("Household", "cleaning_services", "tissue-paper"),
]

# department -> [(subcategory name, icon, representative image slug)]
SUBCATEGORIES = {
    "Fruits & Vegetables": [
        ("Fresh Fruits", "eco", "apple"),
        ("Fresh Vegetables", "eco", "potatoes"),
        ("Herbs & Seasonings", "eco", "lemon"),
    ],
    "Dairy & Eggs": [
        ("Milk & Cream", "egg", "milk"),
        ("Eggs", "egg", "eggs"),
        ("Frozen Desserts", "egg", "ice-cream"),
    ],
    "Meat & Seafood": [
        ("Chicken", "set_meal", "chicken-meat"),
        ("Red Meat", "set_meal", "beef-steak"),
        ("Seafood", "set_meal", "fish-steak"),
    ],
    "Beverages": [
        ("Juices", "local_cafe", "juice"),
        ("Soft Drinks", "local_cafe", "soft-drinks"),
        ("Water", "local_cafe", "water"),
        ("Tea & Coffee", "local_cafe", "nescafe-coffee"),
    ],
    "Staples & Cooking": [
        ("Oils & Ghee", "rice_bowl", "cooking-oil"),
        ("Rice & Grains", "rice_bowl", "rice"),
        ("Honey & Spreads", "rice_bowl", "honey-jar"),
        ("Health Foods", "rice_bowl", "protein-powder"),
    ],
    "Household": [
        ("Paper & Cleaning", "cleaning_services", "tissue-paper"),
        ("Pet Care", "cleaning_services", "dog-food"),
    ],
}

# product image slug -> subcategory name (assigns each product to a leaf category)
PRODUCT_SUBCAT = {
    "apple": "Fresh Fruits", "kiwi": "Fresh Fruits", "strawberry": "Fresh Fruits",
    "lemon": "Herbs & Seasonings",
    "cucumber": "Fresh Vegetables", "potatoes": "Fresh Vegetables",
    "red-onions": "Fresh Vegetables", "green-bell-pepper": "Fresh Vegetables",
    "eggs": "Eggs", "milk": "Milk & Cream", "ice-cream": "Frozen Desserts",
    "chicken-meat": "Chicken", "beef-steak": "Red Meat", "fish-steak": "Seafood",
    "juice": "Juices", "soft-drinks": "Soft Drinks", "water": "Water",
    "nescafe-coffee": "Tea & Coffee",
    "cooking-oil": "Oils & Ghee", "rice": "Rice & Grains",
    "honey-jar": "Honey & Spreads", "protein-powder": "Health Foods",
    "tissue-paper": "Paper & Cleaning", "dog-food": "Pet Care",
}

# name, brand, unit, price, mrp, category, rating, reviews, slug
PRODUCTS = [
    # Fruits & Vegetables
    ("Apple", "Fresh Farms", "1 kg", 165, 189, "Fruits & Vegetables", 4.3, 240, "apple"),
    ("Kiwi", "Fresh Farms", "500 g", 210, 240, "Fruits & Vegetables", 4.4, 132, "kiwi"),
    ("Lemon", "Fresh Farms", "250 g", 45, 60, "Fruits & Vegetables", 4.2, 88, "lemon"),
    ("Strawberry", "Fresh Farms", "200 g", 180, 220, "Fruits & Vegetables", 4.6, 310, "strawberry"),
    ("Cucumber", "Fresh Farms", "500 g", 40, 55, "Fruits & Vegetables", 4.1, 95, "cucumber"),
    ("Potatoes", "Fresh Farms", "2 kg", 70, 90, "Fruits & Vegetables", 4.2, 150, "potatoes"),
    ("Red Onions", "Fresh Farms", "1 kg", 55, 75, "Fruits & Vegetables", 4.0, 120, "red-onions"),
    ("Green Bell Pepper", "Fresh Farms", "500 g", 60, 80, "Fruits & Vegetables", 4.3, 76, "green-bell-pepper"),
    # Dairy & Eggs
    ("Farm Eggs", "Country Hen", "12 pcs", 90, 110, "Dairy & Eggs", 4.7, 520, "eggs"),
    ("Milk", "Pure Dairy", "1 L", 62, 70, "Dairy & Eggs", 4.6, 410, "milk"),
    ("Ice Cream", "FrostByte", "500 ml", 220, 260, "Dairy & Eggs", 4.5, 280, "ice-cream"),
    # Meat & Seafood
    ("Chicken Meat", "ProteinCo", "500 g", 180, 220, "Meat & Seafood", 4.6, 410, "chicken-meat"),
    ("Beef Steak", "ProteinCo", "500 g", 520, 600, "Meat & Seafood", 4.5, 190, "beef-steak"),
    ("Fish Steak", "OceanFresh", "400 g", 340, 400, "Meat & Seafood", 4.4, 130, "fish-steak"),
    # Beverages
    ("Orange Juice", "Tropico", "1 L", 120, 150, "Beverages", 4.5, 312, "juice"),
    ("Soft Drinks", "FizzUp", "750 ml", 45, 60, "Beverages", 4.1, 220, "soft-drinks"),
    ("Drinking Water", "AquaPure", "1 L", 20, 25, "Beverages", 4.3, 540, "water"),
    ("Nescafe Coffee", "Nescafe", "100 g", 290, 330, "Beverages", 4.7, 480, "nescafe-coffee"),
    # Staples & Cooking
    ("Cooking Oil", "GoldenDrop", "1 L", 165, 190, "Staples & Cooking", 4.2, 180, "cooking-oil"),
    ("Basmati Rice", "RoyalGrain", "5 kg", 480, 560, "Staples & Cooking", 4.6, 360, "rice"),
    ("Honey Jar", "BeeWild", "500 g", 320, 380, "Staples & Cooking", 4.6, 210, "honey-jar"),
    ("Protein Powder", "FitFuel", "1 kg", 1899, 2200, "Staples & Cooking", 4.5, 145, "protein-powder"),
    # Household
    ("Tissue Paper", "SoftTouch", "200 pulls", 99, 120, "Household", 4.2, 130, "tissue-paper"),
    ("Dog Food", "PetJoy", "1 kg", 410, 480, "Household", 4.4, 98, "dog-food"),
]


BANNERS = [
    ("Flat 20% Off", "On fresh fruits & vegetables", "Weekend Special", 20, "apple"),
    ("Shop Now, Pay Later", "Up to ₹10,000 instant VS Credit", "VS Credit", None, "milk"),
    ("₹100 Off First Order", "Use code VSNEW100", "New User", None, "juice"),
]
# Secondary carousel lower on Home.
MIDDLE_BANNERS = [
    ("Free Delivery Week", "On every order above ₹499", "Limited Time", None, "tissue-paper"),
    ("Stock Up & Save", "Bulk staples at wholesale prices", "Mega Saver", 15, "rice"),
]
# Product-spotlight cards (Blinkit-style: product PNG over a background).
SPOTLIGHT_SLUGS = ["chicken-meat", "honey-jar", "protein-powder"]
DEAL_SLUGS = ["apple", "chicken-meat", "cooking-oil"]


class Command(BaseCommand):
    help = "Seed a demo grocery catalog (categories + products with images)."

    def _seed_offers(self):
        order = 0
        for title, subtitle, badge, pct, slug in BANNERS:
            Offer.objects.get_or_create(
                type=Offer.Type.BANNER, title=title,
                defaults={
                    "placement": Offer.Placement.TOP,
                    "subtitle": subtitle, "badge": badge, "discount_percent": pct,
                    "image_url": img(slug), "sort_order": order,
                    "code": "VSNEW100" if "VSNEW100" in subtitle else "",
                },
            )
            order += 1
        # Middle-placement banners (second carousel lower on Home).
        for title, subtitle, badge, pct, slug in MIDDLE_BANNERS:
            Offer.objects.get_or_create(
                type=Offer.Type.BANNER, title=title,
                defaults={
                    "placement": Offer.Placement.MIDDLE,
                    "subtitle": subtitle, "badge": badge, "discount_percent": pct,
                    "image_url": img(slug), "sort_order": order,
                },
            )
            order += 1
        # Spotlight banners — a special product on sale (PNG over a background).
        for slug in SPOTLIGHT_SLUGS:
            p = Product.objects.filter(image_url=img(slug)).first()
            if not p:
                continue
            Offer.objects.get_or_create(
                type=Offer.Type.BANNER, title=f"{p.name} on Sale", product=p,
                defaults={
                    "placement": Offer.Placement.SPOTLIGHT,
                    "subtitle": p.brand, "badge": "Special Sale",
                    "deal_price": p.price, "original_price": p.mrp,
                    "discount_percent": p.discount_percent,
                    "image_url": p.image_url, "sort_order": order,
                },
            )
            order += 1
        # Deals link to real products so tapping opens the product page.
        for slug in DEAL_SLUGS:
            p = Product.objects.filter(image_url=img(slug)).first()
            if not p:
                continue
            Offer.objects.get_or_create(
                type=Offer.Type.DEAL, title=f"{p.name} Deal",
                defaults={
                    "subtitle": "Deal of the day", "product": p,
                    "deal_price": p.price, "original_price": p.mrp,
                    "discount_percent": p.discount_percent,
                    "image_url": p.image_url, "sort_order": order,
                },
            )
            order += 1
        # Coupon-type offers (for the offers screen) + Coupon rows (for validation).
        Offer.objects.get_or_create(
            type=Offer.Type.COUPON, title="₹100 off above ₹999",
            defaults={"subtitle": "On all categories", "code": "VS100", "sort_order": 0},
        )
        Offer.objects.get_or_create(
            type=Offer.Type.COUPON, title="15% off Fruits & Veg",
            defaults={"subtitle": "Max discount ₹150", "code": "FRESH15",
                      "discount_percent": 15, "sort_order": 1},
        )
        from datetime import timedelta

        from django.utils import timezone

        soon = timezone.now().date() + timedelta(days=14)
        month = timezone.now().date() + timedelta(days=30)
        coupons = [
            ("VS100", Coupon.DiscountType.FLAT, 100, 999, None, month),
            ("FRESH15", Coupon.DiscountType.PERCENT, 15, None, 150, soon),
            ("WEEKEND50", Coupon.DiscountType.FLAT, 50, 299, None, soon),
            ("BIG20", Coupon.DiscountType.PERCENT, 20, 1499, 300, month),
            ("VSNEW100", Coupon.DiscountType.FLAT, 100, 499, None, month),
        ]
        for code, dtype, value, min_order, max_disc, valid_to in coupons:
            Coupon.objects.get_or_create(
                code=code,
                defaults={"discount_type": dtype, "value": value,
                          "min_order": min_order, "max_discount": max_disc,
                          "valid_to": valid_to},
            )

    def _seed_faqs(self):
        faqs = [
            ("Credit", "How does VS Credit work?",
             "Buy groceries now and pay later. After KYC approval you get a credit "
             "limit to use at checkout; your spend is billed monthly and is "
             "interest-free if cleared by the due date."),
            ("Payments", "How do I pay my outstanding amount?",
             "Open the Credit tab and tap Pay Now. Settle via UPI, card, or "
             "net-banking — payments reflect instantly and restore your limit."),
            ("Credit", "How can I increase my credit limit?",
             "Your limit is reviewed automatically based on repayment history and "
             "activity. Paying on time and keeping KYC current improves eligibility."),
            ("Payments", "What happens if I miss a payment?",
             "A nominal late fee may apply and credit may pause until cleared. We "
             "send reminders before the due date."),
            ("Orders", "How can I contact support?",
             "Use the Support tab — Contact Support for chat, or Raise Ticket to "
             "log an order, payment, or account issue."),
            ("KYC", "How do I update my address?",
             "Go to Settings > Manage Addresses to add or edit delivery addresses. "
             "For KYC address changes, upload a valid proof from KYC Details."),
        ]
        for i, (cat, q, a) in enumerate(faqs):
            Faq.objects.get_or_create(
                question=q,
                defaults={"category": cat, "answer": a, "is_active": True,
                          "sort_order": i},
            )

    def handle(self, *args, **options):
        cats = {}
        for name, icon, rep in CATEGORIES:
            cat, _ = Category.objects.get_or_create(
                slug=slugify(name),
                defaults={
                    "name": name,
                    "icon_name": icon,
                    "image_url": img(rep),
                    "is_active": True,
                },
            )
            # Backfill image on pre-existing rows.
            if not cat.image_url:
                cat.image_url = img(rep)
                cat.save(update_fields=["image_url"])
            cats[name] = cat

        # Subcategories under each department.
        subs = {}
        sord = 100
        for parent_name, sublist in SUBCATEGORIES.items():
            parent = cats[parent_name]
            for sub_name, icon, rep in sublist:
                sub, _ = Category.objects.get_or_create(
                    slug=slugify(f"{parent_name} {sub_name}"),
                    defaults={
                        "name": sub_name, "parent": parent, "icon_name": icon,
                        "image_url": img(rep), "is_active": True,
                        "sort_order": sord,
                    },
                )
                if sub.parent_id != parent.id:
                    sub.parent = parent
                    sub.save(update_fields=["parent"])
                if not sub.image_url:
                    sub.image_url = img(rep)
                    sub.save(update_fields=["image_url"])
                subs[sub_name] = sub
                sord += 1

        created = 0
        for name, brand, unit, price, mrp, cat_name, rating, reviews, slug in PRODUCTS:
            # Assign each product to its leaf subcategory (fall back to department).
            leaf = subs.get(PRODUCT_SUBCAT.get(slug, ""), cats[cat_name])
            p = Product.objects.filter(name=name).first()
            if p is None:
                Product.objects.create(
                    name=name, category=leaf, brand=brand, unit=unit,
                    price=price, mrp=mrp, rating=rating, review_count=reviews,
                    in_stock=True, stock_count=50, available_count=50,
                    image_url=img(slug),
                    description=f"Fresh {name.lower()} delivered to your door.",
                    specifications={"Brand": brand, "Unit": unit},
                )
                created += 1
            elif p.category_id != leaf.id:
                # Move an existing product into its subcategory (idempotent).
                p.category = leaf
                p.save(update_fields=["category"])

        # Subcategory counts = own products; department counts = sum of children.
        for sub in subs.values():
            sub.product_count = sub.products.count()
            sub.save(update_fields=["product_count"])
        for parent in cats.values():
            total = parent.products.count() + sum(
                c.products.count() for c in parent.children.all()
            )
            parent.product_count = total
            parent.save(update_fields=["product_count"])

        self._seed_offers()
        self._seed_faqs()

        self.stdout.write(
            self.style.SUCCESS(
                f"Seeded {len(cats)} departments + {len(subs)} subcategories, "
                f"{created} new products ({Product.objects.count()} total)."
            )
        )
