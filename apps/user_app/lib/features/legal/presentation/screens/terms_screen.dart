import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../content/data/content_data.dart';
import '../../../content/presentation/providers/content_providers.dart';

/// Terms & Conditions — a legal/content screen rendering the VS Mart terms as
/// numbered, titled sections with body paragraphs. Matches the client design:
/// a "Last updated" line, numbered section cards (one with a highlighted
/// "Important" note for the credit policy) and a pinned "Accept & Continue"
/// action at the bottom.
class TermsScreen extends ConsumerWidget {
  const TermsScreen({super.key});

  static const List<_TermsSection> _sections = [
    _TermsSection(
      title: 'General Terms',
      body:
          'Welcome to VS Mart. By accessing or using our grocery commerce and '
          'financial credit services, you agree to be bound by these Terms & '
          'Conditions. These terms govern your use of the VS Mart app, website '
          'and associated services.\n\nWe reserve the right to update or modify '
          'these terms at any time. Your continued use of the platform '
          'following any changes indicates your acceptance of the new terms. If '
          'you do not agree to these terms, please do not use our services.',
    ),
    _TermsSection(
      title: 'Grocery Orders',
      body:
          'All product representations, including prices and availability, are '
          'subject to change without notice. While we strive for accuracy, VS '
          'Mart does not warrant that product descriptions or prices are error '
          'free.\n\nUpon placing an order, you will receive a confirmation. '
          'This confirmation does not guarantee acceptance of the order. We '
          'reserve the right to cancel or limit quantities of any order due to '
          'inventory or pricing constraints.',
    ),
    _TermsSection(
      title: 'Delivery Policy',
      body:
          'VS Mart aims to deliver orders within the estimated timeframe '
          'provided at checkout. However, delivery times are estimates and not '
          'guaranteed. Delays may occur due to weather, traffic or other '
          'unforeseen circumstances.\n\nDelivery fees are calculated based on '
          'your location and selected delivery window. It is your '
          'responsibility to ensure someone is available to receive the '
          'delivery. Perishable goods left unattended are at the customer’s '
          'risk.',
    ),
    _TermsSection(
      title: 'Credit Usage Policy',
      body:
          'Eligibility for VS Mart Credit is determined at our sole discretion. '
          'Users granted a credit limit must manage their usage responsibly. '
          'The credit line is intended for purchases within the VS Mart '
          'ecosystem.\n\nInterest rates, if applicable, and repayment cycles '
          'will be clearly communicated upon credit approval. Late or missed '
          'repayments may result in late fees, suspension of credit privileges '
          'and a negative impact on your internal VS Mart credit score.',
      note:
          'Credit services are subject to approval based on our proprietary '
          'risk-assessment algorithms.',
    ),
    _TermsSection(
      title: 'Payment Terms',
      body:
          'We accept major credit cards, debit cards and VS Mart Credit. By '
          'providing a payment method, you represent that you are authorized to '
          'use it and authorize us to charge it for your orders.\n\nBilling '
          'cycles for credit usage are typically monthly. Statements will be '
          'generated and available within your account profile. All '
          'transactions are processed using industry-standard secure '
          'encryption protocols.',
    ),
    _TermsSection(
      title: 'Refund Policy',
      body:
          'If you are dissatisfied with a product, you may request a refund '
          'within 48 hours of delivery. Refunds are granted at our discretion, '
          'typically for damaged, spoiled or incorrect items.\n\nApproved '
          'refunds will be processed back to the original payment method or '
          'issued as VS Mart Credit within 3–5 business days.',
    ),
    _TermsSection(
      title: 'User Responsibilities',
      body:
          'You are responsible for maintaining the confidentiality of your '
          'account credentials. You agree to notify us immediately of any '
          'unauthorized use of your account.\n\nProhibited activities include, '
          'but are not limited to, fraud, exploiting platform bugs, attempting '
          'to access restricted areas, or harassing our delivery personnel or '
          'support staff. Violation may result in immediate account '
          'termination.',
    ),
    _TermsSection(
      title: 'Limitation of Liability',
      body:
          'To the maximum extent permitted by law, VS Mart shall not be liable '
          'for any indirect, incidental or consequential damages arising from '
          'your use of the platform. Our total liability for any claim is '
          'limited to the amount paid by you for the relevant order.',
    ),
    _TermsSection(
      title: 'Termination',
      body:
          'We may suspend or terminate your access to VS Mart at any time, with '
          'or without cause, including for breach of these terms. Upon '
          'termination, any outstanding credit balance becomes immediately due '
          'and payable.',
    ),
    _TermsSection(
      title: 'Contact Us',
      body:
          'If you have questions about these Terms & Conditions, please reach '
          'out to our support team at support@vsmart.com or through the Help '
          'Center within the app. We are here to help.',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Prefer the editable CMS page; fall back to the bundled copy offline.
    final cms = ref.watch(contentPageProvider('terms')).valueOrNull;
    final useCms = cms != null && cms.body.trim().isNotEmpty;

    return Scaffold(
      appBar: const VSAppBar(title: 'Terms & Conditions'),
      body: SafeArea(
        top: false,
        child: useCms ? _cmsBody(context, cms) : _staticBody(context),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: ElevatedButton(
          onPressed: () => context.showSnack('Terms accepted. Thank you!'),
          child: const Text('Accept & Continue'),
        ),
      ),
    );
  }

  /// Bundled copy used offline / before the CMS page loads.
  Widget _staticBody(BuildContext context) {
    final vs = context.vsColors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
      children: [
        Text(
          'Last updated: October 26, 2024',
          style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
        ),
        AppSpacing.vGapMd,
        for (var i = 0; i < _sections.length; i++) ...[
          _SectionCard(index: i + 1, section: _sections[i]),
          if (i != _sections.length - 1) AppSpacing.vGapMd,
        ],
      ],
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
          AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
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

/// A single numbered terms section rendered inside a bordered surface card,
/// with an optional highlighted "Important" note.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.index, required this.section});

  final int index;
  final _TermsSection section;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
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
          Text(
            '$index. ${section.title}',
            style: AppTypography.titleLarge,
          ),
          AppSpacing.vGapSm,
          Text(
            section.body,
            style: AppTypography.bodyMedium.copyWith(height: 1.6),
          ),
          if (section.note != null) ...[
            AppSpacing.vGapMd,
            _ImportantNote(text: section.note!),
          ],
        ],
      ),
    );
  }
}

/// Highlighted "Important" callout used inside a section (e.g. credit policy).
class _ImportantNote extends StatelessWidget {
  const _ImportantNote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brMd,
        border: Border.all(color: vs.trust.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: vs.trust),
          AppSpacing.hGapSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Important',
                  style: AppTypography.labelMedium.copyWith(color: vs.trust),
                ),
                AppSpacing.vGapXs,
                Text(
                  text,
                  style: AppTypography.bodySmall.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Immutable data holder for a terms section.
@immutable
class _TermsSection {
  const _TermsSection({
    required this.title,
    required this.body,
    this.note,
  });

  final String title;
  final String body;
  final String? note;
}
