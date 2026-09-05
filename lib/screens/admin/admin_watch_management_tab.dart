import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../merchant/merchant_edit_watch_screen.dart';

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
        title: const Text('Watch Management'),
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
                hintText: 'Search watches by name or brand...',
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
              stream: FirebaseFirestore.instance
                  .collection('watches')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
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
                    return name.contains(_searchQuery) ||
                        brand.contains(_searchQuery);
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.watch, color: AppTheme.gold),
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
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (listed ? Colors.greenAccent : AppTheme.textSecondary)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        listed ? 'ACTIVE' : 'DRAFT',
                        style: TextStyle(
                          color: listed ? Colors.greenAccent : AppTheme.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (price != null)
                      Text(
                        'PHP $price',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: AppTheme.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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
              const SizedBox(height: 8),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.redAccent,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _confirmDelete(context),
              ),
            ],
          ),
        ],
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
      await watchService.deleteWatch(watchId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Watch deleted.')),
        );
      }
    }
  }
}