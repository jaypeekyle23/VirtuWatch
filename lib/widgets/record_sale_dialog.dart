import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/sales_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
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

  // ---------- Layout helpers ----------

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: kLabelStyle),
      );

  Widget _errorText(String? message) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(message,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
        );

  TextStyle get _fieldStyle =>
      TextStyle(color: AppTheme.textPrimary, fontSize: 15);

  /// A text-field lookalike for pickers (the date and the payment method):
  /// the same faint underline as the real fields, with an icon on the right.
  Widget _pickerBox(String text, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.outline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _fieldStyle),
            ),
            Icon(icon, size: 18, color: AppTheme.textSecondary),
          ],
        ),
      );

  Widget _stepButton(IconData icon, String tooltip, VoidCallback? onPressed) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        style: IconButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          side: BorderSide(color: AppTheme.outline),
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final q = _quantityValue;
    final price = _priceValue;
    final total = (q != null && price != null) ? saleTotal(price, q) : null;
    final muted = TextStyle(color: AppTheme.textSecondary, fontSize: 12);
    const gap = SizedBox(height: 20);

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Record a sale', style: AppTheme.serif(size: 24)),
          const SizedBox(height: 4),
          Text(
            widget.data['name'] as String? ?? 'Unnamed Watch',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'For a sale that already happened outside VirtuWatch. It is '
              'added to your sales history and taken out of stock.',
              style: muted.copyWith(height: 1.4),
            ),
            gap,

            // Quantity
            _label('QUANTITY SOLD'),
            const SizedBox(height: 4),
            Row(
              children: [
                _stepButton(Icons.remove, 'One less',
                    _saving ? null : () => _setQuantity((q ?? 2) - 1)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _quantity,
                    enabled: !_saving,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    style: AppTheme.serif(size: 28),
                    decoration: luxeFieldDecoration()
                        .copyWith(isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                _stepButton(Icons.add, 'One more',
                    _saving ? null : () => _setQuantity((q ?? 0) + 1)),
              ],
            ),
            const SizedBox(height: 8),
            Text(_stockNote, style: muted),
            _errorText(_shown('quantity')),
            gap,

            // Price and total
            _label('PRICE PER UNIT (PHP)'),
            TextField(
              controller: _price,
              enabled: !_saving,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                LengthLimitingTextInputFormatter(12),
              ],
              style: _fieldStyle,
              decoration: luxeFieldDecoration(hint: '0')
                  .copyWith(errorText: _shown('unitPrice')),
              onChanged: (_) => setState(() {}),
            ),
            if (_shown('unitPrice') == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('From your listing. Change it for a discount.',
                    style: muted),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Text('Total', style: TextStyle(color: AppTheme.textSecondary)),
                  const Spacer(),
                  Text(total == null ? '–' : formatSaleMoney(total),
                      style: AppTheme.serif(size: 22)),
                ],
              ),
            ),
            gap,

            // Date and payment method, side by side (like the web portal)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('DATE SOLD'),
                      InkWell(
                        onTap: _saving ? null : _pickDay,
                        child: _pickerBox(
                            formatDate(_day), Icons.calendar_today_outlined),
                      ),
                      _errorText(_shown('soldAt')),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('PAID VIA'),
                      PopupMenuButton<String>(
                        enabled: !_saving,
                        color: AppTheme.surface,
                        onSelected: (value) => setState(() => _method = value),
                        itemBuilder: (context) => [
                          for (final method in paymentMethods)
                            PopupMenuItem(
                              value: method,
                              child: Text(method,
                                  style: TextStyle(
                                      color: method == _method
                                          ? AppTheme.gold
                                          : AppTheme.textPrimary)),
                            ),
                        ],
                        child: _pickerBox(_method, Icons.arrow_drop_down),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            gap,

            // Optional details
            _label('BUYER (OPTIONAL)'),
            TextField(
              controller: _buyer,
              enabled: !_saving,
              maxLength: maxBuyerLength,
              textCapitalization: TextCapitalization.words,
              style: _fieldStyle,
              decoration: luxeFieldDecoration(hint: 'Name of the buyer')
                  .copyWith(counterText: ''),
            ),
            gap,
            _label('NOTES (OPTIONAL)'),
            TextField(
              controller: _notes,
              enabled: !_saving,
              maxLength: maxNotesLength,
              maxLines: 2,
              minLines: 1,
              style: _fieldStyle,
              decoration: luxeFieldDecoration(
                      hint: 'Reference number, meet-up details, etc.')
                  .copyWith(counterText: ''),
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
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
          child: Text('Cancel',
              style: TextStyle(color: AppTheme.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
          ),
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
