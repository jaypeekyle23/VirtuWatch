import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class WristMeasurementScreen extends StatefulWidget {
  const WristMeasurementScreen({super.key});

  @override
  State<WristMeasurementScreen> createState() =>
      _WristMeasurementScreenState();
}

class _WristMeasurementScreenState extends State<WristMeasurementScreen> {
  String _selectedReference = 'ID Card';
  final List<String> _referenceOptions = [
    'ID Card',
    'Credit Card',
    '1-Peso Coin',
    '5-Peso Coin',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Measure Your Wrist'),
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
                _stepCircle('1', 'Place\nReference', active: true),
                _stepConnector(),
                _stepCircle('2', 'Position\nWrist', active: false),
                _stepConnector(),
                _stepCircle('3', 'Capture', active: false),
              ],
            ),
            const SizedBox(height: 20),

            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.gold.withValues(alpha: 0.4),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.credit_card_outlined,
                            size: 56, color: AppTheme.textSecondary),
                        SizedBox(height: 12),
                        Text(
                          'Camera preview coming soon',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Place your ID card flat next to your wrist',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                    Positioned(
                      bottom: 16,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(Icons.circle, color: Colors.redAccent, size: 8),
                            SizedBox(width: 6),
                            Text(
                              'Reference Object Detected',
                              style: TextStyle(color: Colors.white, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'REFERENCE OBJECT',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _referenceOptions.map((option) {
                final isSelected = _selectedReference == option;
                return ChoiceChip(
                  label: Text(option),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedReference = option),
                  backgroundColor: AppTheme.surface,
                  selectedColor: AppTheme.gold.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppTheme.gold : Colors.transparent,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            InkWell(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Wrist measurement coming soon')),
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
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ESTIMATED WRIST WIDTH',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '— mm',
                        style: TextStyle(
                          color: AppTheme.gold,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.textSecondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'AWAITING SCAN',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                  content: Text('Wrist measurement coming soon')),
                            );
                          },
                          child: const Text('Save & Continue'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.gold,
                            side: const BorderSide(color: AppTheme.gold),
                          ),
                          onPressed: () {},
                          child: const Text('Retake'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('How Wrist Measurement Works',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          'VirtuWatch uses your phone\'s camera to estimate your wrist '
          'width automatically.\n\n'
          'You\'ll place a reference object of known size (like an ID card or '
          'coin) flat next to your wrist, and the app calibrates a '
          'pixels-to-millimeters ratio from it to measure your wrist '
          'accurately — no tape measure needed.\n\n'
          'This helps VirtuWatch recommend watches that will actually fit '
          'your wrist comfortably.',
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

  Widget _stepCircle(String number, String label, {required bool active}) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: active ? AppTheme.gold : AppTheme.surface,
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
            height: 26,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? AppTheme.gold : AppTheme.textSecondary,
                fontSize: 9,
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
}