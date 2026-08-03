import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/env.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';

/// Agent login: phone → OTP. After verifying, confirms the account is an AGENT
/// (via `/agents/me`) before granting access. Dev master OTP: 123456.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;
  String? _verificationId;
  int _resendIn = 0;
  Timer? _resendTimer;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  void _startResendCooldown([int seconds = 30]) {
    _resendTimer?.cancel();
    setState(() => _resendIn = seconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) t.cancel();
    });
  }

  Future<void> _sendOtp() async {
    final phone = _phone.text.trim();
    if (phone.length != 10 || int.tryParse(phone) == null) {
      showToast(context, 'Enter a valid 10-digit mobile number', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final api = ref.read(apiProvider);
      // Gated: the backend only sends an OTP if this phone is a registered agent.
      final res = api.ensureOk(await api
          .post('/agents/auth/send-otp', data: {'phone': phone}, noAuth: true));
      final data = api.obj(res.data);
      _verificationId = data['verification_id']?.toString();
      setState(() => _otpSent = true);
      _startResendCooldown();
    } catch (e) {
      if (mounted) showApiError(context, e, fallback: 'Could not send OTP');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verify() async {
    final code = _otp.text.trim();
    if (code.length < 6 || int.tryParse(code) == null) {
      showToast(context, 'Enter the 6-digit code', error: true);
      return;
    }
    setState(() => _loading = true);
    final api = ref.read(apiProvider);
    try {
      // Gated verify: confirms the OTP AND that the account is a registered
      // agent, then returns the JWT pair. No separate /agents/me check needed.
      final res =
          api.ensureOk(await api.post('/agents/auth/verify-otp', noAuth: true, data: {
        'phone': _phone.text.trim(),
        'otp': code,
        'verification_id': _verificationId,
      }));
      final data = api.obj(res.data);
      final access = data['access_token'] as String?;
      if (access == null) {
        if (mounted) showToast(context, 'Login failed', error: true);
        return;
      }
      await ref.read(tokenStoreProvider).save(
            access: access,
            refresh: data['refresh_token'] as String?,
          );
      ref.read(authStatusProvider.notifier).setAuthenticated();
    } catch (e) {
      if (mounted) showApiError(context, e, fallback: 'Login failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// "9876543210" → "98••••3210" — enough to confirm the number without
  /// showing it in full on screen.
  String _maskedPhone(String phone) {
    if (phone.length != 10) return phone;
    return '${phone.substring(0, 2)}••••${phone.substring(6)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgentColors.bg,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 12),
                    const _LogoMark(),
                    const SizedBox(height: 20),
                    Text(Env.appName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AgentColors.textPrimary)),
                    const SizedBox(height: 6),
                    const Text(
                      'Sign in to manage deliveries, collections\nand verification tasks',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AgentColors.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 32),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AgentColors.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AgentColors.border.withValues(alpha: 0.3)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 20,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _otpSent ? _otpStep() : _phoneStep(),
                    ),
                    const SizedBox(height: 24),
                    const Text('© VS Mart',
                        style: TextStyle(
                            fontSize: 11, color: AgentColors.textSecondary)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _phoneStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Partner sign in',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Enter your registered mobile number',
            style: TextStyle(fontSize: 12.5, color: AgentColors.textSecondary)),
        const SizedBox(height: 16),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.4),
          decoration: const InputDecoration(
            labelText: 'Mobile number',
            hintText: '98765 43210',
            prefixIcon: Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text('🇮🇳  +91',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AgentColors.textPrimary)),
              ),
            ),
            prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _loading ? null : _sendOtp,
          child: _loading ? const _Spin() : const Text('Send OTP'),
        ),
      ],
    );
  }

  Widget _otpStep() {
    final phone = _phone.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Verify your number',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('6-digit code sent to +91 ${_maskedPhone(phone)}',
            style: const TextStyle(
                fontSize: 12.5, color: AgentColors.textSecondary)),
        const SizedBox(height: 18),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          textAlign: TextAlign.center,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
              fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 12),
          decoration: const InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: TextStyle(letterSpacing: 12, color: AgentColors.border),
          ),
        ),
        const SizedBox(height: 4),
        FilledButton(
          onPressed: _loading ? null : _verify,
          child: _loading ? const _Spin() : const Text('Verify & Sign in'),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed:
                  _loading ? null : () => setState(() => _otpSent = false),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Change number'),
            ),
            TextButton.icon(
              onPressed: (_loading || _resendIn > 0) ? null : _sendOtp,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(_resendIn > 0
                  ? 'Resend in ${_resendIn}s'
                  : 'Resend OTP'),
            ),
          ],
        ),
      ],
    );
  }
}

/// The launcher-icon mark, redrawn in-app: a rounded green-gradient square
/// with a bold white "VS" and an amber verified-partner check badge — same
/// identity as the home-screen icon so login reads as the same product.
class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    const size = 84.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AgentColors.brandDark, AgentColors.brandBright],
        ),
        boxShadow: [
          BoxShadow(
            color: AgentColors.brand.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          const Center(
            child: Text('VS',
                style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              padding: const EdgeInsets.all(3),
              child: const DecoratedBox(
                decoration:
                    BoxDecoration(color: AgentColors.amber, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Spin extends StatelessWidget {
  const _Spin();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
            strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
      );
}
