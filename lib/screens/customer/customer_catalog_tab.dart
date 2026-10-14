import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../widgets/catalog_filter_sheet.dart';
import '../../widgets/luxe.dart';
import '../../widgets/network_photo.dart';
import '../../widgets/skeleton_box.dart';
import '../../widgets/watch_tile.dart';
import 'watch_detail_screen.dart';

typedef _WatchDoc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// Height of a list-view row. The photo is a square of this size, and it is
/// tall enough for a 2-line name, size and style, and price.
const double _listRowHeight = 132;

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
  static const List<String> _styleOptions = [
    'Classic',
    'Sport',
    'Luxury',
    'Casual',
  ];

  final _watchService = WatchService();
  final _searchController = TextEditingController();

  // Created once. Building a new stream on every build made the
  // StreamBuilder resubscribe and briefly report "waiting", which swapped
  // the grid for loading placeholders and removed the photos a Hero
  // animation needs to fly from.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _watchesStream =
      _watchService.allListedWatches();

  // Keeps photo Hero tags unique to this copy of the screen. The catalog
  // exists as a tab and can also be pushed from Home, and identical tags
  // across the two made photos fly between them on navigation.
  late final String _heroScope = 'catalog-$hashCode';

  String _searchQuery = '';
  // Every filter (style, gender, AR, brand, price) lives in one
  // CatalogFilters value, set through the shared filter sheet.
  CatalogFilters _filters = const CatalogFilters();
  _SortOption _sortOption = _SortOption.newest;
  // Grid is the default. The app bar toggle switches to a single column.
  bool _isMultiColumn = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _watchesStream,
      builder: (context, snapshot) {
        final allDocs = snapshot.data?.docs ?? <_WatchDoc>[];

        // Brand list and price bounds come from the catalog's current data,
        // so the filter sheet always reflects what is actually listed.
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

        final docs = _applySort(allDocs.where(_matches).toList());

        return Scaffold(
          appBar: AppBar(
            title: Text('Catalog', style: AppTheme.serif(size: 28)),
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
                itemBuilder: (context) => [
                  for (final option in _SortOption.values)
                    PopupMenuItem(
                      value: option,
                      child: Row(
                        children: [
                          Icon(
                            Icons.check,
                            size: 18,
                            color: option == _sortOption
                                ? AppTheme.textPrimary
                                : Colors.transparent,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            option.label,
                            style: TextStyle(
                              color: option == _sortOption
                                  ? AppTheme.textPrimary
                                  : AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 15),
                  decoration: luxeFieldDecoration(
                    hint: 'Search by name, brand, or style',
                    prefixIcon: Icon(Icons.search,
                        size: 20, color: AppTheme.textSecondary),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            color: AppTheme.textSecondary,
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                  ),
                  onChanged: (value) =>
                      setState(() => _searchQuery = value.toLowerCase()),
                ),
              ),
              Expanded(child: _body(snapshot, docs, _heroScope)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
      List<_WatchDoc> docs, String heroScope) {
    if (snapshot.hasError) {
      return Center(
        child: Text(
          'Error loading catalog: ${snapshot.error}',
          style: const TextStyle(color: Colors.redAccent),
          textAlign: TextAlign.center,
        ),
      );
    }
    // Placeholders match whichever view is active, so the layout doesn't
    // change shape when the data arrives.
    if (snapshot.connectionState == ConnectionState.waiting &&
        !snapshot.hasData) {
      return _isMultiColumn
          ? _gridView(
              List<Widget>.filled(6, const WatchTileSkeleton(showPrice: true)),
              loading: true)
          : _listView(List<Widget>.filled(6, const _ListTileSkeleton()),
              loading: true);
    }
    if (docs.isEmpty) {
      return Center(
        child: Text(
          _filters.isDefault && _searchQuery.isEmpty
              ? 'No watches found.'
              : 'No watches match your search or filters.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      );
    }
    return _isMultiColumn
        ? _gridView([
            for (final doc in docs)
              WatchTile(
                watchId: doc.id,
                data: doc.data(),
                heroScope: heroScope,
                showPrice: true,
              ),
          ])
        : _listView([
            for (final doc in docs)
              _WatchListTile(
                  watchId: doc.id, data: doc.data(), heroScope: heroScope),
          ]);
  }

  /// Two tiles per row. Rows size to their content, so there is no guessed
  /// aspect ratio and no blank space under tiles on any screen width.
  Widget _gridView(List<Widget> tiles, {bool loading = false}) {
    return ListView.builder(
      physics: loading ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: (tiles.length / 2).ceil(),
      itemBuilder: (context, row) {
        final first = row * 2;
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: tiles[first]),
              const SizedBox(width: 14),
              Expanded(
                child: first + 1 < tiles.length
                    ? tiles[first + 1]
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _listView(List<Widget> rows, {bool loading = false}) {
    return ListView.separated(
      physics: loading ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) => rows[index],
    );
  }

  /// Whether a watch passes the current filters and search text.
  bool _matches(_WatchDoc doc) {
    final data = doc.data();
    if (_filters.style != 'All' && data['styleCategory'] != _filters.style) {
      return false;
    }
    if (_filters.brand != 'All' && data['brand'] != _filters.brand) {
      return false;
    }
    // A watch with no targetGender never appears under a specific gender
    // filter. It still shows under "All", and is never guessed into a bucket.
    if (_filters.gender != 'All' && data['targetGender'] != _filters.gender) {
      return false;
    }
    if (_filters.arOnly && !(data['has3DModel'] as bool? ?? false)) {
      return false;
    }
    final range = _filters.priceRange;
    if (range != null) {
      // No listed price at all: excluded once a range is applied, since
      // there is no way to know if it belongs in range.
      final price = (data['price'] as num?)?.toDouble();
      if (price == null || price < range.start || price > range.end) {
        return false;
      }
    }
    if (_searchQuery.isNotEmpty) {
      bool has(String key) =>
          (data[key] as String? ?? '').toLowerCase().contains(_searchQuery);
      return has('name') || has('brand') || has('styleCategory');
    }
    return true;
  }

  List<_WatchDoc> _applySort(List<_WatchDoc> docs) {
    num price(_WatchDoc d) => (d.data()['price'] as num?) ?? 0;
    String name(_WatchDoc d) =>
        (d.data()['name'] as String? ?? '').toLowerCase();

    final sorted = List<_WatchDoc>.from(docs);
    switch (_sortOption) {
      case _SortOption.priceLowToHigh:
        sorted.sort((a, b) => price(a).compareTo(price(b)));
      case _SortOption.priceHighToLow:
        sorted.sort((a, b) => price(b).compareTo(price(a)));
      case _SortOption.nameAToZ:
        sorted.sort((a, b) => name(a).compareTo(name(b)));
      case _SortOption.newest:
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
}

/// Single-column row for list view: a filled card with the photo flush on
/// the left and the details beside it.
class _WatchListTile extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;
  final String heroScope;

  const _WatchListTile({
    required this.watchId,
    required this.data,
    required this.heroScope,
  });

  @override
  Widget build(BuildContext context) {
    final heroTag = '$heroScope-photo-$watchId';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final price = data['price'];
    final size = data['caseDiameterMm'];
    final style = data['styleCategory'] as String? ?? '';
    final sub = [if (size != null) '${size}mm', if (style.isNotEmpty) style]
        .join(' · ');
    final fallback = Center(
      child: Icon(Icons.watch, size: 32, color: AppTheme.textSecondary),
    );

    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => WatchDetailScreen(
                watchId: watchId, data: data, heroTag: heroTag),
          ),
        ),
        child: SizedBox(
          height: _listRowHeight,
          child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _listRowHeight,
                  child: ColoredBox(
                    color: AppTheme.background,
                    child: imageUrl.isEmpty
                        ? fallback
                        : Hero(
                            tag: heroTag,
                            child: NetworkPhoto(
                                url: imageUrl, errorWidget: fallback),
                          ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (data['brand'] as String? ?? '').toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 10,
                              letterSpacing: 1.2),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          data['name'] as String? ?? 'Unnamed Watch',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w500),
                        ),
                        if (sub.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(sub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                        if (price is num) ...[
                          const SizedBox(height: 6),
                          Text(formatPeso(price),
                              style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
          ),
        ),
      ),
    );
  }
}

/// Placeholder shaped like [_WatchListTile].
class _ListTileSkeleton extends StatelessWidget {
  const _ListTileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _listRowHeight,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          SkeletonBox(
              width: _listRowHeight,
              height: _listRowHeight,
              borderRadius: BorderRadius.zero),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 44, height: 9),
                  SizedBox(height: 8),
                  SkeletonBox(width: 140, height: 13),
                  SizedBox(height: 8),
                  SkeletonBox(width: 70, height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}