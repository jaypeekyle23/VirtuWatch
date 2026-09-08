import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
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
  String _selectedFilter = 'All';
  _SortOption _sortOption = _SortOption.newest;

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
        title: const Text('Watch Catalog'),
        actions: [
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
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _watchService.allListedWatches(),
              builder: (context, snapshot) {
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
                    child: Text(
                      'No watches found.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: 16, top: 4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.58,
                    ),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      return _WatchCard(watchId: doc.id, data: data);
                    },
                  ),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}