import 'package:flutter/material.dart';
import '../../constants/watch_colors.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import 'merchant_edit_watch_screen.dart';

/// Read-only-ish watch details screen used by both the merchant and admin
/// catalogs. Same image/specs layout as the customer-facing detail screen,
/// but the action row is "Edit Details" / "Delete Watch" instead of the
/// customer's inquire/AR/chat actions, since merchants and admins are
/// managing the listing rather than shopping for it.
class MerchantWatchDetailScreen extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const MerchantWatchDetailScreen({
    super.key,
    required this.watchId,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final price = data['price'];
    final style = data['styleCategory'] as String? ?? '';
    final targetGender = data['targetGender'] as String?;
    final colorHexesRaw = (data['colorHexes'] as List?)?.cast<String>();
    final legacyColorHex = data['colorHex'] as String?;
    final colorHexes = (colorHexesRaw != null && colorHexesRaw.isNotEmpty)
        ? colorHexesRaw
        : (legacyColorHex != null ? [legacyColorHex] : const <String>[]);
    final caseDiameter = data['caseDiameterMm'];
    final caseThickness = data['caseThicknessMm'];
    final lugToLug = data['lugToLugMm'];
    final bandWidth = data['bandWidthMm'];
    final movementType = data['movementType'] as String? ?? '';
    final waterResistance = data['waterResistance'] as String? ?? '';
    final bandMaterial = data['bandMaterial'] as String? ?? '';
    final caseMaterial = data['caseMaterial'] as String? ?? '';
    final imageUrl = data['imageUrl'] as String? ?? '';
    final imageUrls = (data['imageUrls'] as List?)?.cast<String>() ?? [];
    final photoUrls = imageUrls.isNotEmpty
        ? imageUrls
        : (imageUrl.isNotEmpty ? [imageUrl] : <String>[]);
    final listed = data['listedInCatalog'] as bool? ?? false;
    final has3D = data['has3DModel'] as bool? ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WatchPhotoCarousel(imageUrls: photoUrls),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (brand.isNotEmpty)
                    Text(
                      brand.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontSize: 20),
                        ),
                      ),
                      if (price != null)
                        Text(
                          'PHP $price',
                          style: const TextStyle(
                            color: AppTheme.gold,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _statusChip(listed ? 'ACTIVE' : 'DRAFT',
                          listed ? Colors.greenAccent : AppTheme.textSecondary),
                      _statusChip(has3D ? 'AR' : 'NO 3D',
                          has3D ? AppTheme.gold : AppTheme.textSecondary),
                      if (style.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            style.toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      // Unlike the customer-facing screen, an unset gender
                      // is flagged here rather than just omitted — this is
                      // the merchant's own view of their listing, so it
                      // should surface gaps that need filling in, not hide
                      // them.
                      if (targetGender != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            targetGender.toUpperCase(),
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else
                        _statusChip('GENDER NOT SET', Colors.orangeAccent),
                      if (colorHexes.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final hex in colorHexes.take(3))
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: hexToColor(hex),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white24,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                              // Same plain-language lookup the chatbot
                              // uses, so a merchant sees a watch's color
                              // described the same way a customer (or
                              // the AI) would.
                              Text(
                                colorHexes
                                    .take(3)
                                    .map((hex) =>
                                        paletteNameForHex(hex) ??
                                        describeHexColor(hex))
                                    .join(' / '),
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Specifications',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (caseDiameter != null)
                          _specRow('Case Diameter', '${caseDiameter}mm'),
                        if (caseThickness != null)
                          _specRow('Case Thickness', '${caseThickness}mm'),
                        if (lugToLug != null)
                          _specRow('Lug-to-Lug', '${lugToLug}mm'),
                        if (bandWidth != null)
                          _specRow('Band Width', '${bandWidth}mm'),
                        if (bandMaterial.isNotEmpty)
                          _specRow('Band Material', bandMaterial),
                        if (caseMaterial.isNotEmpty)
                          _specRow('Case Material', caseMaterial),
                        if (movementType.isNotEmpty)
                          _specRow('Movement', movementType),
                        if (waterResistance.isNotEmpty)
                          _specRow('Water Resistance', waterResistance,
                              isLast: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.gold,
                        foregroundColor: const Color(0xFF0E1A2B),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
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
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit Details'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => _confirmDelete(context),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Watch'),
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
      await WatchService().deleteWatch(
        watchId,
        watchLabel: data['name'] as String? ?? watchId,
      );
      if (context.mounted) {
        // Pop the details screen too — it was showing a watch that no
        // longer exists.
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Watch deleted.')),
        );
      }
    }
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _specRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipeable photo carousel for the merchant/admin watch detail screen.
/// Falls back to the generic watch icon if the watch has no photos on
/// file at all.
class _WatchPhotoCarousel extends StatefulWidget {
  final List<String> imageUrls;

  const _WatchPhotoCarousel({required this.imageUrls});

  @override
  State<_WatchPhotoCarousel> createState() => _WatchPhotoCarouselState();
}

class _WatchPhotoCarouselState extends State<_WatchPhotoCarousel> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.imageUrls;

    return AspectRatio(
      aspectRatio: 1.1,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photos.isEmpty)
            Container(
              color: AppTheme.surface,
              child: const Center(
                child: Icon(Icons.watch, size: 100, color: AppTheme.gold),
              ),
            )
          else
            PageView.builder(
              controller: _pageController,
              itemCount: photos.length,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemBuilder: (context, index) {
                return Container(
                  color: AppTheme.surface,
                  child: Image.network(
                    photos[index],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.watch, size: 100, color: AppTheme.gold),
                    ),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                );
              },
            ),
          if (photos.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(photos.length, (index) {
                  final isActive = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppTheme.gold
                          : Colors.white.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}