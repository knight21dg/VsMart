import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/utils/app_logger.dart';
import '../../../shared/providers/core_providers.dart';

/// Verdict from the backend `/geo/validate-address` proxy (Google Address
/// Validation). `source == 'google'` means Google actually answered; anything
/// else (no_key / error / bad_args) means we couldn't validate and the caller
/// should proceed without blocking.
class AddressCheck {
  const AddressCheck({
    this.complete,
    this.formatted = '',
    this.pincode = '',
    this.missing = const [],
    this.source = '',
  });

  final bool? complete;
  final String formatted;
  final String pincode;
  final List<String> missing;
  final String source;

  bool get validated => source == 'google';

  /// Google confirmed the address is missing pieces / undeliverable.
  bool get isIncomplete => validated && complete == false;
}

class AddressValidationService {
  const AddressValidationService(this._client);

  final ApiClient _client;

  Future<AddressCheck> validate({
    required List<String> addressLines,
    required String pincode,
  }) async {
    try {
      final res = await _client.post<dynamic>(
        '/geo/validate-address',
        data: {'addressLines': addressLines, 'pincode': pincode},
      );
      final raw = res.data;
      final map = raw is Map && raw['data'] is Map ? raw['data'] : raw;
      if (map is! Map) return const AddressCheck();
      return AddressCheck(
        complete: map['complete'] as bool?,
        formatted: (map['formatted'] ?? '').toString(),
        pincode: (map['pincode'] ?? '').toString(),
        missing: ((map['missing'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        source: (map['source'] ?? '').toString(),
      );
    } catch (e) {
      AppLogger.w('geo/validate-address failed: $e');
      return const AddressCheck();
    }
  }
}

final addressValidationServiceProvider = Provider<AddressValidationService>(
  (ref) => AddressValidationService(ref.watch(apiClientProvider)),
);
