import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/watch_service.dart';
import '../../theme/app_theme.dart';
import 'watch_detail_screen.dart';

class ArTryOnScreen extends StatefulWidget {
  final String? initialWatchId;
  final Map<String, dynamic>? initialWatchData;

  const ArTryOnScreen({
    super.key,
    this.initialWatchId,
    this.initialWatchData,
  });

  @override
  State<ArTryOnScreen> createState() => _ArTryOnScreenState();
}

class _ArTryOnScreenState extends State<ArTryOnScreen> {
  final _watchService = WatchService();
  double _scale = 0;
  String? _selectedWatchId;
  Map<String, dynamic>? _selectedWatchData;

  @override
  void initState() {
    super.initState();
    _selectedWatchId = widget.initialWatchId;
    _selectedWatchData = widget.initialWatchData;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR Try-On'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_outlined),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('AR Try-On coming soon')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  color: AppTheme.surface,
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.view_in_ar_outlined,
                            size: 72, color: AppTheme.textSecondary),
                        SizedBox(height: 12),
                        Text(
                          'AR camera preview coming soon',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Point your camera at your wrist to try on watches',
                          style:
                              TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 16,
                  top: 16,
                  child: Column(
                    children: [
                      _floatingIcon(Icons.flash_off_outlined),
                      const SizedBox(height: 10),
                      _floatingIcon(Icons.cameraswitch_outlined),
                      const SizedBox(height: 10),
                      _floatingIcon(Icons.photo_camera_outlined),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Scale',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    Text(
                      '${_scale >= 0 ? '+' : ''}${_scale.toInt()}%',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppTheme.gold,
                    thumbColor: AppTheme.gold,
                    inactiveTrackColor: AppTheme.background,
                  ),
                  child: Slider(
                    value: _scale,
                    min: -20,
                    max: 20,
                    onChanged: (v) => setState(() => _scale = v),
                  ),
                ),
                const SizedBox(height: 8),

                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _watchService.allListedWatches(),
                  builder: (context, snapshot) {
                    final docs = snapshot.data?.docs ?? [];

                    // Default to the first catalog watch if nothing is
                    // selected yet and we have data to select from.
                    if (_selectedWatchId == null && docs.isNotEmpty) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && _selectedWatchId == null) {
                          setState(() {
                            _selectedWatchId = docs.first.id;
                            _selectedWatchData = docs.first.data();
                          });
                        }
                      });
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 76,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (docs.isEmpty) {
                      return const SizedBox(
                        height: 76,
                        child: Center(
                          child: Text(
                            'No watches available yet.',
                            style: TextStyle(color: AppTheme.textSecondary),
                          ),
                        ),
                      );
                    }

                    return SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: docs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data();
                          final isSelected = doc.id == _selectedWatchId;
                          final brand = data['brand'] as String? ?? '';
                          final name = data['name'] as String? ?? 'Watch';

                          return InkWell(
                            onTap: () => setState(() {
                              _selectedWatchId = doc.id;
                              _selectedWatchData = data;
                            }),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 90,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected
                                      ? AppTheme.gold
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.watch,
                                      color: AppTheme.gold, size: 24),
                                  const SizedBox(height: 4),
                                  if (brand.isNotEmpty)
                                    Text(
                                      brand,
                                      style: const TextStyle(
                                        color: AppTheme.gold,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontSize: 9,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),

                ElevatedButton(
                  onPressed: (_selectedWatchId == null || _selectedWatchData == null)
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => WatchDetailScreen(
                                watchId: _selectedWatchId!,
                                data: _selectedWatchData!,
                              ),
                            ),
                          );
                        },
                  child: const Text('Interested? View Details'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingIcon(IconData icon) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}