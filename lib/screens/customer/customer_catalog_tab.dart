import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../constants/watch_colors.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/catalog_filter_sheet.dart';
import 'watch_detail_screen.dart';

enum _SortOption {
  newest('Newest'),
  priceLowToHigh('Price: Low to High'),
  priceHighToLow('Price: High to Low'),
  nameAToZ('Name: A to Z');

  final String label;
  const _SortOption(this.label);
}

class CustomerCatalogTab extends StatefulWidget {
  const CustomerCatalogTab({super.key});

  @override
  State<CustomerCatalogTab> createState() => _CustomerCatalogTabState();
}

class _CustomerCatalogTabState extends State<CustomerCatalogTab> {
  final _watchService = WatchService();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  // All catalog filters (style, gender, AR, brand, price) live in one
  // CatalogFilters value now, set via the shared filter sheet, instead
  // of a loose field per filter and an always-visible chip row per
  // group — see lib/widgets/catalog_filter_sheet.dart for why.
  CatalogFilters _filters = const CatalogFilters();
  _SortOption _sortOption = _SortOption.newest;
  // Multi-column grid is the default; the toggle in the app bar lets the
  // customer switch to a single-column list instead.
  bool _isMultiColumn = true;

  static const List<String> _styleOptions = [
    'Classic',
    'Sport',
    'Luxury',
    'Casual',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _watchService.allListedWatches(),
      builder: (context, snapshot) {
        final allDocs = snapshot.data?.docs ?? [];

        // Brand list and price bounds are derived from the catalog's
        // CURRENT data every time it changes, rather than hardcoded —
        // so the filter sheet's brand chips and price slider always
        // reflect what's actually listed, not a guess that goes stale
        // as merchants add or remove watches.
        final brandOptions = allDocs
            .map((d) => d.data()['brand'] as String? ?? '')
            .where((b) => b.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final prices = allDocs
            .map((d) => (d.data()['price'] as num?)?.toDouble())
            .whereType<double>()
            .toList();
        final priceFloor =
            prices.isEmpty ? 0.0 : prices.reduce((a, b) => a < b ? a : b);
        final priceCeiling =
            prices.isEmpty ? 0.0 : prices.reduce((a, b) => a > b ? a : b);

        var docs = allDocs;

        if (_filters.style != 'All') {
          docs = docs
              .where((d) => d.data()['styleCategory'] == _filters.style)
              .toList();
        }
        if (_filters.brand != 'All') {
          docs =
              docs.where((d) => d.data()['brand'] == _filters.brand).toList();
        }
        // A watch with no targetGender set (unspecified) simply won't
        // appear under any specific gender filter — it's still visible
        // under "All", never guessed into a bucket.
        if (_filters.gender != 'All') {
          docs = docs
              .where((d) => d.data()['targetGender'] == _filters.gender)
              .toList();
        }
        if (_filters.arOnly) {
          docs = docs
              .where((d) => d.data()['has3DModel'] as bool? ?? false)
              .toList();
        }
        if (_filters.priceRange != null) {
          final range = _filters.priceRange!;
          docs = docs.where((d) {
            final price = (d.data()['price'] as num?)?.toDouble();
            // No listed price at all -> excluded once a price range is
            // actively applied, since there's no way to know if it
            // belongs in range.
            if (price == null) return false;
            return price >= range.start && price <= range.end;
          }).toList();
        }
        if (_searchQuery.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data();
            final name = (data['name'] as String? ?? '').toLowerCase();
            final brand = (data['brand'] as String? ?? '').toLowerCase();
            final style =
                (data['styleCategory'] as String? ?? '').toLowerCase();
            return name.contains(_searchQuery) ||
                brand.contains(_searchQuery) ||
                style.contains(_searchQuery);
          }).toList();
        }

        docs = _applySort(docs);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Watch Catalog'),
            actions: [
              CatalogFilterButton(
                activeCount: _filters.activeCount,
                onPressed: () async {
                  final result = await showCatalogFilterSheet(
                    context,
                    initial: _filters,
                    styleOptions: _styleOptions,
                    brandOptions: brandOptions,
                    priceFloor: priceFloor,
                    priceCeiling: priceCeiling,
                    showGenderFilter: true,
                    showArFilter: true,
                    showListingStatusFilter: false,
                  );
                  if (result != null) setState(() => _filters = result);
                },
              ),
              IconButton(
                icon: Icon(_isMultiColumn
                    ? Icons.view_agenda_outlined
                    : Icons.grid_view),
                tooltip:
                    _isMultiColumn ? 'Switch to list view' : 'Switch to grid view',
                onPressed: () =>
                    setState(() => _isMultiColumn = !_isMultiColumn),
              ),
              PopupMenuButton<_SortOption>(
                icon: const Icon(Icons.sort),
                color: AppTheme.surface,
                initialValue: _sortOption,
                onSelected: (option) => setState(() => _sortOption = option),
                itemBuilder: (context) => _SortOption.values.map((option) {
                  final isSelected = option == _sortOption;
                  return PopupMenuItem(
                    value: option,
                    child: Row(
                      children: [
                        if (isSelected)
                          const Icon(Icons.check, color: AppTheme.gold, size: 18)
                        else
                          const SizedBox(width: 18),
                        const SizedBox(width: 8),
                        Text(
                          option.label,
                          style: TextStyle(
                            color: isSelected
                                ? AppTheme.gold
                                : AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name, brand, or style...',
                    prefixIcon:
                        const Icon(Icons.search, color: AppTheme.textSecondary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            color: AppTheme.textSecondary,
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.toLowerCase());
                  },
                ),
              ),
              Expanded(
                child: Builder(builder: (context) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error loading catalog: ${snapshot.error}',
                        style: const TextStyle(color: Colors.redAccent),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        _filters.isDefault && _searchQuery.isEmpty
                            ? 'No watches found.'
                            : 'No watches match your search or filters.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  if (_isMultiColumn) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: GridView.builder(
                        padding: const EdgeInsets.only(bottom: 16, top: 4),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.60,
                        ),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          return _WatchCard(watchId: doc.id, data: data);
                        },
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount: docs.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      return _WatchListTile(watchId: doc.id, data: data);
                    },
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _applySort(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);

    switch (_sortOption) {
      case _SortOption.priceLowToHigh:
        sorted.sort((a, b) {
          final priceA = (a.data()['price'] as num?) ?? 0;
          final priceB = (b.data()['price'] as num?) ?? 0;
          return priceA.compareTo(priceB);
        });
        break;
      case _SortOption.priceHighToLow:
        sorted.sort((a, b) {
          final priceA = (a.data()['price'] as num?) ?? 0;
          final priceB = (b.data()['price'] as num?) ?? 0;
          return priceB.compareTo(priceA);
        });
        break;
      case _SortOption.nameAToZ:
        sorted.sort((a, b) {
          final nameA = (a.data()['name'] as String? ?? '').toLowerCase();
          final nameB = (b.data()['name'] as String? ?? '').toLowerCase();
          return nameA.compareTo(nameB);
        });
        break;
      case _SortOption.newest:
        sorted.sort((a, b) {
          final createdA = a.data()['createdAt'] as Timestamp?;
          final createdB = b.data()['createdAt'] as Timestamp?;
          if (createdA == null && createdB == null) return 0;
          if (createdA == null) return 1;
          if (createdB == null) return -1;
          return createdB.compareTo(createdA);
        });
        break;
    }

    return sorted;
  }
}

class _WatchCard extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const _WatchCard({required this.watchId, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final price = data['price'];
    final style = data['styleCategory'] as String? ?? '';
    final caseDiameter = data['caseDiameterMm'];
    final imageUrl = data['imageUrl'] as String? ?? '';
    final colorHexesRaw = (data['colorHexes'] as List?)?.cast<String>();
    final legacyColorHex = data['colorHex'] as String?;
    final colorHexes = (colorHexesRaw != null && colorHexesRaw.isNotEmpty)
        ? colorHexesRaw
        : (legacyColorHex != null ? [legacyColorHex] : const <String>[]);

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WatchDetailScreen(watchId: watchId, data: data),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                child: Container(
                  color: AppTheme.background,
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                            child: Icon(Icons.watch,
                                size: 40, color: AppTheme.gold),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            );
                          },
                        )
                      : const Center(
                          child:
                              Icon(Icons.watch, size: 40, color: AppTheme.gold),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  const SizedBox(height: 1),
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (caseDiameter != null) '${caseDiameter}mm',
                      if (style.isNotEmpty) style,
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (price != null)
                    Text(
                      'PHP $price',
                      style: const TextStyle(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  if (colorHexes.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        for (final hex in colorHexes.take(3))
                          Padding(
                            padding: const EdgeInsets.only(right: 3),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: hexToColor(hex),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 0.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
/// Single-column list row shown when the catalog's view toggle is set to
/// list mode instead of the default grid.
class _WatchListTile extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const _WatchListTile({required this.watchId, required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final price = data['price'];
    final style = data['styleCategory'] as String? ?? '';
    final caseDiameter = data['caseDiameterMm'];
    final imageUrl = data['imageUrl'] as String? ?? '';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WatchDetailScreen(watchId: watchId, data: data),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(10),
              ),
              clipBehavior: Clip.antiAlias,
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.watch,
                          color: AppTheme.gold,
                          size: 36),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                    )
                  : const Icon(Icons.watch, color: AppTheme.gold, size: 36),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand.toUpperCase(),
                      style: const TextStyle(
                        color: AppTheme.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (caseDiameter != null) '${caseDiameter}mm',
                      if (style.isNotEmpty) style,
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (price != null)
                    Text(
                      'PHP $price',
                      style: const TextStyle(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}