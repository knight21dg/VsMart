import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/support_data.dart';
import '../providers/support_providers.dart';

/// Frequently Asked Questions — a searchable, category-filtered list (loaded from
/// the backend `/support/faqs`) of expandable cards, plus a "Still Need Help?" CTA.
class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});

  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  static const List<String> _categories = [
    'All',
    'Orders',
    'Payments',
    'Credit',
    'Delivery',
    'KYC',
  ];

  final TextEditingController _searchController = TextEditingController();
  int _selectedCategory = 0;
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _categories[_selectedCategory];
    final q = _query.trim().toLowerCase();
    final faqsAsync = ref.watch(faqsProvider);

    List<Faq> filter(List<Faq> all) => all.where((f) {
          final matchesCategory = selected == 'All' || f.category == selected;
          final matchesQuery = q.isEmpty ||
              f.question.toLowerCase().contains(q) ||
              f.answer.toLowerCase().contains(q);
          return matchesCategory && matchesQuery;
        }).toList();

    return Scaffold(
      appBar: const VSAppBar(title: 'FAQ'),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          children: [
            Text(
              'Frequently Asked Questions',
              style: AppTypography.headlineMedium,
            ),
            AppSpacing.vGapLg,
            VSSearchField(
              controller: _searchController,
              hint: 'Search FAQs',
              onChanged: (v) => setState(() => _query = v),
            ),
            AppSpacing.vGapLg,
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => AppSpacing.hGapSm,
                itemBuilder: (context, i) => _CategoryChip(
                  label: _categories[i],
                  selected: i == _selectedCategory,
                  onTap: () => setState(() => _selectedCategory = i),
                ),
              ),
            ),
            AppSpacing.vGapLg,
            ...faqsAsync.when<List<Widget>>(
              loading: () => const [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (_, __) => [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(
                    child: Text(
                      "Couldn't load FAQs. Pull to retry.",
                      style: AppTypography.bodyMedium
                          .copyWith(color: context.vsColors.textSecondary),
                    ),
                  ),
                ),
              ],
              data: (all) {
                final visibleFaqs = filter(all);
                if (visibleFaqs.isEmpty) {
                  return [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                      child: Center(
                        child: Text(
                          'No FAQs match your search.',
                          style: AppTypography.bodyMedium
                              .copyWith(color: context.vsColors.textSecondary),
                        ),
                      ),
                    ),
                  ];
                }
                return [
                  for (var i = 0; i < visibleFaqs.length; i++) ...[
                    if (i != 0) AppSpacing.vGapMd,
                    _FaqCard(faq: visibleFaqs[i], initiallyExpanded: i == 0),
                  ],
                ];
              },
            ),
            AppSpacing.vGapXl,
            const _StillNeedHelp(),
          ],
        ),
      ),
    );
  }
}

/// A pill category filter chip mirroring the selected (green) / unselected
/// (tinted) states in the design.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Material(
      color: selected ? vs.brand : vs.brandTint,
      borderRadius: AppRadius.brPill,
      child: InkWell(
        borderRadius: AppRadius.brPill,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Center(
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: selected ? AppColors.white : vs.brand,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// White card wrapping an [ExpansionTile] for a single Q&A, with dividers
/// suppressed and a "Was this helpful?" feedback row when expanded.
class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.faq, this.initiallyExpanded = false});

  final Faq faq;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: vs.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: AppColors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
          childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          iconColor: vs.textSecondary,
          collapsedIconColor: vs.textSecondary,
          title: Text(faq.question, style: AppTypography.titleLarge),
          children: [
            Text(
              faq.answer,
              style:
                  AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
            AppSpacing.vGapMd,
            Divider(height: 1, color: vs.border),
            AppSpacing.vGapMd,
            Row(
              children: [
                Text(
                  'Was this helpful?',
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary),
                ),
                AppSpacing.hGapMd,
                _FeedbackButton(
                  icon: Icons.thumb_up_alt_outlined,
                  label: 'Yes',
                  onTap: () => context.showSnack('Thanks for your feedback!'),
                ),
                AppSpacing.hGapSm,
                _FeedbackButton(
                  icon: Icons.thumb_down_alt_outlined,
                  label: 'No',
                  onTap: () => context.showSnack('Thanks for your feedback!'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Small tinted pill button used in the "Was this helpful?" feedback row.
class _FeedbackButton extends StatelessWidget {
  const _FeedbackButton({
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
    return Material(
      color: vs.brandTint.withValues(alpha: 0.6),
      borderRadius: AppRadius.brPill,
      child: InkWell(
        borderRadius: AppRadius.brPill,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.xs),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: context.colors.onSurface),
              const SizedBox(width: AppSpacing.xs),
              Text(label, style: AppTypography.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Closing support call-to-action with Contact Support and Raise Ticket
/// actions, matching the tinted panel at the bottom of the design.
class _StillNeedHelp extends StatelessWidget {
  const _StillNeedHelp();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: vs.trustTint.withValues(alpha: 0.5),
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        children: [
          Text('Still Need Help?', style: AppTypography.headlineSmall),
          AppSpacing.vGapXs,
          Text(
            'Our support team is here to assist you.',
            textAlign: TextAlign.center,
            style:
                AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapLg,
          ElevatedButton.icon(
            onPressed: () => context.pushNamed(RouteNames.supportChat),
            icon: const Icon(Icons.headset_mic_outlined, size: 20),
            label: const Text('Contact Support'),
          ),
          AppSpacing.vGapMd,
          OutlinedButton.icon(
            onPressed: () => context.pushNamed(RouteNames.raiseTicket),
            style: OutlinedButton.styleFrom(
              foregroundColor: vs.trust,
              side: BorderSide(color: vs.trust, width: 1.5),
            ),
            icon: const Icon(Icons.confirmation_number_outlined, size: 20),
            label: const Text('Raise Ticket'),
          ),
        ],
      ),
    );
  }
}
