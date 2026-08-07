import 'package:flutter/material.dart';

import '../../app/constants/app_constants.dart';
import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Debounced search bar. Calls [onChanged] after the user stops typing for
/// [AppConstants.searchDebounce]. Use [readOnly] + [onTap] to render a tappable
/// search "button" that navigates to a dedicated search screen.
class VSSearchField extends StatefulWidget {
  const VSSearchField({
    super.key,
    this.controller,
    this.hint = 'Search for groceries, brands…',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    this.showFilter = false,
    this.onFilterTap,
  });

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;
  final bool showFilter;
  final VoidCallback? onFilterTap;

  @override
  State<VSSearchField> createState() => _VSSearchFieldState();
}

class _VSSearchFieldState extends State<VSSearchField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  Object? _debounceToken;

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    final token = Object();
    _debounceToken = token;
    Future.delayed(AppConstants.searchDebounce, () {
      if (mounted && identical(_debounceToken, token)) {
        widget.onChanged?.call(value);
      }
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            readOnly: widget.readOnly,
            autofocus: widget.autofocus,
            onTap: widget.onTap,
            onChanged: _onChanged,
            onSubmitted: widget.onSubmitted,
            textInputAction: TextInputAction.search,
            style: AppTypography.bodyMedium
                .copyWith(color: context.textStyles.bodyLarge?.color),
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: Icon(Icons.search_rounded, color: vs.textSecondary),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close_rounded, color: vs.textSecondary),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),
        ),
        if (widget.showFilter) ...[
          AppSpacing.hGapSm,
          Material(
            color: vs.brand,
            borderRadius: AppRadius.brMd,
            child: InkWell(
              borderRadius: AppRadius.brMd,
              onTap: widget.onFilterTap,
              child: const SizedBox(
                height: 52,
                width: 52,
                child: Icon(Icons.tune_rounded, color: AppColors.white),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
