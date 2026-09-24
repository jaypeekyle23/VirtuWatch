import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/catalog_filter_sheet.dart';
import '../merchant/merchant_catalog_tab.dart' show missingWatchFields;
import '../merchant/merchant_edit_watch_screen.dart';
import '../merchant/merchant_add_watch_screen.dart';
import '../merchant/merchant_watch_detail_screen.dart';

enum _SortOption {
  newest('Newest'),
  priceLowToHigh('Price: Low to High'),
  priceHighToLow('Price: High to Low'),
  nameAToZ('Name: A to Z');

  final String label;
  const _SortOption(this.label);
}

class AdminWatchManagementTab extends StatefulWidget {
  const AdminWatchManagementTab({super.key});

  @override
  State<AdminWatchManagementTab> createState() =>
      _AdminWatchManagementTabState();
}

class _AdminWatchManagementTabState extends State<AdminWatchManagementTab> {
  final _watchService = WatchService();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  // Same shared CatalogFilters/filter sheet as the customer and merchant
  // catalogs — see lib/widgets/catalog_filter_sheet.dart.
  CatalogFilters _filters = const CatalogFilters();
  // Same data-completeness helper the merchant catalog uses — admins
  // manage the whole platform's catalog, so the same "which watches are
  // missing gender/color/fit data" concern applies here too, if not more.
  bool _needsInfoOnly = false;
  _SortOption _sortOption = _SortOption.newest;
  // Multi-column grid is the default; the toggle in the app bar lets the
  // admin switch to the original single-column list instead.
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
      stream: FirebaseFirestore.instance
          .collection('watches')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        final allDocs = snapshot.data?.docs ?? [];

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

        final incompleteCount = allDocs
            .where((d) => missingWatchFields(d.data()).isNotEmpty)
            .length;

        var docs = allDocs;

        if (_needsInfoOnly) {
          docs = docs
              .where((d) => missingWatchFields(d.data()).isNotEmpty)
              .toList();
        }
        if (_filters.style != 'All') {
          docs = docs
              .where((d) => d.data()['styleCategory'] == _filters.style)
              .toList();
        }
        if (_filters.brand != 'All') {
          docs =
              docs.where((d) => d.data()['brand'] == _filters.brand).toList();
        }
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
        if (_filters.listingStatus != 'All') {
          final wantListed = _filters.listingStatus == 'Active';
          docs = docs
              .where((d) =>
                  (d.data()['listedInCatalog'] as bool? ?? false) ==
                  wantListed)
              .toList();
        }
        if (_filters.priceRange != null) {
          final range = _filters.priceRange!;
          docs = docs.where((d) {
            final price = (d.data()['price'] as num?)?.toDouble();
            if (price == null) return false;
            return price >= range.start && price <= range.end;
          }).toList();
        }
        if (_searchQuery.isNotEmpty) {
          docs = docs.where((d) {
            final data = d.data();
            final name = (data['name'] as String? ?? '').toLowerCase();
            final brand = (data['brand'] as String? ?? '').toLowerCase();
            return name.contains(_searchQuery) || brand.contains(_searchQuery);
          }).toList();
        }

        docs = _applySort(docs);

        return Scaffold(
          appBar: AppBar(
            title: const Text('Watch Management'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add Watch',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const MerchantAddWatchScreen(),
                    ),
                  );
                },
              ),
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
                    showListingStatusFilter: true,
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
                    hintText: 'Search watches by name or brand...',
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
              if (incompleteCount > 0)
                _NeedsInfoBanner(
                  count: incompleteCount,
                  isActive: _needsInfoOnly,
                  onToggle: () =>
                      setState(() => _needsInfoOnly = !_needsInfoOnly),
                ),
              Expanded(
                child: Builder(builder: (context) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
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
                        'No watches found.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    );
                  }

                  if (_isMultiColumn) {
                    // Built row-by-row instead of GridView + a fixed
                    // childAspectRatio: a hardcoded ratio has to guess a
                    // worst-case cell height for the narrowest phone this
                    // app supports, which leaves leftover blank space
                    // under every card on a normal-width phone. Since
                    // _AdminWatchGridCard already sizes itself to exactly
                    // what its content needs (mainAxisSize.min
                    // throughout), putting two cards in a Row and letting
                    // the Row size itself to them gives every row its
                    // exact natural height, on any screen width, with no
                    // guessing and no leftover space.
                    final rowCount = (docs.length / 2).ceil();
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 16, top: 4),
                        itemCount: rowCount,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, rowIndex) {
                          final firstIndex = rowIndex * 2;
                          final secondIndex = firstIndex + 1;
                          final firstDoc = docs[firstIndex];
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: _AdminWatchGridCard(
                                  watchId: firstDoc.id,
                                  data: firstDoc.data(),
                                  watchService: _watchService,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: secondIndex < docs.length
                                    ? _AdminWatchGridCard(
                                        watchId: docs[secondIndex].id,
                                        data: docs[secondIndex].data(),
                                        watchService: _watchService,
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          );
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
                      return _AdminWatchTile(
                        watchId: doc.id,
                        data: doc.data(),
                        watchService: _watchService,
                      );
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

/// Same completeness-banner concept as the merchant catalog — see
/// merchant_catalog_tab.dart's _NeedsInfoBanner for the reasoning.
class _NeedsInfoBanner extends StatelessWidget {
  final int count;
  final bool isActive;
  final VoidCallback onToggle;

  const _NeedsInfoBanner({
    required this.count,
    required this.isActive,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.orangeAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isActive
                    ? 'Showing ${count == 1 ? '1 watch' : '$count watches'} needing gender, color, or fit data.'
                    : '${count == 1 ? '1 watch is' : '$count watches are'} missing gender, color, or fit data.',
                style: const TextStyle(
                  color: Colors.orangeAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              isActive ? 'Show all' : 'Review',
              style: const TextStyle(
                color: Colors.orangeAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminWatchTile extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;
  final WatchService watchService;

  const _AdminWatchTile({
    required this.watchId,
    required this.data,
    required this.watchService,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final price = data['price'];
    final listed = data['listedInCatalog'] as bool? ?? false;
    final has3D = data['has3DModel'] as bool? ?? false;
    final missing = missingWatchFields(data);
    final imageUrl = data['imageUrl'] as String? ?? '';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MerchantWatchDetailScreen(
              watchId: watchId,
              data: data,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      brand.isNotEmpty ? '$brand $name' : name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _statusChip(listed ? 'ACTIVE' : 'DRAFT',
                            listed ? Colors.greenAccent : AppTheme.textSecondary),
                        _statusChip(has3D ? 'AR' : 'NO 3D',
                            has3D ? AppTheme.gold : AppTheme.textSecondary),
                        if (missing.isNotEmpty)
                          Tooltip(
                            message: 'Missing: ${missing.join(', ')}',
                            child: _statusChip(
                                'NEEDS INFO', Colors.orangeAccent),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: listed,
                  activeThumbColor: AppTheme.gold,
                  onChanged: (value) => _handleToggleListed(context, value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Divider(color: AppTheme.background, height: 1),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (price != null)
                Text(
                  'PHP $price',
                  style: const TextStyle(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                )
              else
                const SizedBox(),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    color: AppTheme.textSecondary,
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => MerchantEditWatchScreen(
                            watchId: watchId,
                            data: data,
                          ),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    color: Colors.redAccent,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDelete(context),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _handleToggleListed(BuildContext context, bool value) async {
    try {
      await watchService.updateWatch(watchId, {'listedInCatalog': value});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? '"${data['name']}" is now listed in the catalog.'
                  : '"${data['name']}" was unlisted from the catalog.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update listing: $e')),
        );
      }
    }
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Watch?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'This will permanently remove "${data['name']}" from the catalog.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await watchService.deleteWatch(
        watchId,
        watchLabel: data['name'] as String? ?? watchId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Watch deleted.')),
        );
      }
    }
  }
}
/// Compact grid-cell version of the admin watch tile, shown when the
/// catalog's view toggle is set to grid mode (the default). Keeps the
/// same listed switch and edit/delete actions as the single-column tile.
class _AdminWatchGridCard extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;
  final WatchService watchService;

  const _AdminWatchGridCard({
    required this.watchId,
    required this.data,
    required this.watchService,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final price = data['price'];
    final listed = data['listedInCatalog'] as bool? ?? false;
    final has3D = data['has3DModel'] as bool? ?? false;
    final missing = missingWatchFields(data);
    final imageUrl = data['imageUrl'] as String? ?? '';

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MerchantWatchDetailScreen(
              watchId: watchId,
              data: data,
            ),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.3,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Container(
                color: AppTheme.background,
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child: Icon(Icons.watch, size: 32, color: AppTheme.gold),
                        ),
                      )
                    : const Center(
                        child: Icon(Icons.watch, size: 32, color: AppTheme.gold),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Fixed-height box sized for 2 lines, so a short name
                // doesn't leave this card shorter than its neighbors.
                SizedBox(
                  height: 36,
                  child: Text(
                    brand.isNotEmpty ? '$brand $name' : name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                // Fixed-height box sized for 2 rows of chips: with
                // "Needs Info" showing, 3 chips can wrap to a second row
                // on a narrow card, while watches without that chip only
                // need 1 row. Reserving space for the taller case keeps
                // every card the same height regardless of chip count.
                SizedBox(
                  height: 36,
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _statusChip(listed ? 'ACTIVE' : 'DRAFT',
                          listed ? Colors.greenAccent : AppTheme.textSecondary),
                      _statusChip(has3D ? 'AR' : 'NO 3D',
                          has3D ? AppTheme.gold : AppTheme.textSecondary),
                      if (missing.isNotEmpty)
                        Tooltip(
                          message: 'Missing: ${missing.join(', ')}',
                          child: _statusChip('NEEDS INFO', Colors.orangeAccent),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 18,
                  child: price != null
                      ? Text(
                          'PHP $price',
                          style: const TextStyle(
                            color: AppTheme.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Transform.scale(
                      scale: 0.75,
                      alignment: Alignment.centerLeft,
                      child: Switch(
                        value: listed,
                        activeThumbColor: AppTheme.gold,
                        onChanged: (value) => _handleToggleListed(context, value),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: AppTheme.textSecondary,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MerchantEditWatchScreen(
                                  watchId: watchId,
                                  data: data,
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: Colors.redAccent,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                          onPressed: () => _confirmDelete(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Future<void> _handleToggleListed(BuildContext context, bool value) async {
    try {
      await watchService.updateWatch(watchId, {'listedInCatalog': value});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value
                  ? '"${data['name']}" is now listed in the catalog.'
                  : '"${data['name']}" was unlisted from the catalog.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update listing: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Watch?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'This will permanently remove "${data['name']}" from the catalog.',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await watchService.deleteWatch(
        watchId,
        watchLabel: data['name'] as String? ?? watchId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Watch deleted.')),
        );
      }
    }
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}