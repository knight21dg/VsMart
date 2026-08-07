import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/settings_provider.dart';

/// A selectable app language, with its native + English display names and code.
class _Language {
  const _Language({
    required this.code,
    required this.native,
    required this.english,
  });

  final String code;
  final String native;
  final String english;
}

/// Language selection screen — a current-language banner, a small preview card,
/// a list of selectable language cards and an "Apply Language" CTA. The choice
/// persists locally via [localeProvider].
class LanguageScreen extends ConsumerStatefulWidget {
  const LanguageScreen({super.key});

  @override
  ConsumerState<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends ConsumerState<LanguageScreen> {
  // Phase 1 languages — English, Telugu, Hindi.
  static const List<_Language> _languages = [
    _Language(code: 'en', native: 'English', english: 'English'),
    _Language(code: 'te', native: 'తెలుగు', english: 'Telugu'),
    _Language(code: 'hi', native: 'हिन्दी', english: 'Hindi'),
  ];

  /// Live preview samples per language (shown for the *selected* language before
  /// it's applied). Numbers/currency stay in ₹ + Latin digits in every language.
  static const Map<String, List<List<String>>> _previews = {
    'en': [
      ['Add to cart', 'Add to cart'],
      ['Credit limit', '₹50,000'],
      ['Outstanding', 'You have ₹25,000 outstanding'],
    ],
    'te': [
      ['కార్ట్‌కు జోడించు', 'కార్ట్‌కు జోడించు'],
      ['క్రెడిట్ పరిమితి', '₹50,000'],
      ['బాకీ', 'మీకు ₹25,000 బాకీ ఉంది'],
    ],
    'hi': [
      ['कार्ट में जोड़ें', 'कार्ट में जोड़ें'],
      ['क्रेडिट सीमा', '₹50,000'],
      ['बकाया', 'आपके पास ₹25,000 बकाया है'],
    ],
  };

  int _selected = 0;
  bool _seeded = false;

  void _seed() {
    final code = ref.read(localeProvider);
    final idx = _languages.indexWhere((l) => l.code == code);
    if (idx >= 0) _selected = idx;
    _seeded = true;
  }

  Future<void> _apply() async {
    await ref.read(localeProvider.notifier).set(_languages[_selected].code);
    if (!mounted) return;
    context.showSnack(context.l10n.languageUpdated);
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (!_seeded) _seed();
    final current = _languages[_selected];

    return Scaffold(
      appBar: VSAppBar(title: context.l10n.languageTitle),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: [
                  _CurrentLanguageBanner(language: current),
                  AppSpacing.vGapLg,
                  _PreviewCard(samples: _previews[current.code] ?? const []),
                  AppSpacing.vGapXl,
                  Text(context.l10n.languageSelect,
                      style: AppTypography.headlineMedium),
                  AppSpacing.vGapMd,
                  for (var i = 0; i < _languages.length; i++) ...[
                    _LanguageTile(
                      language: _languages[i],
                      selected: i == _selected,
                      onTap: () => setState(() => _selected = i),
                    ),
                    if (i != _languages.length - 1) AppSpacing.vGapMd,
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: VSButton(
                label: context.l10n.languageApply,
                onPressed: _apply,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blue-tint banner showing the currently selected language with a globe badge.
class _CurrentLanguageBanner extends StatelessWidget {
  const _CurrentLanguageBanner({required this.language});

  final _Language language;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: vs.trustTint,
        borderRadius: AppRadius.brLg,
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: vs.brand,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.language_rounded,
              color: AppColors.white,
              size: 24,
            ),
          ),
          AppSpacing.hGapMd,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.languageCurrent,
                style: AppTypography.bodySmall
                    .copyWith(color: vs.textSecondary),
              ),
              AppSpacing.vGapXs,
              Text(language.english, style: AppTypography.titleLarge),
            ],
          ),
        ],
      ),
    );
  }
}

/// White card previewing how sample strings render in the *selected* language —
/// including a ₹ amount, to show numbers/currency staying consistent.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.samples});

  final List<List<String>> samples;

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
          Text(context.l10n.languagePreview, style: AppTypography.titleLarge),
          AppSpacing.vGapMd,
          for (var i = 0; i < samples.length; i++) ...[
            _PreviewRow(label: samples[i][0], value: samples[i][1]),
            if (i != samples.length - 1) AppSpacing.vGapSm,
          ],
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: vs.border.withValues(alpha: 0.3),
        borderRadius: AppRadius.brMd,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style:
                  AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
            ),
          ),
          Text(
            value,
            style: AppTypography.labelLarge.copyWith(color: vs.brand),
          ),
        ],
      ),
    );
  }
}

/// A single selectable language card: native name + English subtitle and a
/// radio indicator. Selected cards use the brand tint, a brand border and a
/// filled green check.
class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final _Language language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Material(
      color: AppColors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.brLg,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: selected ? vs.brandTint : context.colors.surface,
            borderRadius: AppRadius.brLg,
            border: Border.all(
              color: selected ? vs.brand : vs.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(language.native, style: AppTypography.titleLarge),
                    AppSpacing.vGapXs,
                    Text(
                      language.english,
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary),
                    ),
                  ],
                ),
              ),
              _RadioDot(selected: selected),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom radio dot — an outlined circle, filled with a brand check when active.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? vs.brand : AppColors.transparent,
        border: Border.all(
          color: selected ? vs.brand : vs.border,
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: AppColors.white)
          : null,
    );
  }
}
