import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import 'merchant_add_watch_screen.dart';
import 'merchant_edit_watch_screen.dart';
import 'merchant_watch_detail_screen.dart';

enum _SortOption {
  newest('Newest'),
  priceLowToHigh('Price: Low to High'),
  priceHighToLow('Price: High to Low'),
  nameAToZ('Name: A to Z');

  final String label;
  const _SortOption(this.label);
}

class MerchantCatalogTab extends StatefulWidget {
  const MerchantCatalogTab({super.key});

  @override
  State<MerchantCatalogTab> createState() => _MerchantCatalogTabState();
}

class _MerchantCatalogTabState extends State<MerchantCatalogTab> {
  final _watchService = WatchService();
  final _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedFilter = 'All';
  _SortOption _sortOption = _SortOption.newest;
  // Multi-column grid is the default; the toggle in the app bar lets the
  // merchant switch to the original single-column list instead.
  bool _isMultiColumn = true;

  final List<String> _filters = ['All', 'Classic', 'Sport', 'Luxury', 'Casual'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Catalog'),
        actions: [
          IconButton(
            icon: Icon(_isMultiColumn ? Icons.view_agenda_outlined : Icons.grid_view),
            tooltip: _isMultiColumn ? 'Switch to list view' : 'Switch to grid view',
            onPressed: () => setState(() => _isMultiColumn = !_isMultiColumn),
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
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MerchantAddWatchScreen(),
                ),
              );
            },
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
                prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
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
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedFilter = filter),
                  backgroundColor: AppTheme.surface,
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
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _watchService.myWatches(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading catalog: ${snapshot.error}',
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var docs = snapshot.data?.docs ?? [];

                if (_selectedFilter != 'All') {
                  docs = docs
                      .where((d) => d.data()['styleCategory'] == _selectedFilter)
                      .toList();
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

                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.watch_outlined,
                              size: 48, color: AppTheme.textSecondary),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty && _selectedFilter == 'All'
                                ? 'No watches yet. Tap + to add your first one.'
                                : 'No watches match your search or filter.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
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
                        childAspectRatio: 0.62,
                      ),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final doc = docs[index];
                        final data = doc.data();
                        return _WatchGridCard(
                          watchId: doc.id,
                          data: data,
                          watchService: _watchService,
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
                    final data = doc.data();
                    return _WatchListTile(
                      watchId: doc.id,
                      data: data,
                      watchService: _watchService,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
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

class _WatchListTile extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;
  final WatchService watchService;

  const _WatchListTile({
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
                      maxLines: 1,
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

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Delete Watch?',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          'This will permanently remove "${data['name']}" from your catalog.',
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
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
/// Compact grid-cell version of the watch tile, shown when the catalog's
/// view toggle is set to grid mode (the default). Keeps the same listed
/// switch and edit/delete actions as the single-column list tile.
class _WatchGridCard extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;
  final WatchService watchService;

  const _WatchGridCard({
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
                Text(
                  brand.isNotEmpty ? '$brand $name' : name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _statusChip(listed ? 'ACTIVE' : 'DRAFT',
                        listed ? Colors.greenAccent : AppTheme.textSecondary),
                    _statusChip(has3D ? 'AR' : 'NO 3D',
                        has3D ? AppTheme.gold : AppTheme.textSecondary),
                  ],
                ),
                const SizedBox(height: 6),
                if (price != null)
                  Text(
                    'PHP $price',
                    style: const TextStyle(
                      color: AppTheme.gold,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                const SizedBox(height: 4),
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
          'This will permanently remove "${data['name']}" from your catalog.',
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