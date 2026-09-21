import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Immutable snapshot of every filter a catalog screen (customer,
/// merchant, or admin) can apply. Deliberately shared across all three
/// screens rather than each keeping its own set of loose fields, so
/// "customers can filter by X" and "merchants/admins can filter by the
/// same X" can't quietly drift apart the way three copy-pasted filter
/// rows eventually would.
///
/// [priceRange] is null when price isn't constrained at all (the default,
/// and also what "reset" returns to) — this avoids needing a separate
/// enabled/disabled flag alongside a range that's always technically set
/// to *something*.
@immutable
class CatalogFilters {
  final String style;
  final String gender;
  final bool arOnly;
  final String brand;
  final RangeValues? priceRange;
  // 'All' | 'Active' | 'Draft' — only meaningful on merchant/admin screens,
  // where showListingStatusFilter is true. Customers only ever see listed
  // watches in the first place, so this field is simply unused there.
  final String listingStatus;

  const CatalogFilters({
    this.style = 'All',
    this.gender = 'All',
    this.arOnly = false,
    this.brand = 'All',
    this.priceRange,
    this.listingStatus = 'All',
  });

  CatalogFilters copyWith({
    String? style,
    String? gender,
    bool? arOnly,
    String? brand,
    RangeValues? priceRange,
    bool clearPriceRange = false,
    String? listingStatus,
  }) {
    return CatalogFilters(
      style: style ?? this.style,
      gender: gender ?? this.gender,
      arOnly: arOnly ?? this.arOnly,
      brand: brand ?? this.brand,
      priceRange: clearPriceRange ? null : (priceRange ?? this.priceRange),
      listingStatus: listingStatus ?? this.listingStatus,
    );
  }

  /// How many filters are actually narrowing the catalog right now — used
  /// for the badge on the filter icon, so a customer/merchant/admin can
  /// tell at a glance whether they're looking at the full catalog.
  int get activeCount {
    var count = 0;
    if (style != 'All') count++;
    if (gender != 'All') count++;
    if (arOnly) count++;
    if (brand != 'All') count++;
    if (priceRange != null) count++;
    if (listingStatus != 'All') count++;
    return count;
  }

  bool get isDefault => activeCount == 0;
}

/// Opens the shared filter bottom sheet and returns the filters the user
/// applied, or null if they dismissed it without hitting Apply (in which
/// case the caller should leave its current filters untouched).
///
/// [priceFloor]/[priceCeiling] should be computed from the catalog's
/// actual current prices (not a guessed fixed range) so the slider
/// always reflects what's really in the catalog — see each screen's
/// docs-derived min/max at the call site.
Future<CatalogFilters?> showCatalogFilterSheet(
  BuildContext context, {
  required CatalogFilters initial,
  required List<String> styleOptions,
  required List<String> brandOptions,
  required double priceFloor,
  required double priceCeiling,
  bool showGenderFilter = true,
  bool showArFilter = true,
  bool showListingStatusFilter = false,
}) {
  return showModalBottomSheet<CatalogFilters>(
    context: context,
    backgroundColor: AppTheme.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _FilterSheetBody(
      initial: initial,
      styleOptions: styleOptions,
      brandOptions: brandOptions,
      priceFloor: priceFloor,
      priceCeiling: priceCeiling,
      showGenderFilter: showGenderFilter,
      showArFilter: showArFilter,
      showListingStatusFilter: showListingStatusFilter,
    ),
  );
}

class _FilterSheetBody extends StatefulWidget {
  final CatalogFilters initial;
  final List<String> styleOptions;
  final List<String> brandOptions;
  final double priceFloor;
  final double priceCeiling;
  final bool showGenderFilter;
  final bool showArFilter;
  final bool showListingStatusFilter;

  const _FilterSheetBody({
    required this.initial,
    required this.styleOptions,
    required this.brandOptions,
    required this.priceFloor,
    required this.priceCeiling,
    required this.showGenderFilter,
    required this.showArFilter,
    required this.showListingStatusFilter,
  });

  @override
  State<_FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends State<_FilterSheetBody> {
  late CatalogFilters _draft;
  late RangeValues _priceDraft;

  static const List<String> _genderOptions = [
    'All',
    "Men's",
    "Women's",
    'Unisex',
  ];
  static const List<String> _listingStatusOptions = ['All', 'Active', 'Draft'];

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _priceDraft = widget.initial.priceRange ??
        RangeValues(widget.priceFloor, widget.priceCeiling);
  }

  bool get _priceIsFullRange =>
      _priceDraft.start <= widget.priceFloor &&
      _priceDraft.end >= widget.priceCeiling;

  void _reset() {
    setState(() {
      _draft = const CatalogFilters();
      _priceDraft = RangeValues(widget.priceFloor, widget.priceCeiling);
    });
  }

  void _apply() {
    final result = _draft.copyWith(
      priceRange: _priceIsFullRange ? null : _priceDraft,
      clearPriceRange: _priceIsFullRange,
    );
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: _draft.isDefault && _priceIsFullRange
                        ? null
                        : _reset,
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _sectionLabel('STYLE'),
              _chipWrap(
                options: ['All', ...widget.styleOptions],
                selected: _draft.style,
                onSelected: (value) =>
                    setState(() => _draft = _draft.copyWith(style: value)),
              ),
              if (widget.brandOptions.isNotEmpty) ...[
                const SizedBox(height: 16),
                _sectionLabel('BRAND'),
                _chipWrap(
                  options: ['All', ...widget.brandOptions],
                  selected: _draft.brand,
                  onSelected: (value) =>
                      setState(() => _draft = _draft.copyWith(brand: value)),
                ),
              ],
              if (widget.showGenderFilter) ...[
                const SizedBox(height: 16),
                _sectionLabel('GENDER'),
                _chipWrap(
                  options: _genderOptions,
                  selected: _draft.gender,
                  onSelected: (value) =>
                      setState(() => _draft = _draft.copyWith(gender: value)),
                ),
              ],
              if (widget.showListingStatusFilter) ...[
                const SizedBox(height: 16),
                _sectionLabel('LISTING STATUS'),
                _chipWrap(
                  options: _listingStatusOptions,
                  selected: _draft.listingStatus,
                  onSelected: (value) => setState(
                      () => _draft = _draft.copyWith(listingStatus: value)),
                ),
              ],
              if (widget.showArFilter) ...[
                const SizedBox(height: 16),
                _sectionLabel('AR TRY-ON'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _draft.arOnly,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(arOnly: value)),
                  activeThumbColor: AppTheme.gold,
                  title: const Text(
                    'Only show watches with AR try-on',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _sectionLabel('PRICE RANGE (PHP)'),
              if (widget.priceCeiling > widget.priceFloor) ...[
                RangeSlider(
                  values: _priceDraft,
                  min: widget.priceFloor,
                  max: widget.priceCeiling,
                  activeColor: AppTheme.gold,
                  inactiveColor: AppTheme.surface,
                  labels: RangeLabels(
                    _priceDraft.start.round().toString(),
                    _priceDraft.end.round().toString(),
                  ),
                  onChanged: (values) => setState(() => _priceDraft = values),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'PHP ${_priceDraft.start.round()}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                      Text(
                        'PHP ${_priceDraft.end.round()}',
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ] else
                // Every watch shares the same price (or there's only one) —
                // a slider with equal min/max is meaningless/disabled-looking
                // in Flutter, so just say so instead of showing a broken
                // control.
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Not enough price variation in the catalog to filter by range yet.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _apply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Apply Filters',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _chipWrap({
    required List<String> options,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selected == option;
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          // The gold border + gold text already mark the selected chip —
          // the default checkmark on top of that was the main source of
          // clutter in the old inline filter rows, so it's off everywhere
          // in this sheet.
          showCheckmark: false,
          onSelected: (_) => onSelected(option),
          backgroundColor: AppTheme.background,
          selectedColor: AppTheme.gold.withValues(alpha: 0.2),
          labelStyle: TextStyle(
            color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
            fontSize: 13,
          ),
          side: BorderSide(
            color: isSelected ? AppTheme.gold : Colors.transparent,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        );
      }).toList(),
    );
  }
}

/// App-bar filter icon with a small badge showing how many filters are
/// active — the single indicator that replaces the old always-visible
/// chip rows. Identical on all three catalog screens by design.
class CatalogFilterButton extends StatelessWidget {
  final int activeCount;
  final VoidCallback onPressed;

  const CatalogFilterButton({
    super.key,
    required this.activeCount,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Filters',
      onPressed: onPressed,
      icon: Badge(
        label: Text('$activeCount'),
        isLabelVisible: activeCount > 0,
        backgroundColor: AppTheme.gold,
        textColor: Colors.black,
        child: const Icon(Icons.filter_list),
      ),
    );
  }
}