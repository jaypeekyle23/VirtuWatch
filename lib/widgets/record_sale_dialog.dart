import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sales_service.dart';
import '../theme/app_theme.dart';
import '../utils/sales.dart';
import '../utils/stock.dart';
import 'luxe.dart';

/// Lets a merchant record a sale that happened OFF the platform (VirtuWatch
/// has no checkout), without leaving the screen they are on. Saving writes the
/// sale to the sales history and takes the units out of stock in one step (see
/// [SalesService.recordSale]).
///
/// Returns the [SaleReceipt] once the sale is saved, or null if the dialog was
/// cancelled. Port of RecordSaleDialog.vue.
Future<SaleReceipt?> showRecordSaleDialog(
  BuildContext context, {
  required String watchId,
  required Map<String, dynamic> data,
}) {
  return showDialog<SaleReceipt>(
    context: context,
    builder: (_) => _RecordSaleDialog(watchId: watchId, data: data),
  );
}

class _RecordSaleDialog extends StatefulWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const _RecordSaleDialog({required this.watchId, required this.data});

  @override
  State<_RecordSaleDialog> createState() => _RecordSaleDialogState();
}

class _RecordSaleDialogState extends State<_RecordSaleDialog> {
  late final _quantity = TextEditingController(text: '1');
  late final _price = TextEditingController(
    text: _initialPrice(widget.data['price']),
  );
  final _buyer = TextEditingController();
  final _notes = TextEditingController();

  DateTime _day = DateTime.now();
  String _method = paymentMethods.first;

  bool _saving = false;
  bool _submitted = false; // field errors only show after the first Save
  String? _error;

  static String _initialPrice(Object? price) {
    if (price is! num) return '';
    return price == price.truncate() ? '${price.truncate()}' : '$price';
  }

  @override
  void dispose() {
    _quantity.dispose();
    _price.dispose();
    _buyer.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// The watch's count, or null when the merchant never entered one.
  int? get _stock => stockOf(widget.data);

  int? get _quantityValue => int.tryParse(_quantity.text.trim());

  double? get _priceValue =>
      double.tryParse(_price.text.replaceAll(',', '').trim());

  Map<String, String> get _errors => validateSaleInput(
        quantity: _quantityValue,
        unitPrice: _priceValue,
        soldAt: soldAtFromDay(_day),
        paymentMethod: _method,
        buyerName: _buyer.text,
        notes: _notes.text,
        stock: _stock,
      );

  String? _shown(String field) => _submitted ? _errors[field] : null;

  void _setQuantity(int value) {
    final stock = _stock;
    final max = stock == null
        ? maxSaleQuantity
        : (stock < maxSaleQuantity ? stock : maxSaleQuantity);
    final next = value.clamp(1, max < 1 ? 1 : max);
    setState(() {
      _quantity.text = '$next';
      _quantity.selection =
          TextSelection.collapsed(offset: _quantity.text.length);
    });
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isAfter(now) ? now : _day,
      firstDate: DateTime(2020),
      lastDate: now,
    );
    if (picked != null) setState(() => _day = picked);
  }

  String get _stockNote {
    final stock = _stock;
    if (stock == null) return "No stock count is on file, so stock won't change.";
    if (stock == 0) {
      return 'Out of stock. Update the stock first if you still have units.';
    }
    final q = _quantityValue;
    if (q == null || q > stock) return '$stock in stock.';
    return '$stock in stock, ${stock - q} left after this sale.';
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    if (_errors.isNotEmpty) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final receipt = await SalesService().recordSale(
        watchId: widget.watchId,
        quantity: _quantityValue!,
        unitPrice: _priceValue!,
        soldAt: soldAtFromDay(_day),
        paymentMethod: _method,
        buyerName: _buyer.text,
        notes: _notes.text,
      );
      if (mounted) Navigator.of(context).pop(receipt);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = saleErrorMessage(
              e, 'Could not record the sale. Please try again.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quantityValue;
    final price = _priceValue;
    final total = (q != null && price != null) ? saleTotal(price, q) : null;
    final muted = TextStyle(color: AppTheme.textSecondary, fontSize: 12);

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Record a sale', style: AppTheme.serif(size: 22)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.data['name'] as String? ?? 'Unnamed Watch',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
            const SizedBox(height: 6),
            Text(
              'For a sale that already happened outside VirtuWatch. It is '
              'added to your sales history and taken out of stock.',
              style: muted,
            ),
            const SizedBox(height: 16),

            // Quantity
            Text('QUANTITY SOLD', style: kLabelStyle),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'One less',
                  onPressed: _saving ? null : () => _setQuantity((q ?? 2) - 1),
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 84,
                  child: TextField(
                    controller: _quantity,
                    enabled: !_saving,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    style: AppTheme.serif(size: 30),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                IconButton(
                  tooltip: 'One more',
                  onPressed: _saving ? null : () => _setQuantity((q ?? 0) + 1),
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Center(child: Text(_stockNote, style: muted)),
            if (_shown('quantity') != null)
              Center(
                child: Text(_shown('quantity')!,
                    style: const TextStyle(
                        color: Colors.redAccent, fontSize: 12)),
              ),
            const SizedBox(height: 16),

            // Price and total
            TextField(
              controller: _price,
              enabled: !_saving,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                LengthLimitingTextInputFormatter(12),
              ],
              decoration: InputDecoration(
                labelText: 'Price per unit (PHP)',
                helperText: 'Filled in from your listing. Change it if you '
                    'sold at a discount.',
                helperMaxLines: 2,
                errorText: _shown('unitPrice'),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Total', style: TextStyle(color: AppTheme.textSecondary)),
                const Spacer(),
                Text(total == null ? '–' : formatSaleMoney(total),
                    style: AppTheme.serif(size: 24)),
              ],
            ),
            const SizedBox(height: 16),

            // Date
            Text('DATE SOLD', style: kLabelStyle),
            InkWell(
              onTap: _saving ? null : _pickDay,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_day.year}-${_day.month.toString().padLeft(2, '0')}-${_day.day.toString().padLeft(2, '0')}',
                        style: TextStyle(color: AppTheme.textPrimary),
                      ),
                    ),
                    Icon(Icons.calendar_today_outlined,
                        size: 18, color: AppTheme.textSecondary),
                  ],
                ),
              ),
            ),
            if (_shown('soldAt') != null)
              Text(_shown('soldAt')!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            const SizedBox(height: 8),

            // Payment method
            Text('PAID VIA', style: kLabelStyle),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in paymentMethods)
                  luxePill(
                    method,
                    selected: _method == method,
                    onTap: () {
                      if (!_saving) setState(() => _method = method);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Optional details
            TextField(
              controller: _buyer,
              enabled: !_saving,
              maxLength: maxBuyerLength,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Buyer (optional)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
              enabled: !_saving,
              maxLength: maxNotesLength,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Reference number, meet-up details, etc.',
                counterText: '',
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: (_saving || _stock == 0) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Record sale'),
        ),
      ],
    );
  }
}
