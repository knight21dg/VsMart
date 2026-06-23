import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../app/constants/app_constants.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';

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
      appBar: const VSAppBar(title: 'About VS Mart'),
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
          const _CardHeader(
            icon: Icons.apartment_rounded,
            iconColor: AppColors.vsGreen,
            title: 'Company Information',
          ),
          AppSpacing.vGapLg,
          Text(
            'Knight21 Digi Hub Pvt Ltd',
            style: AppTypography.titleMedium,
          ),
          AppSpacing.vGapSm,
          Text(
            'VS Mart is a pioneering hybrid ecosystem bridging the gap between '
            'daily grocery commerce and flexible financial credit, ensuring '
            'families have seamless access to essentials when they need them '
            'most.',
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
                    Text('Mission Statement',
                        style: AppTypography.titleMedium
                            .copyWith(color: AppColors.vsGreen)),
                  ],
                ),
                AppSpacing.vGapSm,
                Text(
                  '"To empower communities by providing fresh, affordable '
                  'groceries coupled with trustworthy, flexible credit '
                  'solutions, creating a stress-free shopping experience."',
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
          child: Text('What We Offer', style: AppTypography.headlineSmall),
        ),
        AppSpacing.vGapMd,
        const Row(
          children: [
            Expanded(
              child: _FeatureCard(
                icon: Icons.shopping_basket_rounded,
                color: AppColors.vsGreen,
                title: 'Grocery Shopping',
                subtitle: 'Fresh daily essentials',
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: _FeatureCard(
                icon: Icons.account_balance_wallet_rounded,
                color: AppColors.trustBlue,
                title: 'VS Credit',
                subtitle: 'Flexible payment options',
              ),
            ),
          ],
        ),
        AppSpacing.vGapMd,
        const Row(
          children: [
            Expanded(
              child: _FeatureCard(
                icon: Icons.local_shipping_rounded,
                color: AppColors.vsGreen,
                title: 'Delivery Services',
                subtitle: 'Fast & reliable delivery',
              ),
            ),
            AppSpacing.hGapMd,
            Expanded(
              child: _FeatureCard(
                icon: Icons.sync_rounded,
                color: AppColors.trustBlue,
                title: 'Digital Collections',
                subtitle: 'Seamless repayment',
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
          Text('Get in Touch', style: AppTypography.headlineSmall),
          AppSpacing.vGapMd,
          _ContactRow(
            icon: Icons.language_rounded,
            label: 'Website',
            value: 'www.vsmart.com',
            onTap: () => context.showSnack('Opening website…'),
          ),
          Divider(height: 1, color: vs.border),
          _ContactRow(
            icon: Icons.mail_outline_rounded,
            label: 'Email',
            value: AppConstants.supportEmail,
            onTap: () => context.showSnack('Opening email…'),
          ),
          Divider(height: 1, color: vs.border),
          _ContactRow(
            icon: Icons.call_rounded,
            label: 'Phone',
            value: AppConstants.supportPhone,
            onTap: () => context.showSnack('Calling support…'),
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
                    Text('Office Address', style: AppTypography.titleMedium),
                    AppSpacing.vGapXs,
                    Text(
                      'Knight21 Digi Hub Pvt Ltd\n'
                      '124 Tech Park Avenue, Suite 400\n'
                      'Innovation District\n'
                      'New York, NY 10001',
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
          const _CardHeader(
            icon: Icons.gavel_rounded,
            iconColor: AppColors.trustBlue,
            title: 'Legal & Compliance',
          ),
          AppSpacing.vGapSm,
          _LegalRow(
            icon: Icons.description_outlined,
            label: 'Terms of Service',
            onTap: () => context.showSnack('Opening Terms of Service…'),
          ),
          Divider(height: 1, color: vs.border),
          _LegalRow(
            icon: Icons.shield_outlined,
            label: 'Privacy Policy',
            onTap: () => context.showSnack('Opening Privacy Policy…'),
          ),
          Divider(height: 1, color: vs.border),
          _LegalRow(
            icon: Icons.verified_user_outlined,
            label: 'Licenses & Accreditations',
            onTap: () => showLicensePage(
              context: context,
              applicationName: AppConstants.appName,
              applicationVersion: 'Version 1.0.0',
            ),
          ),
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
          '© 2026 ${AppConstants.appName}. All rights reserved.',
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
