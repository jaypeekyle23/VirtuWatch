import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/watch_service.dart';
import '../theme/app_theme.dart';
import '../utils/stock.dart';

// Solid fills, so the badge stays readable on top of any watch photo and in
// every theme.
const Color _outFill = Color(0xFFC62828);
const Color _lowFill = Color(0xFFF9A825);

/// Small pill for a watch that is low or out of stock. Shown in the corner of
/// a tile photo (see [withStockOverlay]).
class StockBadge extends StatelessWidget {
  final StockStatus status;
  final int? count;

  const StockBadge({super.key, required this.status, this.count});

  @override
  Widget build(BuildContext context) {
    final out = status == StockStatus.out;
    final text =
        out ? 'OUT OF STOCK' : (count == 1 ? 'ONLY 1 LEFT' : 'ONLY $count LEFT');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: out ? _outFill : _lowFill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(
          color: out ? Colors.white : Colors.black87,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Puts a [StockBadge] in the top-left corner of [photo] when the watch in
/// [data] is low or out of stock. An out-of-stock photo is also dimmed. Any
/// other watch gets [photo] back unchanged, so tiles keep their size.
///
/// [photo] must fill its parent (it sits in a sized box in every tile).
Widget withStockOverlay(Widget photo, Map<String, dynamic> data,
    {double inset = 8}) {
  final status = stockStatus(data);
  if (status != StockStatus.out && status != StockStatus.low) return photo;
  return Stack(
    fit: StackFit.expand,
    children: [
      photo,
      if (status == StockStatus.out)
        ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
      Positioned(
        left: inset,
        top: inset,
        child: StockBadge(status: status, count: stockOf(data)),
      ),
    ],
  );
}

/// One line of availability for the customer detail screen: a colored dot and
/// "In stock", "Only 2 left" or "Out of stock". Draws nothing when the seller
/// has not entered a count.
class StockStatusLine extends StatelessWidget {
  final Map<String, dynamic> data;

  const StockStatusLine(this.data, {super.key});

  @override
  Widget build(BuildContext context) {
    final label = customerStockLabel(data);
    if (label == null) return const SizedBox.shrink();
    final color = switch (stockStatus(data)) {
      StockStatus.out => Colors.redAccent,
      StockStatus.low => Colors.orangeAccent,
      _ => AppTheme.textSecondary,
    };
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Lets a merchant (or admin) change one watch's stock count without opening
/// the full edit form. Returns true when a new count was saved.
Future<bool> showStockDialog(
  BuildContext context, {
  required String watchId,
  required Map<String, dynamic> data,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => _StockDialog(watchId: watchId, data: data),
  );
  return saved ?? false;
}

class _StockDialog extends StatefulWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const _StockDialog({required this.watchId, required this.data});

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  static const _maxCount = 99999;

  late final _controller =
      TextEditingController(text: '${stockOf(widget.data) ?? 0}');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _count => int.tryParse(_controller.text.trim());

  void _set(int value) {
    final next = value.clamp(0, _maxCount);
    setState(() {
      _controller.text = '$next';
      _controller.selection =
          TextSelection.collapsed(offset: _controller.text.length);
    });
  }

  Future<void> _save() async {
    final count = _count;
    if (count == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await WatchService().updateWatch(widget.watchId, {'stock': count});
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    final preview = count == null ? null : merchantStockLabel({'stock': count});

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Text('Update stock', style: AppTheme.serif(size: 22)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.data['name'] as String? ?? 'Unnamed Watch',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'One less',
                onPressed: _saving ? null : () => _set((count ?? 0) - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _controller,
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
                onPressed: _saving ? null : () => _set((count ?? 0) + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          if (preview != null) ...[
            const SizedBox(height: 4),
            Center(
              child: Text(preview,
                  style:
                      TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: _saving ? null : () => _set(0),
              child: const Text('Mark as out of stock'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: (_saving || count == null) ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
