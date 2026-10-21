import 'dart:math' show max, min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../utils/ar_readiness.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/stock.dart';
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
  // Only watches with at least one unit on hand. A watch with no stock count
  // is left out once this is on, since its availability is unknown.
  final bool inStockOnly;
  final String brand;
  final RangeValues? priceRange;
  // Lug-to-lug range in mm. Null means not constrained, same as [priceRange].
  final RangeValues? lugRange;
  // 'All' | 'Active' | 'Draft' — only meaningful on merchant/admin screens,
  // where showListingStatusFilter is true. Customers only ever see listed
  // watches in the first place, so this field is simply unused there.
  final String listingStatus;

  const CatalogFilters({
    this.style = 'All',
    this.gender = 'All',
    this.arOnly = false,
    this.inStockOnly = false,
    this.brand = 'All',
    this.priceRange,
    this.lugRange,
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
    if (arOnly && !isArReady(data)) return false;
    if (inStockOnly && !isInStock(data)) return false;
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
    final lugRangeValue = lugRange;
    if (lugRangeValue != null) {
      // No lug-to-lug on file: excluded once a range is applied.
      final lug = (data['lugToLugMm'] as num?)?.toDouble();
      if (lug == null || lug < lugRangeValue.start || lug > lugRangeValue.end) {
        return false;
      }
    }
    return true;
  }

  CatalogFilters copyWith({
    String? style,
    String? gender,
    bool? arOnly,
    bool? inStockOnly,
    String? brand,
    RangeValues? priceRange,
    bool clearPriceRange = false,
    RangeValues? lugRange,
    bool clearLugRange = false,
    String? listingStatus,
  }) {
    return CatalogFilters(
      style: style ?? this.style,
      gender: gender ?? this.gender,
      arOnly: arOnly ?? this.arOnly,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      brand: brand ?? this.brand,
      priceRange: clearPriceRange ? null : (priceRange ?? this.priceRange),
      lugRange: clearLugRange ? null : (lugRange ?? this.lugRange),
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
    if (inStockOnly) count++;
    if (brand != 'All') count++;
    if (priceRange != null) count++;
    if (lugRange != null) count++;
    if (listingStatus != 'All') count++;
    return count;
  }

  bool get isDefault => activeCount == 0;
}

/// Smallest and largest lug-to-lug (rounded outward to whole mm) among
/// [docs]. Both are 0 when no watch lists one.
({double floor, double ceiling}) lugBounds(Iterable<WatchDoc> docs) {
  final values = [
    for (final d in docs)
      if (d.data()['lugToLugMm'] is num)
        (d.data()['lugToLugMm'] as num).toDouble(),
  ];
  if (values.isEmpty) return (floor: 0, ceiling: 0);
  return (
    floor: values.reduce(min).floorToDouble(),
    ceiling: values.reduce(max).ceilToDouble(),
  );
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
  required double lugFloor,
  required double lugCeiling,
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
      lugFloor: lugFloor,
      lugCeiling: lugCeiling,
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
  final double lugFloor;
  final double lugCeiling;
  final bool showGenderFilter;
  final bool showArFilter;
  final bool showListingStatusFilter;

  const _FilterSheetBody({
    required this.initial,
    required this.styleOptions,
    required this.brandOptions,
    required this.priceFloor,
    required this.priceCeiling,
    required this.lugFloor,
    required this.lugCeiling,
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
  late RangeValues _lugDraft;

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
    _lugDraft = widget.initial.lugRange ??
        RangeValues(widget.lugFloor, widget.lugCeiling);
  }

  bool get _priceIsFullRange =>
      _priceDraft.start <= widget.priceFloor &&
      _priceDraft.end >= widget.priceCeiling;

  bool get _lugIsFullRange =>
      _lugDraft.start <= widget.lugFloor && _lugDraft.end >= widget.lugCeiling;

  void _reset() {
    setState(() {
      _draft = const CatalogFilters();
      _priceDraft = RangeValues(widget.priceFloor, widget.priceCeiling);
      _lugDraft = RangeValues(widget.lugFloor, widget.lugCeiling);
    });
  }

  void _apply() {
    final result = _draft.copyWith(
      priceRange: _priceIsFullRange ? null : _priceDraft,
      clearPriceRange: _priceIsFullRange,
      lugRange: _lugIsFullRange ? null : _lugDraft,
      clearLugRange: _lugIsFullRange,
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

  /// A label, the chosen range as text, and a range slider. Shows a short
  /// note instead when the catalog has no variation to filter by.
  Widget _rangeSection(String label, RangeValues draft, double floor,
      double ceiling, String Function(double) fmt, String what,
      ValueChanged<RangeValues> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: kLabelStyle),
        const SizedBox(height: 10),
        if (ceiling > floor) ...[
          Text('${fmt(draft.start)}  to  ${fmt(draft.end)}',
              style: AppTheme.serif(size: 20)),
          RangeSlider(
            values: draft,
            min: floor,
            max: ceiling,
            activeColor: AppTheme.textPrimary,
            inactiveColor: AppTheme.outline,
            labels: RangeLabels(fmt(draft.start), fmt(draft.end)),
            onChanged: (values) => setState(() => onChanged(values)),
          ),
        ] else
          // Every watch shares the same value (or there is only one). A
          // slider with equal min and max looks broken, so say so.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Not enough $what variation in the catalog to filter by range yet.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
      ],
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
                    onPressed: _draft.isDefault &&
                            _priceIsFullRange &&
                            _lugIsFullRange
                        ? null
                        : _reset,
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
              Text('AVAILABILITY', style: kLabelStyle),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _draft.inStockOnly,
                onChanged: (value) => setState(
                    () => _draft = _draft.copyWith(inStockOnly: value)),
                activeThumbColor: AppTheme.textPrimary,
                activeTrackColor: AppTheme.outline,
                title: Text(
                  'Only show watches that are in stock',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                ),
              ),
              const SizedBox(height: 12),
              _rangeSection('PRICE RANGE', _priceDraft, widget.priceFloor,
                  widget.priceCeiling, formatPeso, 'price',
                  (v) => _priceDraft = v),
              const SizedBox(height: 20),
              _rangeSection('LUG-TO-LUG RANGE', _lugDraft, widget.lugFloor,
                  widget.lugCeiling, (v) => '${v.round()} mm', 'lug-to-lug',
                  (v) => _lugDraft = v),
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