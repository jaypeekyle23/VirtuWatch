import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import 'luxe.dart';

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

  /// Whether a watch's [data] passes every filter here. Search text is not
  /// part of the model, so callers apply it themselves.
  bool matches(Map<String, dynamic> data) {
    if (style != 'All' && data['styleCategory'] != style) return false;
    if (brand != 'All' && data['brand'] != brand) return false;
    // A watch with no targetGender never shows under a specific gender, and
    // is never guessed into a bucket. It still shows under "All".
    if (gender != 'All' && data['targetGender'] != gender) return false;
    if (arOnly && data['has3DModel'] != true) return false;
    if (listingStatus != 'All' &&
        (data['listedInCatalog'] == true) != (listingStatus == 'Active')) {
      return false;
    }
    final range = priceRange;
    if (range != null) {
      // No price at all: excluded once a range is applied, since there is
      // no way to know whether it belongs in range.
      final price = (data['price'] as num?)?.toDouble();
      if (price == null || price < range.start || price > range.end) {
        return false;
      }
    }
    return true;
  }

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

  /// A label and a row of single-select pills.
  Widget _group(String label, List<String> options, String selected,
      ValueChanged<String> onSelected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: kLabelStyle),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                luxePill(
                  option,
                  selected: option == selected,
                  onTap: () => setState(() => onSelected(option)),
                ),
            ],
          ),
        ],
      ),
    );
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
                children: [
                  Text('Filters', style: AppTheme.serif(size: 26)),
                  const Spacer(),
                  TextButton(
                    onPressed:
                        _draft.isDefault && _priceIsFullRange ? null : _reset,
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.textSecondary),
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _group('STYLE', ['All', ...widget.styleOptions], _draft.style,
                  (v) => _draft = _draft.copyWith(style: v)),
              if (widget.brandOptions.isNotEmpty)
                _group('BRAND', ['All', ...widget.brandOptions], _draft.brand,
                    (v) => _draft = _draft.copyWith(brand: v)),
              if (widget.showGenderFilter)
                _group('GENDER', _genderOptions, _draft.gender,
                    (v) => _draft = _draft.copyWith(gender: v)),
              if (widget.showListingStatusFilter)
                _group('LISTING STATUS', _listingStatusOptions,
                    _draft.listingStatus,
                    (v) => _draft = _draft.copyWith(listingStatus: v)),
              if (widget.showArFilter) ...[
                Text('AR TRY-ON', style: kLabelStyle),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _draft.arOnly,
                  onChanged: (value) =>
                      setState(() => _draft = _draft.copyWith(arOnly: value)),
                  activeThumbColor: AppTheme.textPrimary,
                  activeTrackColor: AppTheme.outline,
                  title: Text(
                    'Only show watches with AR try-on',
                    style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text('PRICE RANGE', style: kLabelStyle),
              const SizedBox(height: 10),
              if (widget.priceCeiling > widget.priceFloor) ...[
                Text(
                  '${formatPeso(_priceDraft.start)}  to  '
                  '${formatPeso(_priceDraft.end)}',
                  style: AppTheme.serif(size: 20),
                ),
                RangeSlider(
                  values: _priceDraft,
                  min: widget.priceFloor,
                  max: widget.priceCeiling,
                  activeColor: AppTheme.textPrimary,
                  inactiveColor: AppTheme.outline,
                  labels: RangeLabels(
                    formatPeso(_priceDraft.start),
                    formatPeso(_priceDraft.end),
                  ),
                  onChanged: (values) => setState(() => _priceDraft = values),
                ),
              ] else
                // Every watch shares the same price (or there is only one).
                // A slider with equal min and max looks broken, so say so.
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Not enough price variation in the catalog to filter by range yet.',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _apply,
                  child: const Text('Apply Filters'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// App-bar filter icon with a small badge showing how many filters are
/// active. Identical on all three catalog screens by design.
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
        backgroundColor: AppTheme.textPrimary,
        textColor: AppTheme.background,
        child: const Icon(Icons.filter_list),
      ),
    );
  }
}

typedef WatchDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

enum CatalogSort {
  newest('Newest'),
  priceLowToHigh('Price: Low to High'),
  priceHighToLow('Price: High to Low'),
  nameAToZ('Name: A to Z');

  final String label;
  const CatalogSort(this.label);
}

List<WatchDoc> sortWatchDocs(List<WatchDoc> docs, CatalogSort sort) {
  num price(WatchDoc d) => (d.data()['price'] as num?) ?? 0;
  String name(WatchDoc d) => (d.data()['name'] as String? ?? '').toLowerCase();

  final sorted = [...docs];
  switch (sort) {
    case CatalogSort.priceLowToHigh:
      sorted.sort((a, b) => price(a).compareTo(price(b)));
    case CatalogSort.priceHighToLow:
      sorted.sort((a, b) => price(b).compareTo(price(a)));
    case CatalogSort.nameAToZ:
      sorted.sort((a, b) => name(a).compareTo(name(b)));
    case CatalogSort.newest:
      sorted.sort((a, b) {
        final createdA = a.data()['createdAt'] as Timestamp?;
        final createdB = b.data()['createdAt'] as Timestamp?;
        if (createdA == null && createdB == null) return 0;
        if (createdA == null) return 1;
        if (createdB == null) return -1;
        return createdB.compareTo(createdA);
      });
  }
  return sorted;
}

/// App bar sort menu with a check beside the current choice.
class CatalogSortButton extends StatelessWidget {
  final CatalogSort selected;
  final ValueChanged<CatalogSort> onSelected;

  const CatalogSortButton({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<CatalogSort>(
      icon: const Icon(Icons.sort),
      color: AppTheme.surface,
      initialValue: selected,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final option in CatalogSort.values)
          PopupMenuItem(
            value: option,
            child: Row(
              children: [
                Icon(
                  Icons.check,
                  size: 18,
                  color: option == selected
                      ? AppTheme.textPrimary
                      : Colors.transparent,
                ),
                const SizedBox(width: 8),
                Text(
                  option.label,
                  style: TextStyle(
                    color: option == selected
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Underline search field shown above a catalog. The caller keeps the query
/// in state and rebuilds on [onChanged], which also updates the clear button.
class CatalogSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const CatalogSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 15),
        decoration: luxeFieldDecoration(
          hint: 'Search by name, brand, or style',
          prefixIcon: Icon(Icons.search,
              size: 20, color: AppTheme.textSecondary),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: AppTheme.textSecondary,
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}