import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../content/data/content_data.dart';
import '../../../content/presentation/providers/content_providers.dart';

/// Privacy Policy — a legal/content screen that renders the VS Mart privacy
/// policy as an intro, a table of contents, and a series of titled sections
/// (each with an icon header and body paragraphs), closing with a Grievance
/// Officer contact card. Matches the client design.
class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Prefer the editable CMS page; fall back to the bundled copy offline.
    final cms = ref.watch(contentPageProvider('privacy')).valueOrNull;
    final useCms = cms != null && cms.body.trim().isNotEmpty;
    return Scaffold(
      appBar: const VSAppBar(title: 'Privacy Policy'),
      body: SafeArea(
        top: false,
        child: useCms
            ? _cmsBody(context, cms)
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: const [
                  _Intro(),
            AppSpacing.vGapLg,
            _TableOfContents(),
            AppSpacing.vGapXl,
            _Section(
              icon: Icons.person_outline_rounded,
              title: 'Data Collection',
              children: [
                _Paragraph('We collect basic information to create and manage '
                    'your account:'),
                _Bullet('Full Name'),
                _Bullet('Phone Number'),
                _Bullet('Delivery Address'),
              ],
            ),
            _Section(
              icon: Icons.badge_outlined,
              title: 'Identity Documents',
              children: [
                _Paragraph('For credit services, we require specific identity '
                    'verification:'),
                _Lead(
                  lead: 'Aadhaar: Stored securely using masked formats',
                  rest: ' in compliance with regulations.',
                ),
                _Lead(
                  lead: 'PAN: Utilized solely for verifying credit eligibility',
                  rest: ' and reporting.',
                ),
              ],
            ),
            _Section(
              icon: Icons.account_balance_outlined,
              title: 'Financial Data',
              children: [
                _Paragraph('To manage your credit profile, we access and '
                    'maintain:'),
                _Bullet('Credit information obtained from authorized credit '
                    'bureaus.'),
                _Bullet('Your payment history and transaction records within '
                    'VS Mart.'),
              ],
            ),
            _Section(
              icon: Icons.share_outlined,
              title: 'Data Sharing',
              children: [
                _Paragraph('Your data is shared strictly on a need-to-know '
                    'basis:'),
                _Lead(
                  lead: 'Logistics Partners: Address and phone number',
                  rest: ' for delivery purposes.',
                ),
                _Lead(
                  lead: 'Lending Partners: Identity and financial data',
                  rest: ' for credit assessment and approval.',
                ),
              ],
            ),
            _Section(
              icon: Icons.shield_outlined,
              title: 'User Rights',
              children: [
                _Paragraph('You retain full control over your personal data:'),
                _Lead(
                  lead: 'Right to Access: Request a copy of the data',
                  rest: ' we hold about you.',
                ),
                _Lead(
                  lead: 'Right to Correct: Update inaccurate or incomplete',
                  rest: ' information.',
                ),
                _Lead(
                  lead: 'Right to Delete: Request deletion of your account',
                  rest: ' and associated data (subject to legal retention '
                      'requirements).',
                ),
              ],
            ),
                  AppSpacing.vGapMd,
                  _GrievanceCard(),
                ],
              ),
      ),
    );
  }

  /// Server-managed copy rendered as readable paragraphs.
  Widget _cmsBody(BuildContext context, ContentPage page) {
    final paras = page.body
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n[ \t]*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xxl),
      children: [
        for (var i = 0; i < paras.length; i++) ...[
          if (i != 0) AppSpacing.vGapLg,
          Text(
            paras[i],
            style: AppTypography.bodyMedium
                .copyWith(height: 1.6, color: context.vsColors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// Intro block: headline + descriptive paragraph.
class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Commitment to Your Privacy',
          style: AppTypography.headlineMedium.copyWith(color: vs.brand),
        ),
        AppSpacing.vGapSm,
        Text(
          'At VS Mart, we are dedicated to protecting your personal and '
          'financial information. This Privacy Policy outlines how we collect, '
          'use, and safeguard your data to provide a seamless grocery shopping '
          'and credit management experience.',
          style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
        ),
      ],
    );
  }
}

/// Table of contents card with quick-jump links rendered in the trust color.
class _TableOfContents extends StatelessWidget {
  const _TableOfContents();

  static const List<String> _items = [
    'Data Collection',
    'Identity Documents',
    'Financial Data',
    'Data Sharing',
    'User Rights',
  ];

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TABLE OF CONTENTS',
            style: AppTypography.labelSmall
                .copyWith(color: vs.textSecondary, letterSpacing: 1),
          ),
          AppSpacing.vGapMd,
          for (var i = 0; i < _items.length; i++) ...[
            if (i != 0) AppSpacing.vGapSm,
            Row(
              children: [
                Icon(Icons.arrow_forward_rounded, size: 16, color: vs.trust),
                AppSpacing.hGapSm,
                Expanded(
                  child: Text(
                    _items[i],
                    style:
                        AppTypography.bodyMedium.copyWith(color: vs.trust),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A titled policy section: green icon + heading, followed by body content.
class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: vs.brand),
              AppSpacing.hGapSm,
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.headlineSmall.copyWith(color: vs.brand),
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          ...children,
          AppSpacing.vGapLg,
          Divider(height: 1, color: vs.border),
        ],
      ),
    );
  }
}

/// A standard body paragraph in secondary text color.
class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style:
          AppTypography.bodyMedium.copyWith(color: context.vsColors.textSecondary),
    );
  }
}

/// An indented bullet-style item (plain body text, slightly inset).
class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, left: AppSpacing.lg),
      child: Text(
        text,
        style: AppTypography.bodyMedium
            .copyWith(color: context.vsColors.textSecondary),
      ),
    );
  }
}

/// An indented item with a bold lead phrase followed by regular continuation.
class _Lead extends StatelessWidget {
  const _Lead({required this.lead, required this.rest});

  final String lead;
  final String rest;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final base = AppTypography.bodyMedium.copyWith(color: vs.textSecondary);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, left: AppSpacing.lg),
      child: Text.rich(
        TextSpan(
          style: base,
          children: [
            TextSpan(
              text: lead,
              style: base.copyWith(
                fontWeight: FontWeight.w700,
                color: context.colors.onSurface,
              ),
            ),
            TextSpan(text: rest),
          ],
        ),
      ),
    );
  }
}

/// Closing contact card for the Grievance Officer.
class _GrievanceCard extends StatelessWidget {
  const _GrievanceCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: vs.brand,
              borderRadius: AppRadius.brPill,
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              size: 24,
              color: AppColors.white,
            ),
          ),
          AppSpacing.vGapMd,
          Text(
            'Grievance Officer',
            style: AppTypography.headlineSmall,
          ),
          AppSpacing.vGapSm,
          Text(
            'For any privacy-related concerns or to exercise your rights, '
            'please contact our dedicated Grievance Officer.',
            style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapMd,
          Text(
            'Email: privacy@vsmart.com',
            style: AppTypography.labelLarge.copyWith(color: vs.brand),
          ),
          AppSpacing.vGapXs,
          Text(
            'Phone: 1-800-VSMART-PRIVACY',
            style: AppTypography.labelLarge.copyWith(color: vs.brand),
          ),
        ],
      ),
    );
  }
}
