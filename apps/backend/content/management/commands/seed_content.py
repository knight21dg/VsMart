"""Seed CMS pages so the content API returns real, multi-paragraph copy.

    python manage.py seed_content

Idempotent — safe to run repeatedly (get_or_create by slug).
"""
from django.core.management.base import BaseCommand

from content.models import Page

# slug, type, title, sort_order, body
PAGES = [
    (
        "about",
        Page.Type.ABOUT,
        "About VS Mart",
        10,
        """VS Mart is your neighbourhood grocery store, reimagined for the way you shop today. We bring fresh produce, daily essentials, and household favourites right to your doorstep, so you can spend less time running errands and more time on what matters.

Founded with a simple belief that good groceries should be affordable and accessible to everyone, VS Mart partners directly with farmers, local suppliers, and trusted brands to keep quality high and prices fair. Every order is hand-picked and carefully packed by people who care.

Beyond convenience, we are building a community. Our flexible credit options, family accounts, and referral rewards are designed to help households manage their everyday spending with confidence. Thank you for making VS Mart a part of your daily life.""",
    ),
    (
        "contact",
        Page.Type.CONTACT,
        "Contact Us",
        20,
        """We would love to hear from you. Whether you have a question about an order, feedback on a product, or just want to say hello, our support team is here to help.

Customer Support: +91 00000 00000
Email: support@vsmart.example
Hours: Monday to Saturday, 8:00 AM to 9:00 PM

For order-related queries, please keep your order number handy so we can assist you faster. You can also raise a request directly from the Help & Support section in the app, and one of our team members will get back to you as soon as possible.

Registered Office: VS Mart, 123 Market Road, Your City, 500000.""",
    ),
    (
        "careers",
        Page.Type.CAREERS,
        "Careers at VS Mart",
        30,
        """At VS Mart, we are on a mission to make everyday shopping simpler, fairer, and more delightful, and we are looking for people who share that passion.

We are a fast-growing team that values ownership, curiosity, and kindness. From technology and operations to warehouse and delivery, every role at VS Mart has a direct impact on the families we serve. We invest in our people with hands-on learning, clear growth paths, and a culture that celebrates initiative.

If you enjoy solving real problems and want to help build something that millions of households can rely on, we want to meet you. Send your resume and a short note about what excites you to careers@vsmart.example, and tell us how you would like to contribute.""",
    ),
    (
        "terms",
        Page.Type.TERMS,
        "Terms of Service",
        40,
        """Welcome to VS Mart. By accessing or using our app and services, you agree to be bound by these Terms of Service. Please read them carefully before placing an order.

Use of the Service: You agree to provide accurate account information and to use VS Mart only for lawful purposes. You are responsible for maintaining the confidentiality of your account credentials and for all activity under your account.

Orders and Pricing: All orders are subject to acceptance and availability. Prices, offers, and product information are subject to change without notice. We make every effort to ensure accuracy, but errors may occasionally occur, and we reserve the right to correct them.

Payments and Credit: Where credit facilities are offered, repayment terms and any applicable charges will be disclosed at the time of use. Failure to repay outstanding amounts may affect your eligibility for future credit.

Limitation of Liability: VS Mart is not liable for any indirect or consequential losses arising from the use of the service, to the maximum extent permitted by law. We may update these terms from time to time, and continued use of the service constitutes acceptance of the revised terms.""",
    ),
    (
        "privacy",
        Page.Type.PRIVACY,
        "Privacy Policy",
        50,
        """Your privacy matters to us. This Privacy Policy explains what information VS Mart collects, how we use it, and the choices you have.

Information We Collect: We collect information you provide directly, such as your name, phone number, delivery address, and order history. We also collect limited technical data, like device and usage information, to keep the service secure and to improve your experience.

How We Use Your Information: We use your information to process orders, provide customer support, personalise offers, prevent fraud, and comply with legal obligations. We do not sell your personal information to third parties.

Sharing and Security: We share information only with trusted partners who help us operate the service, such as delivery and payment providers, under strict confidentiality obligations. We apply reasonable technical and organisational measures to protect your data.

Your Choices: You may review and update your account information at any time, and you may contact us to request deletion of your data, subject to legal requirements. For any privacy-related questions, please reach us at privacy@vsmart.example.""",
    ),
]


class Command(BaseCommand):
    help = "Seed CMS pages (About, Contact, Careers, Terms, Privacy)."

    def handle(self, *args, **options):
        created = 0
        for slug, page_type, title, sort_order, body in PAGES:
            _, was_created = Page.objects.get_or_create(
                slug=slug,
                defaults={
                    "type": page_type,
                    "title": title,
                    "body": body,
                    "sort_order": sort_order,
                    "is_active": True,
                },
            )
            if was_created:
                created += 1
                self.stdout.write(self.style.SUCCESS(f"Created page: {slug}"))
            else:
                self.stdout.write(f"Page already exists: {slug}")

        self.stdout.write(
            self.style.SUCCESS(
                f"Done. {created} created, {len(PAGES) - created} already present."
            )
        )
