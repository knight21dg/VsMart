import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

/// Brand splash shown during app bootstrap: a full-WHITE screen with the VS Mart
/// logo centred and a "powered by Knight21 Digi Hub" credit pinned to the bottom.
///
/// The entrance is a single short fade — the splash is only a brand flash now, not
/// a loading gate (location resolves against the last-known verdict, so the app no
/// longer waits here). Routing away is handled by the GoRouter redirect once
/// bootstrap completes.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  )..forward();

  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1.0)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutBack));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            // Centred VS Mart logo.
            Center(
              child: FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: const Image(
                    image: AssetImage('assets/images/vsmartlogo.png'),
                    width: 160,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            // "Powered by Knight21 Digi Hub" credit at the bottom.
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: FadeTransition(
                  opacity: _fade,
                  child: const _PoweredBy(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Powered by" line + the Knight21 Digi Hub logo. Renders a text credit if the
/// logo asset isn't present yet (drop knight21_logo.png into assets/images/).
class _PoweredBy extends StatelessWidget {
  const _PoweredBy();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'powered by',
          style: AppTypography.bodySmall.copyWith(
            color: Colors.black.withValues(alpha: 0.45),
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Image.asset(
          'assets/images/knight21_logo.png',
          height: 40,
          fit: BoxFit.contain,
          // The asset is added separately — until then, show a clean text credit
          // so the build never breaks on a missing file.
          errorBuilder: (_, __, ___) => Text(
            'KNIGHT21 DIGI HUB PVT LTD',
            style: AppTypography.labelMedium.copyWith(
              color: Colors.black.withValues(alpha: 0.7),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
