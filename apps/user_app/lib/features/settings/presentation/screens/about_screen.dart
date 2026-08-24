import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/constants/app_constants.dart';
import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';

/// Launch an external URI (web `https:`, `mailto:`, or `tel:`) from the About
/// screen's contact rows, reporting a graceful snackbar if no handler exists.
Future<void> _launchExternal(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // No handler for this scheme — fall through to the failure snackbar.
  }
  if (!context.mounted) return;
  final what = switch (uri.scheme) {
    'tel' => context.l10n.settingsOpenTargetDialer,
    'mailto' => context.l10n.settingsOpenTargetEmail,
    _ => context.l10n.settingsOpenTargetLink,
  };
  context.showSnack(context.l10n.settingsCouldNotOpen(what));
}

/// The running app version + build number, read from the platform package info.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'Version ${info.version} (${info.buildNumber})';
});

/// About / Legal & Privacy screen — brand header, company information with a
/// mission statement, a "What We Offer" feature grid, a "Get in Touch" contact
/// card with a social row, and a legal & compliance links card.
///
/// Matches the "About VS Mart" client design.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: VSAppBar(title: context.l10n.accountAboutUs),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: const [
            _BrandHeader(),
            AppSpacing.vGapXl,
            _CompanyInfoCard(),
            AppSpacing.vGapXl,
            _OfferSection(),
            AppSpacing.vGapXl,
            _ContactCard(),
            AppSpacing.vGapXl,
            _LegalCard(),
            AppSpacing.vGapLg,
            _Footer(),
          ],
        ),
      ),
    );
  }
}

/// Centered brand badge, app name, and version pill.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: const BoxDecoration(
            gradient: AppColors.greenGradient,
            borderRadius: AppRadius.brXl,
          ),
          child: const Icon(
            Icons.storefront_rounded,
            color: AppColors.white,
            size: 44,
          ),
        ),
        AppSpacing.vGapLg,
        Text(AppConstants.appName, style: AppTypography.headlineLarge),
        AppSpacing.vGapSm,
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xxs,
          ),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: AppRadius.brPill,
            border: Border.all(color: vs.border),
          ),
          child: Consumer(
            builder: (context, ref, _) {
              final version = ref.watch(appVersionProvider).valueOrNull;
              return Text(
                version ?? 'Version …',
                style:
                    AppTypography.labelSmall.copyWith(color: vs.textSecondary),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// White card: company name, description, and an inset mission statement.
class _CompanyInfoCard extends StatelessWidget {
  const _CompanyInfoCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.apartment_rounded,
            iconColor: AppColors.vsGreen,
            title: context.l10n.settingsCompanyInfo,
          ),
          AppSpacing.vGapLg,
          Text(
            'Knight21 Digi Hub Pvt Ltd',
            style: AppTypography.titleMedium,
          ),
          AppSpacing.vGapSm,
          Text(
            context.l10n.settingsCompanyDescription,
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: vs.brandTint,
              borderRadius: AppRadius.brMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.flag_rounded,
                      size: 18,
                      color: AppColors.vsGreen,
                    ),
                    AppSpacing.hGapSm,
                    Text(context.l10n.settingsMissionStatement,
                        style: AppTypography.titleMedium
                            .copyWith(color: AppColors.vsGreen)),
                  ],
                ),
                AppSpacing.vGapSm,
                Text(
                  context.l10n.settingsMissionText,
                  style: AppTypography.bodyMedium.copyWith(
                    color: context.colors.onSurface,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "What We Offer" 2x2 feature grid.
class _OfferSection extends StatelessWidget {
  const _OfferSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Text(context.l10n.settingsWhatWeOffer,
              style: AppTypography.headlineSmall),
        ),
        AppSpacing.vGapMd,
        Row(
          children: [
            Expanded(
              child: _FeatureCard(
                icon: Icons.shopping_basket_rounded,
                color: AppColors.vsGreen,
                title: context.l10n.settingsOfferGroceryTitle,
                subtitle: context.l10n.settingsOfferGrocerySubtitle,
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: _FeatureCard(
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.trustBlue,
                title: 'VS Credit',
                subtitle: context.l10n.settingsOfferCreditSubtitle,
              ),
            ),
          ],
        ),
        AppSpacing.vGapMd,
        Row(
          children: [
            Expanded(
              child: _FeatureCard(
                icon: Icons.local_shipping_rounded,
                color: AppColors.vsGreen,
                title: context.l10n.settingsOfferDeliveryTitle,
                subtitle: context.l10n.settingsOfferDeliverySubtitle,
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: _FeatureCard(
                icon: Icons.sync_rounded,
                color: AppColors.trustBlue,
                title: context.l10n.settingsOfferCollectionsTitle,
                subtitle: context.l10n.settingsOfferCollectionsSubtitle,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final tint = color == AppColors.trustBlue ? vs.trustTint : vs.brandTint;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: AppRadius.brMd,
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          AppSpacing.vGapMd,
          Text(title, style: AppTypography.titleMedium),
          AppSpacing.vGapXs,
          Text(
            subtitle,
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// "Get in Touch" card: contact rows + office address + social row.
class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.settingsGetInTouch,
              style: AppTypography.headlineSmall),
          AppSpacing.vGapMd,
          _ContactRow(
            icon: Icons.language_rounded,
            label: context.l10n.settingsWebsite,
            value: 'www.thevsmart.com',
            onTap: () => _launchExternal(
                context, Uri.parse('https://www.thevsmart.com')),
          ),
          Divider(height: 1, color: vs.border),
          _ContactRow(
            icon: Icons.mail_outline_rounded,
            label: context.l10n.accountEmail,
            value: AppConstants.supportEmail,
            onTap: () => _launchExternal(
                context, Uri(scheme: 'mailto', path: AppConstants.supportEmail)),
          ),
          Divider(height: 1, color: vs.border),
          _ContactRow(
            icon: Icons.call_rounded,
            label: context.l10n.accountPhone,
            value: AppConstants.supportPhone,
            onTap: () => _launchExternal(
                context, Uri(scheme: 'tel', path: AppConstants.supportPhone)),
          ),
          Divider(height: 1, color: vs.border),
          AppSpacing.vGapMd,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 22,
                color: AppColors.vsGreen,
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.settingsOfficeAddress,
                        style: AppTypography.titleMedium),
                    AppSpacing.vGapXs,
                    // BUSINESS CONFIG: neutral placeholder. Replace with the
                    // company's real registered office address (VS Mart operates
                    // in India — the previous "New York, NY" value was wrong).
                    Text(
                      'Knight21 Digi Hub Pvt Ltd\n'
                      'Bengaluru, Karnataka\n'
                      'India',
                      style: AppTypography.bodyMedium
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapLg,
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            decoration: BoxDecoration(
              color: vs.brandTint,
              borderRadius: AppRadius.brMd,
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SocialButton(icon: Icons.facebook_rounded, label: 'f'),
                AppSpacing.hGapMd,
                _SocialButton(icon: Icons.camera_alt_rounded, label: 'ig'),
                AppSpacing.hGapMd,
                _SocialButton(icon: Icons.play_circle_fill_rounded, label: 'yt'),
                AppSpacing.hGapMd,
                _SocialButton(icon: Icons.business_center_rounded, label: 'in'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.vsGreen),
            AppSpacing.hGapMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.titleMedium),
                  AppSpacing.vGapXs,
                  Text(
                    value,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: vs.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  const _SocialButton({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: context.colors.surface,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: AppColors.vsGreen),
    );
  }
}

/// "Legal & Compliance" card with external-link rows.
class _LegalCard extends StatelessWidget {
  const _LegalCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: Icons.gavel_rounded,
            iconColor: AppColors.trustBlue,
            title: context.l10n.settingsLegalCompliance,
          ),
          AppSpacing.vGapSm,
          _LegalRow(
            icon: Icons.description_outlined,
            label: context.l10n.authTermsOfService,
            onTap: () => context.pushNamed(RouteNames.terms),
          ),
          Divider(height: 1, color: vs.border),
          _LegalRow(
            icon: Icons.shield_outlined,
            label: context.l10n.accountPrivacy,
            onTap: () => context.pushNamed(RouteNames.privacyPolicy),
          ),
          // Third-party OSS license viewer removed: it's Flutter's own
          // package-license dump (React/Dio/etc.), not the business
          // accreditations "Licenses & accreditations" actually implied to a
          // customer — a genuine label/content mismatch, and not something
          // a customer-facing legal card should surface at all.
        ],
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Row(
          children: [
            Icon(icon, size: 22, color: context.colors.onSurface),
            AppSpacing.hGapMd,
            Expanded(child: Text(label, style: AppTypography.bodyLarge)),
            Icon(Icons.open_in_new_rounded, size: 18, color: vs.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Copyright / tagline footer.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      children: [
        Text(
          AppConstants.appTagline,
          textAlign: TextAlign.center,
          style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
        ),
        AppSpacing.vGapXs,
        Text(
          context.l10n.settingsAllRightsReserved(AppConstants.appName),
          textAlign: TextAlign.center,
          style: AppTypography.labelSmall.copyWith(color: vs.textSecondary),
        ),
      ],
    );
  }
}

/// White rounded card container used across the screen.
class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: child,
    );
  }
}

/// Section header: tinted-free leading icon + title.
class _CardHeader extends StatelessWidget {
  const _CardHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
  });

  final IconData icon;
  final Color iconColor;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 22, color: iconColor),
        AppSpacing.hGapSm,
        Text(title, style: AppTypography.headlineSmall),
      ],
    );
  }
}
