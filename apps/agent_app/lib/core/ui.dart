import 'package:flutter/material.dart';

import 'api_exception.dart';

/// Agent-app brand + theme — the "Agent App" Figma design system (green primary,
/// bento cards). Field names kept stable so existing screens re-theme for free.
abstract final class AgentColors {
  AgentColors._();
  static const brand = Color(0xFF006B2C);      // primary green (text/accent)
  static const brandBright = Color(0xFF00873A); // buttons / active nav pill
  static const brandDark = Color(0xFF004D20);
  static const blue = Color(0xFF0051D5);        // deliveries accent
  static const blueBright = Color(0xFF316BF3);
  static const pink = Color(0xFFC74668);        // verifications accent
  static const pinkText = Color(0xFFA72D51);
  static const navy = Color(0xFF293040);        // dark route/summary cards
  static const green = Color(0xFF00873A);
  static const amber = Color(0xFFF59E0B);       // tasks accent
  static const danger = Color(0xFFDC2626);
  static const bg = Color(0xFFF9F9FF);          // app background
  static const actionTile = Color(0xFFE1E8FD);  // quick-action tile bg
  static const surface = Colors.white;
  static const textPrimary = Color(0xFF141B2B);
  static const textSecondary = Color(0xFF6B7280);
  static const label = Color(0xFF3E4A3D);       // section-header / caption
  static const border = Color(0xFFBDCABA);
  static const divider = Color(0xFFF3F4F6);
}

ThemeData buildAgentTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AgentColors.brand,
    primary: AgentColors.brand,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AgentColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AgentColors.bg,
      foregroundColor: AgentColors.brand,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AgentColors.brand,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AgentColors.brand,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(50),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AgentColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AgentColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AgentColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AgentColors.brand, width: 1.5),
      ),
    ),
  );
}

/// Centered loading spinner.
class Loading extends StatelessWidget {
  const Loading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// Error state with a retry action.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.onRetry, this.message});
  final VoidCallback onRetry;
  final String? message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 56, color: AgentColors.textSecondary),
            const SizedBox(height: 12),
            Text(message ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AgentColors.textSecondary)),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(minimumSize: const Size(140, 44)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// An iOS-style "slide to confirm" control (the same interaction as iOS's
/// slide-to-answer / slide-to-power-off) — dragging the thumb the full width
/// of the track fires [onConfirmed]; releasing early snaps back. Used for
/// check-in/check-out so a stray tap can never end a shift by accident.
class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.color = AgentColors.brand,
    this.icon = Icons.chevron_right_rounded,
    this.height = 54,
    this.busy = false,
  });

  final String label;
  final VoidCallback onConfirmed;
  final Color color;
  final IconData icon;
  final double height;

  /// While true the thumb shows a spinner and ignores drags — set this from
  /// the in-flight API call the slide triggers.
  final bool busy;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm>
    with SingleTickerProviderStateMixin {
  // Built eagerly in initState — a lazy `late final` initializer here would
  // construct the controller (needing `vsync: this`, i.e. an ancestor
  // lookup) on FIRST ACCESS, which for a slide that never partially released
  // (so _snapBack was never touched) turned out to be dispose() itself: by
  // then the element tree is already deactivating and the ancestor lookup
  // throws ("Looking up a deactivated widget's ancestor is unsafe").
  late final AnimationController _snapBack;

  double _dragFraction = 0; // 0..1 of the track's draggable width
  bool _confirmed = false;

  @override
  void initState() {
    super.initState();
    _snapBack = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() => setState(() => _dragFraction = _snapBack.value));
  }

  @override
  void dispose() {
    _snapBack.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SlideToConfirm old) {
    super.didUpdateWidget(old);
    // The confirmed action's API call just finished (busy: true -> false) —
    // hold the thumb at the end briefly so the confirmation reads clearly,
    // then reset for next time.
    if (_confirmed && old.busy && !widget.busy) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() => _confirmed = false);
        _snapBack.value = 1.0;
        _snapBack.animateTo(0, curve: Curves.easeOut);
      });
    }
  }

  void _onDragUpdate(DragUpdateDetails details, double maxExtent) {
    if (_confirmed || widget.busy || maxExtent <= 0) return;
    final delta = details.delta.dx / maxExtent;
    setState(() => _dragFraction = (_dragFraction + delta).clamp(0.0, 1.0));
  }

  void _onDragEnd(DragEndDetails details) {
    if (_confirmed || widget.busy) return;
    if (_dragFraction > 0.8) {
      setState(() {
        _confirmed = true;
        _dragFraction = 1.0;
      });
      widget.onConfirmed();
    } else {
      _snapBack.value = _dragFraction;
      _snapBack.animateTo(0, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final thumbSize = widget.height - 8;
      final maxExtent = (constraints.maxWidth - thumbSize - 8)
          .clamp(0.0, double.infinity);
      final thumbX = 4 + _dragFraction * maxExtent;
      return Container(
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(widget.height / 2),
          border: Border.all(color: widget.color.withValues(alpha: 0.3)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: (1 - _dragFraction * 1.6).clamp(0.0, 1.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(widget.label,
                      style: TextStyle(
                          color: widget.color,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5)),
                  const SizedBox(width: 4),
                  Icon(Icons.double_arrow_rounded,
                      size: 15, color: widget.color.withValues(alpha: 0.6)),
                ],
              ),
            ),
            Positioned(
              left: thumbX,
              child: GestureDetector(
                onHorizontalDragUpdate: (d) => _onDragUpdate(d, maxExtent),
                onHorizontalDragEnd: _onDragEnd,
                child: Container(
                  width: thumbSize,
                  height: thumbSize,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 4,
                          offset: Offset(0, 2)),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: widget.busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation(Colors.white)),
                        )
                      : Icon(
                          _confirmed ? Icons.check_rounded : widget.icon,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// Empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
  });
  final IconData icon;
  final String title;
  final String? message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AgentColors.textSecondary),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w700)),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AgentColors.textSecondary)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Simple status pill.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// A standard white card.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AgentColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AgentColors.border),
      ),
      child: child,
    );
  }
}

void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AgentColors.danger : Colors.black87,
      behavior: SnackBarBehavior.floating,
    ));
}

/// Surface a caught error as an error toast. For an [ApiException] (any feature
/// subclass) it shows the backend `display` message plus `nextStep`; anything
/// else falls back to a generic line. Use this everywhere a repo call is caught.
void showApiError(BuildContext context, Object error, {String? fallback}) {
  if (error is ApiException) {
    final next = error.nextStep;
    final msg = (next != null && next.isNotEmpty)
        ? '${error.display}\n$next'
        : error.display;
    showToast(context, msg, error: true);
    return;
  }
  showToast(context, fallback ?? 'Something went wrong. Please try again.',
      error: true);
}

/// Indian-grouped integer digits: 1234567 → "12,34,567".
String _indianGroup(String digits) {
  if (digits.length <= 3) return digits;
  final last3 = digits.substring(digits.length - 3);
  var rest = digits.substring(0, digits.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(",")},$last3';
}

/// Strict INR formatter for a money app: **exact paise** (computed via integer
/// cents so float drift can never round money away), Indian digit grouping, and
/// always two decimals (e.g. 1250 → ₹1,250.00, 1250.5 → ₹1,250.50). Use this
/// everywhere an amount is shown — receipts, dues, earnings.
String agentMoney(num v) {
  final neg = v < 0;
  final cents = (v.abs() * 100).round(); // exact; no 0.1+0.2 float error
  final whole = cents ~/ 100;
  final paise = (cents % 100).toString().padLeft(2, '0');
  final s = '₹${_indianGroup(whole.toString())}.$paise';
  return neg ? '-$s' : s;
}

/// Circular tinted leading icon used on list rows (design system).
class LeadingIcon extends StatelessWidget {
  const LeadingIcon({super.key, required this.icon, required this.color, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: size * 0.45),
      );
}

/// Uppercase caption used above every section (design system).
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: AgentColors.label)),
      );
}

/// White stat card with a coloured left border (design system bento tile).
class StatTile extends StatelessWidget {
  const StatTile(
      {super.key,
      required this.label,
      required this.value,
      required this.accent,
      this.sub});
  final String label;
  final String value;
  final Color accent;
  final String? sub;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 4)),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AgentColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AgentColors.textPrimary)),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!,
                style: const TextStyle(
                    fontSize: 11, color: AgentColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}
