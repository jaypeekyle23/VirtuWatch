import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/watch_chat_sheet.dart';
import 'ar_try_on_screen.dart';

class WatchDetailScreen extends StatefulWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const WatchDetailScreen({
    super.key,
    required this.watchId,
    required this.data,
  });

  @override
  State<WatchDetailScreen> createState() => _WatchDetailScreenState();
}

class _WatchDetailScreenState extends State<WatchDetailScreen> {
  final _userService = UserService();

  // VirtuWatch doesn't process purchases in-app — Urbane Time handles
  // inquiries and sales themselves, so every watch routes here regardless
  // of which merchant listed it.
  static final Uri _urbaneTimeFacebookUrl =
      Uri.parse('https://www.facebook.com/urbanetime');

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: recording a view is a nice-to-have for the
    // "Recently Viewed" section and should never block or interrupt
    // someone looking at a watch's details, so failures are swallowed.
    _userService.recordRecentlyViewed(widget.watchId).catchError((_) {});
  }

  Future<void> _inquireViaFacebook(BuildContext context) async {
    try {
      final launched = await launchUrl(
        _urbaneTimeFacebookUrl,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Facebook. Please try again.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open Facebook. Please try again.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final watchId = widget.watchId;
    final data = widget.data;
    final name = data['name'] as String? ?? 'Unnamed Watch';
    final brand = data['brand'] as String? ?? '';
    final price = data['price'];
    final style = data['styleCategory'] as String? ?? '';
    final caseDiameter = data['caseDiameterMm'];
    final caseThickness = data['caseThicknessMm'];
    final lugToLug = data['lugToLugMm'];
    final bandWidth = data['bandWidthMm'];
    final movementType = data['movementType'] as String? ?? '';
    final waterResistance = data['waterResistance'] as String? ?? '';
    final bandMaterial = data['bandMaterial'] as String? ?? '';
    final caseMaterial = data['caseMaterial'] as String? ?? '';
    final imageUrl = data['imageUrl'] as String? ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _userService.currentUserStream(),
            builder: (context, snapshot) {
              final saved = (snapshot.data?.data()?['savedWatches'] as List?)
                      ?.cast<String>() ??
                  [];
              final isSaved = saved.contains(watchId);

              return IconButton(
                icon: Icon(
                  isSaved ? Icons.favorite : Icons.favorite_border,
                  color: isSaved ? Colors.redAccent : null,
                ),
                onPressed: () async {
                  try {
                    await _userService.toggleSavedWatch(watchId);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isSaved
                                ? 'Removed from saved watches'
                                : 'Saved to your favorites',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(e.toString())),
                      );
                    }
                  }
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.1,
              child: Container(
                color: AppTheme.surface,
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                          child:
                              Icon(Icons.watch, size: 100, color: AppTheme.gold),
                        ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                      )
                    : const Center(
                        child:
                            Icon(Icons.watch, size: 100, color: AppTheme.gold),
                      ),
              ),
            ),
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
                  const SizedBox(height: 24),

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
                      onPressed: () => _inquireViaFacebook(context),
                      icon: const Icon(Icons.facebook),
                      label: const Text('Inquire via Urbane Time'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.gold,
                        side: const BorderSide(color: AppTheme.gold),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ArTryOnScreen(
                              initialWatchId: watchId,
                              initialWatchData: data,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.view_in_ar_outlined),
                      label: const Text('Try On in AR'),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.gold,
                        side: const BorderSide(color: AppTheme.gold),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => showWatchChatSheet(
                        context,
                        watchId: watchId,
                        watchData: data,
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Ask About This Watch'),
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