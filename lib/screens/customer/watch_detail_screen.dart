import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/user_service.dart';
import '../../theme/app_theme.dart';

class WatchDetailScreen extends StatelessWidget {
  final String watchId;
  final Map<String, dynamic> data;

  const WatchDetailScreen({
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
    final caseDiameter = data['caseDiameterMm'];
    final caseThickness = data['caseThicknessMm'];
    final lugToLug = data['lugToLugMm'];
    final bandWidth = data['bandWidthMm'];
    final movementType = data['movementType'] as String? ?? '';
    final waterResistance = data['waterResistance'] as String? ?? '';
    final bandMaterial = data['bandMaterial'] as String? ?? '';
    final caseMaterial = data['caseMaterial'] as String? ?? '';
    final userService = UserService();

    return Scaffold(
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: userService.currentUserStream(),
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
                    await userService.toggleSavedWatch(watchId);
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
                child: const Center(
                  child: Icon(Icons.watch, size: 100, color: AppTheme.gold),
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

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.view_in_ar_outlined,
                            color: AppTheme.textSecondary),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'AR Try-On coming soon',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 13,
                            ),
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

  Widget _specRow(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}