import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// Footer spinner shown while the next page of a listing loads.
class VSPaginationLoader extends StatelessWidget {
  const VSPaginationLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
              strokeWidth: 2.4, color: AppColors.vsGreen),
        ),
      ),
    );
  }
}
