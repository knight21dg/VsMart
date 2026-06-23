import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/extensions/string_extensions.dart';
import 'package:user_app/core/utils/validators.dart';

void main() {
  group('Validators', () {
    test('phone requires 10 digits', () {
      expect(Validators.phone('9876543210'), isNull);
      expect(Validators.phone('123'), isNotNull);
      expect(Validators.phone('abcdefghij'), isNotNull);
    });

    test('otp requires 6 digits', () {
      expect(Validators.otp('123456'), isNull);
      expect(Validators.otp('123'), isNotNull);
    });

    test('email validation', () {
      expect(Validators.email('user@vsmart.app'), isNull);
      expect(Validators.email('not-an-email'), isNotNull);
    });
  });

  group('StringX', () {
    test('initials', () {
      expect('Vijay Sharma'.initials, 'VS');
      expect('vsmart'.initials, 'V');
    });

    test('titleCase', () {
      expect('hello world'.titleCase, 'Hello World');
    });
  });
}
