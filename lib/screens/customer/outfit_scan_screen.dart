import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class OutfitScanScreen extends StatelessWidget {
  const OutfitScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Outfit Color Scan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _stepCircle('1', 'Aim Camera', active: true),
                _stepConnector(),
                _stepCircle('2', 'Analyze', active: false),
                _stepConnector(),
                _stepCircle('3', 'Results', active: false),
              ],
            ),
            const SizedBox(height: 20),

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.checkroom_outlined,
                            size: 72, color: AppTheme.textSecondary),
                        SizedBox(height: 12),
                        Text(
                          'Camera preview coming soon',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Point your camera at your outfit',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                    Positioned(
                      top: 16,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Point camera at your outfit',
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'LIVE COLOR EXTRACTION',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _colorBar(Colors.blueGrey, 0.4),
                      const SizedBox(width: 4),
                      _colorBar(const Color(0xFFC9A876), 0.25),
                      const SizedBox(width: 4),
                      _colorBar(const Color(0xFFEDE3D3), 0.2),
                      const SizedBox(width: 4),
                      _colorBar(const Color(0xFF1B1F2A), 0.15),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('42%', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                      Text('25%', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                      Text('20%', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                      Text('15%', style: TextStyle(color: AppTheme.textSecondary, fontSize: 10)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(Icons.lightbulb_outline, color: AppTheme.textSecondary, size: 14),
                    SizedBox(width: 4),
                    Text('Good lighting helps',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                ),
                Row(
                  children: const [
                    Icon(Icons.grid_view_outlined, color: AppTheme.textSecondary, size: 14),
                    SizedBox(width: 4),
                    Text('Clusters: K=4',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            InkWell(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Outfit scan coming soon')),
                );
              },
              borderRadius: BorderRadius.circular(40),
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppTheme.gold,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.camera_alt_outlined,
                    color: Color(0xFF0E1A2B), size: 28),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap to capture outfit colors',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepCircle(String number, String label, {required bool active}) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: active
                ? AppTheme.gold
                : AppTheme.surface,
            child: Text(
              number,
              style: TextStyle(
                color: active ? const Color(0xFF0E1A2B) : AppTheme.textSecondary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? AppTheme.gold : AppTheme.textSecondary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepConnector() {
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Container(
        width: 24,
        height: 1,
        color: AppTheme.textSecondary.withValues(alpha: 0.3),
      ),
    );
  }

  Widget _colorBar(Color color, double flexValue) {
    return Expanded(
      flex: (flexValue * 100).toInt(),
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('How Outfit Color Scan Works',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'VirtuWatch uses your phone\'s camera to identify the dominant '
          'colors in your outfit using a clustering technique (K-means '
          'color extraction).\n\n'
          'Point your camera at your outfit in good lighting, and the app '
          'detects the main tones you\'re wearing — then uses those '
          'colors to recommend watches with cases, dials, or bands that '
          'complement your look.\n\n'
          'Good, even lighting helps the scan work more accurately.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it', style: TextStyle(color: AppTheme.gold)),
          ),
        ],
      ),
    );
  }
}