import '../../app/constants/app_constants.dart';

/// Reusable form-field validators returning a `String?` error (null = valid),
/// compatible with [FormFieldValidator].
abstract final class Validators {
  Validators._();

  static final RegExp _email =
      RegExp(r'^[\w.+-]+@([\w-]+\.)+[\w-]{2,}$');
  static final RegExp _digits = RegExp(r'^\d+$');
  static final RegExp _name = RegExp(r"^[a-zA-Z][a-zA-Z .'-]*$");
  static final RegExp _aadhaar = RegExp(r'^\d{12}$');
  static final RegExp _pan = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');

  static String? required(String? value, {String field = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Phone number is required';
    if (!_digits.hasMatch(v)) return 'Enter digits only';
    if (v.length != AppConstants.phoneNumberLength) {
      return 'Enter a valid ${AppConstants.phoneNumberLength}-digit number';
    }
    return null;
  }

  static String? otp(String? value) {
    final v = value?.trim() ?? '';
    if (v.length != AppConstants.otpLength || !_digits.hasMatch(v)) {
      return 'Enter the ${AppConstants.otpLength}-digit code';
    }
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    if (!_email.hasMatch(v)) return 'Enter a valid email';
    return null;
  }

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Name is required';
    if (v.length < 2) return 'Name is too short';
    if (!_name.hasMatch(v)) return 'Enter a valid name';
    return null;
  }

  static String? pincode(String? value) {
    final v = value?.trim() ?? '';
    if (!_digits.hasMatch(v) || v.length != 6) return 'Enter a valid 6-digit PIN';
    return null;
  }

  static String? minLength(String? value, int min, {String field = 'Value'}) {
    if ((value?.trim().length ?? 0) < min) {
      return '$field must be at least $min characters';
    }
    return null;
  }

  /// 12-digit Aadhaar number (digits only; spaces are stripped).
  static String? aadhaar(String? value) {
    final v = (value ?? '').replaceAll(' ', '');
    if (v.isEmpty) return 'Aadhaar number is required';
    if (!_aadhaar.hasMatch(v)) return 'Enter a valid 12-digit Aadhaar number';
    return null;
  }

  /// PAN in the format ABCDE1234F (uppercased before checking).
  static String? pan(String? value) {
    final v = (value ?? '').trim().toUpperCase();
    if (v.isEmpty) return 'PAN is required';
    if (!_pan.hasMatch(v)) return 'Enter a valid PAN (e.g. ABCDE1234F)';
    return null;
  }

  /// Date of birth implying an age of at least [minAge] years.
  static String? age(DateTime? dob, {int minAge = 18}) {
    if (dob == null) return 'Date of birth is required';
    final now = DateTime.now();
    var years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years--;
    }
    if (years < minAge) return 'You must be at least $minAge years old';
    return null;
  }

  /// Positive monthly income amount.
  static String? income(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Monthly income is required';
    final amount = num.tryParse(v);
    if (amount == null || amount <= 0) return 'Enter a valid income amount';
    return null;
  }
}
