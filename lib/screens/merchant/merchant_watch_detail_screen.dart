import 'package:flutter/material.dart';
import '../../utils/ar_readiness.dart';
import '../../theme/app_theme.dart';
import '../../widgets/delete_watch.dart';
import '../../widgets/luxe.dart';
import '../../widgets/watch_detail_parts.dart';
import 'merchant_catalog_tab.dart' show missingWatchFields;
import 'merchant_edit_watch_screen.dart';

/// A watch as its owner sees it, used by both the merchant and admin
/// catalogs. Same layout as the customer detail screen, with the listing
/// status and edit/delete actions in place of matching, AR and chat.
class MerchantWatchDetailScreen extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;

  /// Hero tag of the photo tapped on the previous screen, so it can fly
  /// into this screen's first photo. Null means no animation.
  final String? heroTag;

  const MerchantWatchDetailScreen({
    super.key,
    required this.watchId,
    required this.data,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final listed = data['listedInCatalog'] as bool? ?? false;
    final has3D = data['has3DModel'] as bool? ?? false;
    final arReady = isArReady(data);
    final missing = missingWatchFields(data);

    return Scaffold(
      appBar: AppBar(
        title: Text('Watch Detail', style: AppTheme.serif(size: 28)),
        centerTitle: true,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            WatchPhotoCarousel(imageUrls: watchPhotos(data), heroTag: heroTag),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WatchHeadline(data),
                  const SizedBox(height: 24),
                  luxeSection(
                    'LISTING',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(listed ? 'Listed' : 'Draft',
                            style: AppTheme.serif(size: 26)),
                        const SizedBox(height: 4),
                        Text(
                          listed
                              ? 'Visible to customers in the catalog.'
                              : 'Hidden from customers until you list it.',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        _line(
                            arReady,
                            arReady
                                ? 'AR try-on is available'
                                : has3D
                                    ? '3D model uploaded, AR fit pending review'
                                    : 'No 3D model, so AR try-on is unavailable'),
                        _line(
                            missing.isEmpty,
                            missing.isEmpty
                                ? 'Key details are filled in'
                                : 'Missing ${missing.join(', ')}'),
                      ],
                    ),
                  ),
                  watchSpecsSection(data),
                  const SizedBox(height: 12),
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14)),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => MerchantEditWatchScreen(
                                    watchId: watchId, data: data),
                              ),
                            ),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Edit details'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Tooltip(
                          message: 'Delete watch',
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppTheme.outline),
                              minimumSize: const Size(52, 0),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () => _delete(context),
                            child: Icon(Icons.delete_outline,
                                size: 20,
                                color:
                                    Colors.redAccent.withValues(alpha: 0.8)),
                          ),
                        ),
                      ],
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

  /// One status line: a check when [good], a dash when something is missing.
  Widget _line(bool good, String text) {
    final color = good ? AppTheme.textPrimary : AppTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(good ? Icons.check : Icons.remove,
                size: 15, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 13, height: 1.4)),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final deleted = await confirmDeleteWatch(context,
        watchId: watchId, name: data['name'] as String? ?? watchId);
    if (deleted && context.mounted) {
      // Leave too: this screen was showing a watch that no longer exists.
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Watch deleted.')));
    }
  }
}