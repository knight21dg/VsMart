import 'package:flutter/material.dart';

import 'ui.dart';

/// One selectable reason option, carrying a typed [value] (usually an enum).
class ReasonOption<T> {
  const ReasonOption(this.value, this.label);
  final T value;
  final String label;
}

/// A full-page reason picker used for the "report failed / reject" steps of the
/// delivery, collection and verification flows (design: Reason screens). Pops
/// with `({T value, String note})` on submit, or `null` if cancelled.
class ReasonScreen<T> extends StatefulWidget {
  const ReasonScreen({
    super.key,
    required this.title,
    required this.options,
    required this.submitLabel,
    this.prompt,
    this.danger = false,
  });

  final String title;
  final String? prompt;
  final List<ReasonOption<T>> options;
  final String submitLabel;
  final bool danger;

  @override
  State<ReasonScreen<T>> createState() => _ReasonScreenState<T>();
}

class _ReasonScreenState<T> extends State<ReasonScreen<T>> {
  T? _selected;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selected == null) return;
    Navigator.of(context).pop((value: _selected as T, note: _note.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger ? AgentColors.danger : AgentColors.brand;
    return Scaffold(
      backgroundColor: AgentColors.bg,
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionHeader(widget.prompt ?? 'Select a reason'),
                for (final opt in widget.options) ...[
                  _OptionCard(
                    label: opt.label,
                    selected: _selected == opt.value,
                    accent: accent,
                    onTap: () => setState(() => _selected = opt.value),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 8),
                TextField(
                  controller: _note,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: _selected == null ? null : _submit,
                child: Text(widget.submitLabel),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : AgentColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? accent : AgentColors.border,
              width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? accent : AgentColors.textSecondary,
                size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: AgentColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
