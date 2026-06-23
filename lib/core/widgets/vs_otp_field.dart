import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/constants/app_constants.dart';
import '../../app/theme/app_theme.dart';
import '../extensions/context_extensions.dart';

/// Segmented OTP input. Emits [onCompleted] when all boxes are filled and
/// streams the running value via [onChanged].
class VSOTPField extends StatefulWidget {
  const VSOTPField({
    super.key,
    this.length = AppConstants.otpLength,
    this.onCompleted,
    this.onChanged,
    this.autofocus = true,
    this.hasError = false,
  });

  final int length;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final bool hasError;

  @override
  State<VSOTPField> createState() => _VSOTPFieldState();
}

class _VSOTPFieldState extends State<VSOTPField> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _nodes;

  @override
  void initState() {
    super.initState();
    _controllers =
        List.generate(widget.length, (_) => TextEditingController());
    _nodes = List.generate(widget.length, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  String get _value => _controllers.map((c) => c.text).join();

  void _onChanged(int index, String value) {
    if (value.isNotEmpty && index < widget.length - 1) {
      _nodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _nodes[index - 1].requestFocus();
    }
    widget.onChanged?.call(_value);
    if (_value.length == widget.length) {
      _nodes[index].unfocus();
      widget.onCompleted?.call(_value);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(widget.length, (i) {
        final filled = _controllers[i].text.isNotEmpty;
        final borderColor = widget.hasError
            ? vs.danger
            : (_nodes[i].hasFocus || filled ? vs.brand : vs.border);
        return SizedBox(
          width: 48,
          height: 56,
          child: TextField(
            controller: _controllers[i],
            focusNode: _nodes[i],
            autofocus: widget.autofocus && i == 0,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            style: AppTypography.headlineSmall
                .copyWith(color: context.textStyles.bodyLarge?.color),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              contentPadding: EdgeInsets.zero,
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.brMd,
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.brMd,
                borderSide: BorderSide(color: borderColor, width: 1.5),
              ),
            ),
            onChanged: (v) => _onChanged(i, v),
          ),
        );
      }),
    );
  }
}
