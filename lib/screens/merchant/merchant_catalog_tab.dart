import 'dart:math' show max, min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/catalog_filter_sheet.dart';
import '../../widgets/delete_watch.dart';
import '../../widgets/luxe.dart';
import '../../widgets/watch_tile.dart';
import 'merchant_add_watch_screen.dart';
import 'merchant_edit_watch_screen.dart';
import 'merchant_watch_detail_screen.dart';

TextStyle get _muted =>

    TextStyle(color: AppTheme.textSecondary, fontSize: 13);

/// Which fields this watch is missing that the recommendation engine and
/// chatbot actually rely on: gender (informational, but customer-facing
/// via the catalog filter and chat), color (feeds the color-match score
/// and is what the chatbot describes), and lug-to-lug (feeds the fit
/// score — the single biggest weighted signal at 55%). Deliberately
/// narrower than "every empty field" — this flags gaps that actually
/// degrade what the customer sees or what the AI can honestly answer,
/// not cosmetic specs like water resistance.
List<String> missingWatchFields(Map<String, dynamic> data) {
  final missing = <String>[];
  if (data['targetGender'] == null) missing.add('Gender');
  final colorHex = data['colorHex'] as String?;
  final colorHexes = (data['colorHexes'] as List?)?.cast<String>();
  if (colorHex == null && (colorHexes == null || colorHexes.isEmpty)) {
    missing.add('Color');
  }
  if (data['lugToLugMm'] == null) missing.add('Lug-to-Lug');
  return missing;
}

class MerchantCatalogTab extends StatefulWidget {
  const MerchantCatalogTab({super.key});

  @override
  State<MerchantCatalogTab> createState() => _MerchantCatalogTabState();
}

class _MerchantCatalogTabState extends State<MerchantCatalogTab> {
  static const _styleOptions = ['Classic', 'Sport', 'Luxury', 'Casual'];

  final _watchService = WatchService();
  final _searchController = TextEditingController();

  // Created once, so rebuilds don't re-subscribe and swap the list for
  // loading placeholders.
  late final _watches = _watchService.myWatches();

  // Keeps photo Hero tags unique to this copy of the screen, so photos
  // never fly between it and another copy of the catalog.
  late final _heroScope = 'merchant-catalog-$hashCode';

  String _searchQuery = '';
  CatalogFilters _filters = const CatalogFilters();
  CatalogSort _sort = CatalogSort.newest;
  // "Needs info" is a merchant-only data-completeness tool, not a catalog
  // filter a customer would use, so it stays out of the shared CatalogFilters.
  bool _needsInfoOnly = false;
  bool _isMultiColumn = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _watches,
      builder: (context, snapshot) {
        final allDocs = snapshot.data?.docs ?? <WatchDoc>[];
        final brands = {
          for (final d in allDocs)
            if ((d.data()['brand'] as String? ?? '').isNotEmpty)
              d.data()['brand'] as String,
        }.toList()
          ..sort();
        final prices = [
          for (final d in allDocs)
            if (d.data()['price'] is num) (d.data()['price'] as num).toDouble(),
        ];
        // Counted over the whole catalog, whatever filters are applied.
        final incomplete = allDocs
            .where((d) => missingWatchFields(d.data()).isNotEmpty)
            .length;
        final docs = sortWatchDocs(allDocs.where(_matches).toList(), _sort);

        return Scaffold(
          appBar: AppBar(
            title: Text('My Catalog', style: AppTheme.serif(size: 28)),
            actions: [
              CatalogFilterButton(
                activeCount: _filters.activeCount,
                onPressed: () async {
                  final result = await showCatalogFilterSheet(
                    context,
                    initial: _filters,
                    styleOptions: _styleOptions,
                    brandOptions: brands,
                    priceFloor: prices.isEmpty ? 0.0 : prices.reduce(min),
                    priceCeiling: prices.isEmpty ? 0.0 : prices.reduce(max),
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
              CatalogSortButton(
                selected: _sort,
                onSelected: (sort) => setState(() => _sort = sort),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: 'Add watch',
                onPressed: () => _open(const MerchantAddWatchScreen()),
              ),
            ],
          ),
          body: Column(
            children: [
              CatalogSearchField(
                controller: _searchController,
                onChanged: (value) =>
                    setState(() => _searchQuery = value.toLowerCase()),
              ),
              if (incomplete > 0) _needsInfoBar(incomplete),
              Expanded(child: _body(snapshot, docs)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snapshot,
      List<WatchDoc> docs) {
    if (snapshot.hasError) {
      return Center(
        child: Text(
          'Error loading catalog: ${snapshot.error}',
          style: const TextStyle(color: Colors.redAccent),
          textAlign: TextAlign.center,
        ),
      );
    }
    final loading =
        snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData;
    if (!loading && docs.isEmpty) {
      final unfiltered =
          _filters.isDefault && _searchQuery.isEmpty && !_needsInfoOnly;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            unfiltered
                ? 'No watches yet. Tap + to add your first one.'
                : 'No watches match your search or filters.',
            style: _muted,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Placeholders match the active view, so the layout doesn't change
    // shape when the data arrives.
    final List<Widget> tiles = loading
        ? [
            for (var i = 0; i < 6; i++)
              _isMultiColumn
                  ? const WatchTileSkeleton(showPrice: true, showFooter: true)
                  : const WatchListTileSkeleton(showFooter: true),
          ]
        : [for (final doc in docs) _tile(doc)];

    return ListView(
      physics: loading ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: _isMultiColumn
          ? watchGridRows(tiles)
          : [
              for (final tile in tiles)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12), child: tile),
            ],
    );
  }

  Widget _tile(WatchDoc doc) {
    final id = doc.id;
    final data = doc.data();
    void open(String heroTag) => _open(
        MerchantWatchDetailScreen(watchId: id, data: data, heroTag: heroTag));
    final footer = _footer(id, data);

    return _isMultiColumn
        ? WatchTile(
            watchId: id,
            data: data,
            heroScope: _heroScope,
            showPrice: true,
            onTap: open,
            footer: footer)
        : WatchListTile(
            watchId: id,
            data: data,
            heroScope: _heroScope,
            onTap: open,
            footer: footer);
  }

  /// Listing status, a flag when key data is missing, and the actions menu.
  Widget _footer(String id, Map<String, dynamic> data) {
    final listed = data['listedInCatalog'] as bool? ?? false;
    final missing = missingWatchFields(data);

    PopupMenuItem<String> item(String value, String label, {Color? color}) =>
        PopupMenuItem(
          value: value,
          child: Text(label,
              style: TextStyle(
                  color: color ?? AppTheme.textPrimary, fontSize: 14)),
        );

    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Text(listed ? 'LISTED' : 'DRAFT',
              style: kLabelStyle.copyWith(
                  color:
                      listed ? AppTheme.textPrimary : AppTheme.textSecondary)),
          if (missing.isNotEmpty)
            Tooltip(
              message: 'Missing: ${missing.join(', ')}',
              child: const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(Icons.error_outline,
                    size: 14, color: Colors.orangeAccent),
              ),
            ),
          const Spacer(),
          SizedBox(
            width: 28,
            height: 28,
            child: PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz,
                  size: 18, color: AppTheme.textSecondary),
              padding: EdgeInsets.zero,
              color: AppTheme.surface,
              onSelected: (action) {
                switch (action) {
                  case 'edit':
                    _open(MerchantEditWatchScreen(watchId: id, data: data));
                  case 'toggle':
                    _toggleListed(id, data);
                  default:
                    _confirmDelete(id, data);
                }
              },
              itemBuilder: (context) => [
                item('edit', 'Edit'),
                item('toggle', listed ? 'Unlist' : 'List in catalog'),
                item('delete', 'Delete', color: Colors.redAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Strip under the search field. Shown only while some watch is missing
  /// gender, color or lug-to-lug data (see [missingWatchFields]); tapping it
  /// toggles between those watches and everything, so a large catalog's gaps
  /// can be found without opening every watch.
  Widget _needsInfoBar(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: InkWell(
        onTap: () => setState(() => _needsInfoOnly = !_needsInfoOnly),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.symmetric(
                horizontal: BorderSide(color: AppTheme.hairline)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${count == 1 ? '1 watch is' : '$count watches are'} '
                  'missing gender, color or fit data.',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
              const SizedBox(width: 12),
              Text(_needsInfoOnly ? 'SHOW ALL' : 'REVIEW',
                  style: kLabelStyle.copyWith(color: AppTheme.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }

  bool _matches(WatchDoc doc) {
    final data = doc.data();
    if (!_filters.matches(data)) return false;
    if (_needsInfoOnly && missingWatchFields(data).isEmpty) return false;
    if (_searchQuery.isEmpty) return true;
    return ['name', 'brand', 'styleCategory'].any((key) =>
        (data[key] as String? ?? '').toLowerCase().contains(_searchQuery));
  }

  Future<void> _toggleListed(String id, Map<String, dynamic> data) async {
    final listed = !(data['listedInCatalog'] as bool? ?? false);
    try {
      await _watchService.updateWatch(id, {'listedInCatalog': listed});
      _snack(listed
          ? '"${data['name']}" is now listed in the catalog.'
          : '"${data['name']}" was unlisted from the catalog.');
    } catch (e) {
      _snack('Could not update listing: $e');
    }
  }

  Future<void> _confirmDelete(String id, Map<String, dynamic> data) async {
    final deleted = await confirmDeleteWatch(context,
        watchId: id, name: data['name'] as String? ?? id);
    if (deleted) _snack('Watch deleted.');
  }
}