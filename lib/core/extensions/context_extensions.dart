import 'package:flutter/material.dart';

import '../../app/theme/theme_extensions.dart';

/// Convenience accessors on [BuildContext] for theme, media query, and common
/// UI actions used throughout VS Mart.
extension ContextX on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get textStyles => Theme.of(this).textTheme;

  /// VS Mart custom semantic colors.
  VSColors get vsColors => Theme.of(this).extension<VSColors>()!;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  MediaQueryData get mediaQuery => MediaQuery.of(this);
  Size get screenSize => MediaQuery.sizeOf(this);
  double get screenWidth => MediaQuery.sizeOf(this).width;
  double get screenHeight => MediaQuery.sizeOf(this).height;
  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);
  EdgeInsets get viewInsets => MediaQuery.viewInsetsOf(this);
  bool get isKeyboardOpen => MediaQuery.viewInsetsOf(this).bottom > 0;

  void hideKeyboard() => FocusScope.of(this).unfocus();

  ScaffoldMessengerState get messenger => ScaffoldMessenger.of(this);

  void showSnack(String message, {bool isError = false}) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? vsColors.danger : null,
        ),
      );
  }
}
