import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/sales_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/format.dart';
import '../../utils/sales.dart';
import '../../widgets/luxe.dart';

/// The merchant's sales history: every sale they recorded by hand (VirtuWatch
/// has no checkout), with revenue and unit totals for whatever is filtered.
/// A sale is never deleted; a mistake is voided and stays in the list, marked
/// as voided and left out of the totals. Port of MerchantSalesView.vue.
class MerchantSalesTab extends StatefulWidget {
  const MerchantSalesTab({super.key});

  @override
  State<MerchantSalesTab> createState() => _MerchantSalesTabState();
}

class _MerchantSalesTabState extends State<MerchantSalesTab> {
  static const _pageSize = 20;
  static const _anyMethod = 'any';

  final _salesService = SalesService();
  final _searchController = TextEditingController();

  // Created once, so rebuilds don't re-subscribe and flash a loader.
  late final _sales = _salesService.mySales();

  String _search = '';
  SalePreset _preset = SalePreset.all;
  String _method = _anyMethod;
  bool _showVoided = false;
  int _visibleCount = _pageSize;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  bool get _filtersActive =>
      _search.isNotEmpty ||
      _preset != SalePreset.all ||
      _method != _anyMethod ||
      _showVoided;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _preset = SalePreset.all;
      _method = _anyMethod;
      _showVoided = false;
      _visibleCount = _pageSize;
    });
  }

  Future<void> _confirmVoid(Map<String, dynamic> sale) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _VoidSaleDialog(sale: sale),
    );
    if (reason == null) return; // cancelled
    try {
      final restored =
          await _salesService.voidSale(sale['id'] as String, reason: reason);
      _snack(restored
          ? 'Sale voided. The units are back in stock.'
          : 'Sale voided.');
    } catch (e) {
      _snack(saleErrorMessage(e, 'Could not void the sale. Please try again.'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _sales,
          builder: (context, snap) {
            final docs = snap.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            final List<Map<String, dynamic>> sales = [
              for (final doc in docs) {'id': doc.id, ...doc.data()},
            ];
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Text('Sales history', style: AppTheme.serif(size: 32)),
                const SizedBox(height: 6),
                ..._body(snap, sales),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _body(
    AsyncSnapshot<QuerySnapshot<Map<String, dynamic>>> snap,
    List<Map<String, dynamic>> sales,
  ) {
    if (snap.hasError) {
      return [
        const SizedBox(height: 24),
        Text('Could not load your sales history.',
            style: TextStyle(color: AppTheme.textSecondary)),
      ];
    }
    if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
      return const [
        SizedBox(height: 48),
        Center(child: CircularProgressIndicator()),
      ];
    }
    if (sales.isEmpty) {
      return [
        const SizedBox(height: 40),
        Center(child: Text('No sales recorded yet', style: AppTheme.serif(size: 22))),
        const SizedBox(height: 8),
        Text(
          "VirtuWatch doesn't take payments, so when you sell a watch (in "
          'person, by message or online), record it from your catalog: open '
          'a watch\'s menu and choose Record sale. It is saved here and the '
          'stock goes down with it.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ];
    }

    final range = presetRange(_preset, DateTime.now());
    final visible = sortSalesNewestFirst(filterSales(
      sales,
      search: _search,
      from: range.from,
      to: range.to,
      paymentMethod: _method == _anyMethod ? null : _method,
      includeVoided: _showVoided,
    ));
    final totals = salesTotals(visible);
    final allCount = sales.where((s) => !isVoidedSale(s)).length;
    final shown = visible.take(_visibleCount).toList();

    return [
      Text(
        totals.count == allCount
            ? '$allCount ${allCount == 1 ? 'sale' : 'sales'} recorded'
            : '${totals.count} of $allCount sales',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      ),
      const SizedBox(height: 16),
      luxeBand([
        _stat('REVENUE', formatSaleMoney(totals.revenue)),
        _stat('UNITS SOLD', '${totals.units}'),
        _stat('SALES', '${totals.count}'),
      ]),
      if (totals.voided > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${totals.voided} voided ${totals.voided == 1 ? 'sale is' : 'sales are'} '
            'shown below and left out of these totals.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      const SizedBox(height: 16),

      // Search
      TextField(
        controller: _searchController,
        onChanged: (value) => setState(() {
          _search = value.trim();
          _visibleCount = _pageSize;
        }),
        decoration: luxeFieldDecoration(
          hint: 'Search watch, brand, buyer or note',
          prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.textSecondary),
        ),
      ),
      const SizedBox(height: 14),

      // Date range
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final preset in SalePreset.values)
            luxePill(
              presetLabel(preset),
              selected: _preset == preset,
              onTap: () => setState(() {
                _preset = preset;
                _visibleCount = _pageSize;
              }),
            ),
        ],
      ),
      const SizedBox(height: 10),

      // Payment method, voided toggle, clear
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          PopupMenuButton<String>(
            color: AppTheme.surface,
            onSelected: (value) => setState(() {
              _method = value;
              _visibleCount = _pageSize;
            }),
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: _anyMethod,
                  child: Text('Any method',
                      style: TextStyle(color: AppTheme.textPrimary))),
              for (final method in paymentMethods)
                PopupMenuItem(
                    value: method,
                    child: Text(method,
                        style: TextStyle(color: AppTheme.textPrimary))),
            ],
            child: IgnorePointer(
              child: luxePill(
                _method == _anyMethod ? 'Paid via: any' : 'Paid via: $_method',
                selected: _method != _anyMethod,
                onTap: () {},
              ),
            ),
          ),
          luxePill(
            'Show voided',
            selected: _showVoided,
            onTap: () => setState(() {
              _showVoided = !_showVoided;
              _visibleCount = _pageSize;
            }),
          ),
          if (_filtersActive)
            TextButton(onPressed: _clearFilters, child: const Text('Clear')),
        ],
      ),
      const SizedBox(height: 12),

      if (visible.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text('No sales match your search or filters.',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
        )
      else ...[
        for (final sale in shown) _row(sale),
        if (visible.length > shown.length)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Center(
              child: TextButton(
                onPressed: () => setState(() => _visibleCount += _pageSize),
                child: Text('Show more (${visible.length - shown.length} left)'),
              ),
            ),
          ),
      ],
    ];
  }

  Widget _stat(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value, style: AppTheme.serif(size: 24)),
            ),
            const SizedBox(height: 2),
            Text(label, style: kLabelStyle),
          ],
        ),
      );

  Widget _row(Map<String, dynamic> sale) {
    final voided = isVoidedSale(sale);
    final brand = sale['watchBrand'] as String? ?? '';
    final image = sale['watchImageUrl'] as String? ?? '';
    final buyer = sale['buyerName'] as String? ?? '';
    final notes = sale['notes'] as String? ?? '';
    final reason = sale['voidReason'] as String? ?? '';
    final date = saleDate(sale);
    final unitPrice = sale['unitPrice'];
    final total = sale['totalAmount'];
    final fallback = Center(
      child: Icon(Icons.watch, size: 22, color: AppTheme.textSecondary),
    );

    final details = [
      '${sale['quantity']} × ${unitPrice is num ? formatSaleMoney(unitPrice) : '–'}',
      if (sale['paymentMethod'] is String) sale['paymentMethod'] as String,
    ].join('  ·  ');

    return Opacity(
      opacity: voided ? 0.6 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(6),
              ),
              child: image.isEmpty
                  ? fallback
                  : Image.network(image,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => fallback),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(brand.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: kLabelStyle.copyWith(fontSize: 10)),
                  Text(sale['watchName'] as String? ?? 'Unnamed watch',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(details,
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 12)),
                  if (buyer.isNotEmpty)
                    Text('Buyer: $buyer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  if (notes.isNotEmpty)
                    Text(notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                  if (voided && reason.isNotEmpty)
                    Text('Void reason: $reason',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  total is num ? formatSaleMoney(total) : '–',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    decoration: voided ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(date == null ? '' : formatDate(date),
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 4),
                if (voided)
                  Text('VOIDED',
                      style: kLabelStyle.copyWith(color: Colors.redAccent))
                else
                  InkWell(
                    onTap: () => _confirmVoid(sale),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('VOID', style: kLabelStyle),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks before voiding a sale, with an optional reason. Pops the reason (empty
/// when none was typed) on confirm, or null on cancel.
class _VoidSaleDialog extends StatefulWidget {
  final Map<String, dynamic> sale;

  const _VoidSaleDialog({required this.sale});

  @override
  State<_VoidSaleDialog> createState() => _VoidSaleDialogState();
}

class _VoidSaleDialogState extends State<_VoidSaleDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sale = widget.sale;
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Void this sale?', style: AppTheme.serif(size: 22)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${sale['quantity']} × ${sale['watchName']} will stay in your '
            'history, marked as voided, and leave your totals. Any units it '
            "took out of stock go back in. This can't be undone.",
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reason,
            maxLength: maxVoidReasonLength,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
              hintText: 'e.g. Recorded twice by mistake',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: const Text('Void sale',
              style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    );
  }
}
