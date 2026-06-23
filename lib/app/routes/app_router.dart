import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/address/domain/entities/address.dart';
import '../../features/address/presentation/screens/add_address_screen.dart';
import '../../features/address/presentation/screens/address_selection_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/otp_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../../features/catalog/presentation/screens/categories_screen.dart';
import '../../features/catalog/presentation/screens/product_detail_screen.dart';
import '../../features/catalog/presentation/screens/product_listing_screen.dart';
import '../../features/catalog/presentation/screens/product_section_screen.dart';
import '../../features/catalog/presentation/screens/subcategory_screen.dart';
import '../../features/checkout/presentation/screens/checkout_screen.dart';
import '../../features/checkout/presentation/screens/order_success_screen.dart';
import '../../features/checkout/presentation/screens/payment_screen.dart';
import '../../features/billing/presentation/screens/billing_dashboard_screen.dart';
import '../../features/billing/presentation/screens/collections_screen.dart';
import '../../features/billing/presentation/screens/invoice_detail_screen.dart';
import '../../features/billing/presentation/screens/invoices_screen.dart';
import '../../features/billing/presentation/screens/payment_history_screen.dart';
import '../../features/billing/presentation/screens/repayment_screen.dart';
import '../../features/billing/presentation/screens/repayment_success_screen.dart';
import '../../features/billing/presentation/screens/statement_detail_screen.dart';
import '../../features/billing/presentation/screens/statements_screen.dart';
import '../../features/credit/presentation/screens/make_payment_screen.dart';
import '../../features/credit/presentation/screens/payment_success_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/kyc/presentation/screens/kyc_dashboard_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/offers/presentation/screens/offers_screen.dart';
import '../../features/onboarding/presentation/screens/onboarding_screen.dart';
import '../../features/orders/presentation/screens/order_details_screen.dart';
import '../../features/orders/presentation/screens/order_tracking_screen.dart';
import '../../features/orders/presentation/screens/orders_list_screen.dart';
import '../../features/profile/presentation/screens/account_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/support/presentation/screens/support_screen.dart';
import '../../features/wishlist/presentation/screens/wishlist_screen.dart';
import '../../features/verification/presentation/screens/application_submitted_screen.dart';
import '../../features/verification/presentation/screens/credit_application_screen.dart';
import '../../features/verification/presentation/screens/identity_verification_screen.dart';
import '../../features/verification/presentation/screens/review_screen.dart';
import '../../features/verification/presentation/screens/selfie_verification_screen.dart';
import '../../features/verification/presentation/screens/verification_status_screen.dart';
import '../../features/auth/presentation/screens/registration_success_screen.dart';
import '../../features/billing/presentation/screens/cash_collection_request_screen.dart';
import '../../features/billing/presentation/screens/outstanding_due_screen.dart';
import '../../features/kyc/presentation/screens/kyc_details_screen.dart';
import '../../features/legal/presentation/screens/privacy_policy_screen.dart';
import '../../features/legal/presentation/screens/terms_screen.dart';
import '../../features/notifications/presentation/screens/payment_reminders_screen.dart';
import '../../features/offers/presentation/screens/coupons_wallet_screen.dart';
import '../../features/offers/presentation/screens/todays_deals_screen.dart';
import '../../features/profile/presentation/screens/family_info_screen.dart';
import '../../features/referral/presentation/screens/refer_earn_screen.dart';
import '../../features/settings/presentation/screens/about_screen.dart';
import '../../features/settings/presentation/screens/language_screen.dart';
import '../../features/settings/presentation/screens/notification_settings_screen.dart';
import '../../features/settings/presentation/screens/security_settings_screen.dart';
import '../../features/serviceability/presentation/screens/not_serviceable_screen.dart';
import '../../features/support/presentation/screens/faq_screen.dart';
import '../../features/support/presentation/screens/raise_ticket_screen.dart';
import '../../features/support/presentation/screens/support_conversation_screen.dart';
import '../../features/support/presentation/screens/ticket_details_screen.dart';
import '../../features/support/presentation/screens/ticket_history_screen.dart';
import '../../features/verification/presentation/screens/aadhaar_verification_screen.dart';
import '../../features/verification/presentation/screens/pan_verification_screen.dart';
import '../../features/verification/presentation/screens/residence_verification_screen.dart';
import '../../features/loyalty/presentation/screens/loyalty_screen.dart';
import '../../features/returns/presentation/screens/returns_screen.dart';
import '../../features/returns/presentation/screens/request_return_screen.dart';
import '../../features/content/presentation/screens/content_page_screen.dart';
import '../../shared/providers/settings_provider.dart';
import '../../shared/widgets/splash_screen.dart';
import '../constants/app_constants.dart';
import 'app_shell.dart';
import 'route_guards.dart';
import 'route_paths.dart';

/// Gates initial navigation: enforces a minimum splash duration so the brand
/// screen is visible and bootstrap side-effects can settle.
final appStartupProvider = FutureProvider<void>((ref) async {
  await Future<void>.delayed(AppConstants.splashDuration);
});

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

/// The application [GoRouter]. Rebuilds its redirect when auth/onboarding/
/// startup state changes via a bridged [Listenable].
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref
    ..listen(authGuardProvider, (_, __) => refresh.value++)
    ..listen(onboardingSeenProvider, (_, __) => refresh.value++)
    ..listen(guestModeProvider, (_, __) => refresh.value++)
    ..listen(appStartupProvider, (_, __) => refresh.value++);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: RoutePaths.splash,
    debugLogDiagnostics: true,
    refreshListenable: refresh,
    redirect: (context, state) {
      final startup = ref.read(appStartupProvider);
      final onboarded = ref.read(onboardingSeenProvider);
      final stage = ref.read(authGuardProvider);
      final isGuest = ref.read(guestModeProvider);
      final loc = state.matchedLocation;

      // Hold on splash until startup completes.
      if (startup.isLoading) {
        return loc == RoutePaths.splash ? null : RoutePaths.splash;
      }

      // Resolve the post-splash landing screen by lifecycle stage.
      if (loc == RoutePaths.splash) {
        if (!onboarded) return RoutePaths.onboarding;
        if (stage == UserStage.unauthenticated) {
          // A returning guest lands straight on Home; everyone else, login.
          return isGuest ? RoutePaths.home : RoutePaths.login;
        }
        return landingForStage(stage);
      }

      // Unauthenticated handling.
      if (stage == UserStage.unauthenticated) {
        // Guests may browse the catalog freely; only personal/transactional
        // routes (checkout, orders, credit, KYC…) bounce them to login.
        if (isGuest) {
          return guestLocationRequiresAuth(loc) ? RoutePaths.login : null;
        }
        // Non-guests may only reach onboarding / login / OTP / register / legal.
        return kVisitorLocations.contains(loc) ? null : RoutePaths.login;
      }

      // Authenticated: enforce the verification lifecycle guard.
      return resolveGuardRedirect(stage, loc);
    },
    routes: [
      GoRoute(
        path: RoutePaths.splash,
        name: RouteNames.splash,
        builder: (_, __) => const SplashScreen(),
      ),

      // ----- Auth flow -----
      GoRoute(
        path: RoutePaths.onboarding,
        name: RouteNames.onboarding,
        builder: (_, __) => const OnboardingScreen(),
      ),
      GoRoute(
        path: RoutePaths.login,
        name: RouteNames.login,
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: RoutePaths.otp,
        name: RouteNames.otp,
        builder: (_, __) => const OtpScreen(),
      ),
      GoRoute(
        path: RoutePaths.register,
        name: RouteNames.register,
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: RoutePaths.kyc,
        name: RouteNames.kyc,
        builder: (_, __) => const KycDashboardScreen(),
      ),

      // ----- Verification flow (full-screen) -----
      GoRoute(
        path: RoutePaths.identityVerification,
        name: RouteNames.identityVerification,
        builder: (_, __) => const IdentityVerificationScreen(),
      ),
      GoRoute(
        path: RoutePaths.selfieVerification,
        name: RouteNames.selfieVerification,
        builder: (_, __) => const SelfieVerificationScreen(),
      ),
      GoRoute(
        path: RoutePaths.creditApplication,
        name: RouteNames.creditApplication,
        builder: (_, __) => const CreditApplicationScreen(),
      ),
      GoRoute(
        path: RoutePaths.verificationReview,
        name: RouteNames.verificationReview,
        builder: (_, __) => const ReviewScreen(),
      ),
      GoRoute(
        path: RoutePaths.applicationSubmitted,
        name: RouteNames.applicationSubmitted,
        builder: (_, __) => const ApplicationSubmittedScreen(),
      ),
      GoRoute(
        path: RoutePaths.verificationStatus,
        name: RouteNames.verificationStatus,
        builder: (_, __) => const VerificationStatusScreen(),
      ),

      // ----- Main shell (bottom-nav tabs) -----
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootKey,
        builder: (_, __, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellKey,
            routes: [
              GoRoute(
                path: RoutePaths.home,
                name: RouteNames.home,
                builder: (_, __) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.categories,
                name: RouteNames.categories,
                builder: (_, __) => const CategoriesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.cart,
                name: RouteNames.cart,
                builder: (_, __) => const CartScreen(),
              ),
            ],
          ),
          // Credit tab — ledger-derived billing dashboard with nested billing
          // sub-screens (statements, invoices, history, repayment).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.creditDashboard,
                name: RouteNames.creditDashboard,
                builder: (_, __) => const BillingDashboardScreen(),
                routes: [
                  GoRoute(
                    path: 'statements',
                    name: RouteNames.statements,
                    builder: (_, __) => const StatementsScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        name: RouteNames.statementDetail,
                        builder: (_, state) => StatementDetailScreen(
                          statementId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'invoices',
                    name: RouteNames.invoices,
                    builder: (_, __) => const InvoicesScreen(),
                    routes: [
                      GoRoute(
                        path: ':id',
                        name: RouteNames.invoiceDetail,
                        builder: (_, state) => InvoiceDetailScreen(
                          invoiceId: state.pathParameters['id'] ?? '',
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'history',
                    name: RouteNames.paymentHistory,
                    builder: (_, __) => const PaymentHistoryScreen(),
                  ),
                  GoRoute(
                    path: 'collections',
                    name: RouteNames.collections,
                    builder: (_, __) => const CollectionsScreen(),
                  ),
                  GoRoute(
                    path: 'repay',
                    name: RouteNames.repayment,
                    builder: (_, __) => const RepaymentScreen(),
                    routes: [
                      GoRoute(
                        path: 'success',
                        name: RouteNames.repaymentSuccess,
                        builder: (_, __) => const RepaymentSuccessScreen(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RoutePaths.account,
                name: RouteNames.account,
                builder: (_, __) => const AccountScreen(),
              ),
            ],
          ),
        ],
      ),

      // ----- Catalog / search (root-level, full screen) -----
      // Sub-categories is a root-level route (not nested in the Categories tab)
      // so it pushes full-screen with a proper back button no matter which tab
      // opened it (home rail or categories) — back returns to the opener.
      GoRoute(
        path: RoutePaths.subCategories,
        name: RouteNames.subCategories,
        builder: (_, state) => SubCategoryScreen(
          departmentId: state.pathParameters['categoryId'] ?? '',
          departmentName: state.uri.queryParameters['title'] ?? 'Category',
        ),
      ),
      GoRoute(
        path: RoutePaths.products,
        name: RouteNames.products,
        builder: (_, state) => ProductListingScreen(
          categoryId: state.uri.queryParameters['categoryId'],
          query: state.uri.queryParameters['query'],
          title: state.uri.queryParameters['title'] ?? 'Products',
        ),
      ),
      GoRoute(
        path: RoutePaths.popularProducts,
        name: RouteNames.popularProducts,
        builder: (_, __) => const ProductSectionScreen(section: ProductSection.popular),
      ),
      GoRoute(
        path: RoutePaths.recommendedProducts,
        name: RouteNames.recommendedProducts,
        builder: (_, __) => const ProductSectionScreen(section: ProductSection.recommended),
      ),
      GoRoute(
        path: RoutePaths.recentlyOrdered,
        name: RouteNames.recentlyOrdered,
        builder: (_, __) => const ProductSectionScreen(section: ProductSection.recentlyOrdered),
      ),
      GoRoute(
        path: RoutePaths.salesProducts,
        name: RouteNames.salesProducts,
        builder: (_, __) => const ProductSectionScreen(section: ProductSection.sales),
      ),
      GoRoute(
        path: RoutePaths.productDetails,
        name: RouteNames.productDetails,
        builder: (_, state) => ProductDetailScreen(
          productId: state.pathParameters['productId'],
          heroTag: state.extra is String ? state.extra as String : null,
        ),
      ),
      GoRoute(
        path: RoutePaths.search,
        name: RouteNames.search,
        builder: (_, __) => const SearchScreen(),
      ),
      GoRoute(
        path: RoutePaths.offers,
        name: RouteNames.offers,
        builder: (_, __) => const OffersScreen(),
      ),
      GoRoute(
        path: RoutePaths.wishlist,
        name: RouteNames.wishlist,
        builder: (_, __) => const WishlistScreen(),
      ),

      // ----- Credit payment (full-screen) -----
      GoRoute(
        path: RoutePaths.makePayment,
        name: RouteNames.makePayment,
        builder: (_, __) => const MakePaymentScreen(),
      ),
      GoRoute(
        path: RoutePaths.paymentSuccess,
        name: RouteNames.paymentSuccess,
        builder: (_, __) => const PaymentSuccessScreen(),
      ),

      // ----- Checkout -----
      GoRoute(
        path: RoutePaths.checkout,
        name: RouteNames.checkout,
        builder: (_, __) => const CheckoutScreen(),
        routes: [
          GoRoute(
            path: 'payment',
            name: RouteNames.payment,
            builder: (_, __) => const PaymentScreen(),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.orderSuccess,
        name: RouteNames.orderSuccess,
        builder: (_, __) => const OrderSuccessScreen(),
      ),

      // ----- Orders -----
      GoRoute(
        path: RoutePaths.orders,
        name: RouteNames.orders,
        builder: (_, __) => const OrdersListScreen(),
        routes: [
          GoRoute(
            path: ':orderId',
            name: RouteNames.orderDetails,
            builder: (_, state) => OrderDetailsScreen(
              orderId: state.pathParameters['orderId'] ?? '',
            ),
            routes: [
              GoRoute(
                path: 'tracking',
                name: RouteNames.orderTracking,
                builder: (_, state) => OrderTrackingScreen(
                  orderId: state.pathParameters['orderId'] ?? '',
                ),
              ),
            ],
          ),
        ],
      ),

      // ----- Profile / settings / support -----
      GoRoute(
        path: RoutePaths.profile,
        name: RouteNames.profile,
        builder: (_, __) => const ProfileScreen(),
      ),
      GoRoute(
        path: RoutePaths.addresses,
        name: RouteNames.addresses,
        builder: (_, __) => const AddressSelectionScreen(),
        routes: [
          GoRoute(
            path: 'new',
            name: RouteNames.addAddress,
            builder: (_, state) =>
                AddAddressScreen(initial: state.extra as Address?),
          ),
        ],
      ),
      GoRoute(
        path: RoutePaths.notifications,
        name: RouteNames.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: RoutePaths.settings,
        name: RouteNames.settings,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: RoutePaths.support,
        name: RouteNames.support,
        builder: (_, __) => const SupportScreen(),
      ),

      // ----- Secondary screens -----
      GoRoute(
        path: RoutePaths.privacyPolicy,
        name: RouteNames.privacyPolicy,
        builder: (_, __) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: RoutePaths.terms,
        name: RouteNames.terms,
        builder: (_, __) => const TermsScreen(),
      ),
      GoRoute(
        path: RoutePaths.about,
        name: RouteNames.about,
        builder: (_, __) => const AboutScreen(),
      ),
      GoRoute(
        path: RoutePaths.faq,
        name: RouteNames.faq,
        builder: (_, __) => const FaqScreen(),
      ),
      GoRoute(
        path: RoutePaths.raiseTicket,
        name: RouteNames.raiseTicket,
        builder: (_, __) => const RaiseTicketScreen(),
      ),
      GoRoute(
        path: RoutePaths.tickets,
        name: RouteNames.tickets,
        builder: (_, __) => const TicketHistoryScreen(),
      ),
      GoRoute(
        path: RoutePaths.ticketDetails,
        name: RouteNames.ticketDetails,
        builder: (_, __) => const TicketDetailsScreen(),
      ),
      GoRoute(
        path: RoutePaths.supportChat,
        name: RouteNames.supportChat,
        builder: (_, state) =>
            SupportConversationScreen(code: state.extra as String?),
      ),
      GoRoute(
        path: RoutePaths.language,
        name: RouteNames.language,
        builder: (_, __) => const LanguageScreen(),
      ),
      GoRoute(
        path: RoutePaths.notificationSettings,
        name: RouteNames.notificationSettings,
        builder: (_, __) => const NotificationSettingsScreen(),
      ),
      GoRoute(
        path: RoutePaths.securitySettings,
        name: RouteNames.securitySettings,
        builder: (_, __) => const SecuritySettingsScreen(),
      ),
      GoRoute(
        path: RoutePaths.referEarn,
        name: RouteNames.referEarn,
        builder: (_, __) => const ReferEarnScreen(),
      ),
      GoRoute(
        path: RoutePaths.notServiceable,
        name: RouteNames.notServiceable,
        builder: (_, state) {
          final extra = state.extra;
          if (extra is Address) {
            return NotServiceableScreen(
              latitude: extra.latitude,
              longitude: extra.longitude,
              pincode: extra.pincode,
            );
          }
          return const NotServiceableScreen();
        },
      ),
      GoRoute(
        path: RoutePaths.coupons,
        name: RouteNames.coupons,
        builder: (_, __) => const CouponsWalletScreen(),
      ),
      GoRoute(
        path: RoutePaths.todaysDeals,
        name: RouteNames.todaysDeals,
        builder: (_, __) => const TodaysDealsScreen(),
      ),
      GoRoute(
        path: RoutePaths.outstandingDue,
        name: RouteNames.outstandingDue,
        builder: (_, __) => const OutstandingDueScreen(),
      ),
      GoRoute(
        path: RoutePaths.paymentReminders,
        name: RouteNames.paymentReminders,
        builder: (_, __) => const PaymentRemindersScreen(),
      ),
      GoRoute(
        path: RoutePaths.familyInfo,
        name: RouteNames.familyInfo,
        builder: (_, __) => const FamilyInfoScreen(),
      ),
      GoRoute(
        path: RoutePaths.kycDetails,
        name: RouteNames.kycDetails,
        builder: (_, __) => const KycDetailsScreen(),
      ),
      GoRoute(
        path: RoutePaths.residenceVerification,
        name: RouteNames.residenceVerification,
        builder: (_, __) => const ResidenceVerificationScreen(),
      ),
      GoRoute(
        path: RoutePaths.registrationSuccess,
        name: RouteNames.registrationSuccess,
        builder: (_, __) => const RegistrationSuccessScreen(),
      ),
      GoRoute(
        path: RoutePaths.aadhaarVerification,
        name: RouteNames.aadhaarVerification,
        builder: (_, __) => const AadhaarVerificationScreen(),
      ),
      GoRoute(
        path: RoutePaths.panVerification,
        name: RouteNames.panVerification,
        builder: (_, __) => const PanVerificationScreen(),
      ),
      GoRoute(
        path: RoutePaths.cashCollectionRequest,
        name: RouteNames.cashCollectionRequest,
        builder: (_, __) => const CashCollectionRequestScreen(),
      ),

      // ----- Phase 3: customer engagement modules -----
      GoRoute(
        path: RoutePaths.rewards,
        name: RouteNames.rewards,
        builder: (_, __) => const LoyaltyScreen(),
      ),
      GoRoute(
        path: RoutePaths.returns,
        name: RouteNames.returns,
        builder: (_, __) => const ReturnsScreen(),
      ),
      GoRoute(
        path: RoutePaths.requestReturn,
        name: RouteNames.requestReturn,
        builder: (_, state) =>
            RequestReturnScreen(orderCode: state.extra as String? ?? ''),
      ),
      GoRoute(
        path: RoutePaths.contact,
        name: RouteNames.contact,
        builder: (_, __) =>
            const ContentPageScreen(slug: 'contact', title: 'Contact Us'),
      ),
      GoRoute(
        path: RoutePaths.careers,
        name: RouteNames.careers,
        builder: (_, __) =>
            const ContentPageScreen(slug: 'careers', title: 'Careers'),
      ),
    ],
    errorBuilder: (_, state) => Scaffold(
      body: Center(child: Text('Route not found: ${state.uri}')),
    ),
  );
});
