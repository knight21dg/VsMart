import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/widgets/widgets.dart';
import '../../domain/entities/product_filter.dart';
import 'vs_filter_chip.dart';

/// Shows the filter sheet seeded with [current] and the available [brands];
/// returns the updated [ProductFilter] (or null if dismissed).
Future<ProductFilter?> showVSFilterSheet(
  BuildContext context, {
  required ProductFilter current,
  required List<String> brands,
}) {
  return showModalBottomSheet<ProductFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _FilterSheet(current: current, brands: brands),
  );
}

/// (min, max) price buckets offered in the sheet.
const _priceBuckets = <({String label, double? min, double? max})>[
  (label: 'Under ₹50', min: null, max: 50),
  (label: '₹50 – ₹100', min: 50, max: 100),
  (label: '₹100 – ₹250', min: 100, max: 250),
  (label: '₹250+', min: 250, max: null),
];

const _discountOptions = [10.0, 20.0, 30.0, 50.0];

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.current, required this.brands});

  final ProductFilter current;
  final List<String> brands;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late ProductFilter _filter = widget.current;

  bool _isPriceBucket(({String label, double? min, double? max}) b) =>
      _filter.minPrice == b.min && _filter.maxPrice == b.max;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: AppSpacing.screen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Filters', style: AppTypography.headlineSmall),
                  TextButton(
                    onPressed: () =>
                        setState(() => _filter = ProductFilter.empty),
                    child: const Text('Clear all'),
                  ),
                ],
              ),
              AppSpacing.vGapMd,
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _filter.inStockOnly,
                onChanged: (v) =>
                    setState(() => _filter = _filter.copyWith(inStockOnly: v)),
                title: Text('In stock only', style: AppTypography.bodyLarge),
                activeColor: vs.brand,
              ),
              const Divider(),
              AppSpacing.vGapSm,
              Text('Price', style: AppTypography.titleMedium),
              AppSpacing.vGapSm,
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final b in _priceBuckets)
                    VSFilterChip(
                      label: b.label,
                      selected: _isPriceBucket(b),
                      onTap: () => setState(() {
                        _filter = _isPriceBucket(b)
                            ? _filter.copyWith(
                                clearMinPrice: true, clearMaxPrice: true)
                            : _filter.copyWith(
                                clearMinPrice: b.min == null,
                                clearMaxPrice: b.max == null,
                                minPrice: b.min,
                                maxPrice: b.max,
                              );
                      }),
                    ),
                ],
              ),
              AppSpacing.vGapLg,
              Text('Minimum Discount', style: AppTypography.titleMedium),
              AppSpacing.vGapSm,
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final d in _discountOptions)
                    VSFilterChip(
                      label: '${d.round()}%+',
                      selected: _filter.minimumDiscount == d,
                      onTap: () => setState(() {
                        _filter = _filter.minimumDiscount == d
                            ? _filter.copyWith(clearDiscount: true)
                            : _filter.copyWith(minimumDiscount: d);
                      }),
                    ),
                ],
              ),
              if (widget.brands.isNotEmpty) ...[
                AppSpacing.vGapLg,
                Text('Brand', style: AppTypography.titleMedium),
                AppSpacing.vGapSm,
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final brand in widget.brands)
                      VSFilterChip(
                        label: brand,
                        selected: _filter.brands.contains(brand),
                        onTap: () => setState(() {
                          final next = _filter.brands.contains(brand)
                              ? _filter.brands.where((b) => b != brand).toList()
                              : [..._filter.brands, brand];
                          _filter = _filter.copyWith(brands: next);
                        }),
                      ),
                  ],
                ),
              ],
              AppSpacing.vGapXl,
              VSButton(
                label: 'Apply Filters',
                onPressed: () => Navigator.of(context).pop(_filter),
              ),
              AppSpacing.vGapSm,
            ],
          ),
        ),
      ),
    );
  }
}
