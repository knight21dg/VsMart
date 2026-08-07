import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/app_error_presenter.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../domain/entities/cibil_report.dart';
import '../providers/credit_providers.dart';

/// Self-service CIBIL / credit-score check. The customer consents, we fetch their
/// bureau score by mobile number, store it, and render it as a 300–900 gauge.
class CibilScoreScreen extends ConsumerStatefulWidget {
  const CibilScoreScreen({super.key});

  @override
  ConsumerState<CibilScoreScreen> createState() => _CibilScoreScreenState();
}

class _CibilScoreScreenState extends ConsumerState<CibilScoreScreen> {
  late final TextEditingController _mobile;
  bool _consent = false;

  @override
  void initState() {
    super.initState();
    final phone = ref.read(currentUserProvider)?.phone ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    _mobile = TextEditingController(
      text: digits.length >= 10 ? digits.substring(digits.length - 10) : digits,
    );
  }

  @override
  void dispose() {
    _mobile.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    FocusScope.of(context).unfocus();
    final mobile = _mobile.text.trim();
    if (mobile.length != 10) {
      context.showSnack('Enter a valid 10-digit mobile number.');
      return;
    }
    if (!_consent) {
      context.showSnack('Please give consent to check your score.');
      return;
    }
    await ref
        .read(cibilCheckControllerProvider.notifier)
        .check(mobile: mobile, consent: _consent);
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final latest = ref.watch(cibilLatestProvider);
    final check = ref.watch(cibilCheckControllerProvider);

    // Surface a check failure (consent / provider / no-record) actionably.
    ref.listen<AsyncValue<CibilReport?>>(cibilCheckControllerProvider, (_, next) {
      if (next is AsyncError && next.error is Failure) {
        presentFailure(context, ref, next.error as Failure, onRetry: _check);
      }
    });

    final busy = check.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: Text('Credit Score',
            style: AppTypography.headlineSmall.copyWith(color: vs.brand)),
      ),
      body: latest.when(
        loading: () => const VSLoadingView(),
        error: (e, _) => VSErrorView(
          failure: e is Failure ? e : null,
          onRetry: () => ref.invalidate(cibilLatestProvider),
        ),
        data: (report) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(cibilLatestProvider);
            await ref.read(cibilLatestProvider.future);
          },
          child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: AppSpacing.screen,
          children: [
            if (report != null && report.hasScore) ...[
              _ScoreResult(report: report),
              AppSpacing.vGapLg,
              VSButton(
                label: 'Refresh Score',
                variant: VSButtonVariant.secondary,
                icon: Icons.refresh_rounded,
                isLoading: busy,
                onPressed: busy ? null : _check,
              ),
            ] else ...[
              _Intro(vs: vs),
              AppSpacing.vGapLg,
              VSTextField(
                controller: _mobile,
                label: 'Mobile Number',
                hint: '10-digit mobile number',
                keyboardType: TextInputType.number,
                maxLength: 10,
                prefixIcon: Icons.phone_android_rounded,
              ),
              AppSpacing.vGapSm,
              _ConsentTile(
                value: _consent,
                onChanged: (v) => setState(() => _consent = v),
              ),
              AppSpacing.vGapLg,
              VSButton(
                label: 'Check My Score',
                icon: Icons.speed_rounded,
                isLoading: busy,
                onPressed: busy ? null : _check,
              ),
              AppSpacing.vGapMd,
              Text(
                'Checking your score has no impact on it. Powered by a licensed '
                'credit bureau; requires your consent under the DPDP Act.',
                style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.vs});

  final VSColors vs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.verified_user_rounded, color: vs.brand, size: 40),
        AppSpacing.vGapSm,
        Text('Check your CIBIL credit score',
            style: AppTypography.titleLarge),
        AppSpacing.vGapXs,
        Text(
          'See the score linked to your mobile number, free and instant.',
          style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary),
        ),
      ],
    );
  }
}

class _ConsentTile extends StatelessWidget {
  const _ConsentTile({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: vs.brand,
              visualDensity: VisualDensity.compact,
            ),
            AppSpacing.hGapSm,
            Expanded(
              child: Text(
                'I authorise VS Mart to fetch my credit score from the bureau '
                'for this purpose.',
                style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The result panel: a 300–900 gauge, the band, and the bureau identity.
class _ScoreResult extends StatelessWidget {
  const _ScoreResult({required this.report});

  final CibilReport report;

  Color _color(VSColors vs) {
    final s = report.score;
    if (s >= 750) return vs.success;
    if (s >= 650) return vs.warning;
    return vs.danger;
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final color = _color(vs);
    return Column(
      children: [
        _Gauge(fraction: report.gaugeFraction, color: color, score: report.score),
        AppSpacing.vGapXs,
        Text(report.band.toUpperCase(),
            style: AppTypography.labelLarge.copyWith(
                color: color, letterSpacing: 1.2)),
        Text('Range 300 – 900',
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary)),
        AppSpacing.vGapLg,
        Container(
          padding: AppSpacing.card,
          decoration: BoxDecoration(
            color: vs.brandTint,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              if (report.nameOnBureau.isNotEmpty)
                Text(report.nameOnBureau,
                    style: AppTypography.titleMedium,
                    textAlign: TextAlign.center),
              if (report.pan.isNotEmpty) ...[
                AppSpacing.vGapXs,
                Text('PAN ${report.pan}',
                    style: AppTypography.bodyMedium.copyWith(
                        color: vs.textSecondary, letterSpacing: 1.5)),
              ],
            ],
          ),
        ),
        AppSpacing.vGapMd,
        _Row(k: 'Mobile', v: report.mobile),
        if (report.checkedAt != null)
          _Row(
            k: 'Checked on',
            v: DateFormat('d MMM yyyy, h:mm a').format(report.checkedAt!),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.k, required this.v});

  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: AppTypography.bodyMedium.copyWith(color: vs.textSecondary)),
          Text(v, style: AppTypography.bodyMedium),
        ],
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({required this.fraction, required this.color, required this.score});

  final double fraction;
  final Color color;
  final int score;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return SizedBox(
      height: 150,
      child: CustomPaint(
        painter: _GaugePainter(
          fraction: fraction, color: color, track: vs.border),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Text('$score',
                style: AppTypography.displayMedium.copyWith(color: color)),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.fraction,
    required this.color,
    required this.track,
  });

  final double fraction;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      (size.width - stroke), // full circle box; we draw only the top half
    );
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    final value = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;

    // Semicircle: 180° (π) sweep starting from the left (π).
    canvas.drawArc(rect, math.pi, math.pi, false, base);
    canvas.drawArc(rect, math.pi, math.pi * fraction.clamp(0.0, 1.0), false, value);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.color != color || old.track != track;
}
