import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/constants/app_constants.dart';
import '../extensions/context_extensions.dart';

/// Opens the device dialer pre-filled with a support number.
///
/// [phone] lets the caller route to the customer's own serving store first,
/// falling back to the platform-wide number; omit it to use the hardcoded
/// [AppConstants.supportPhone] as a last resort. Falls back to a snackbar if
/// no dialer can handle it (e.g. tablets, emulators).
Future<void> callSupport(BuildContext context, {String? phone}) async {
  final number = (phone != null && phone.trim().isNotEmpty) ? phone.trim() : AppConstants.supportPhone;
  final uri = Uri(scheme: 'tel', path: number);
  try {
    final launched =
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      context.showSnack('Could not open the dialer.');
    }
  } catch (_) {
    if (context.mounted) {
      context.showSnack('Could not open the dialer.');
    }
  }
}
