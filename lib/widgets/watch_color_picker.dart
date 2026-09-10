import 'package:flutter/material.dart';
import '../constants/watch_colors.dart';
import '../theme/app_theme.dart';

/// Row of tappable color swatches for picking a watch's primary color
/// from [watchColorPalette]. Used identically on the merchant add and
/// edit watch screens.
class WatchColorPicker extends StatelessWidget {
  final String selectedHex;
  final ValueChanged<String> onChanged;

  const WatchColorPicker({
    super.key,
    required this.selectedHex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      children: watchColorPalette.map((option) {
        final isSelected = option.hex == selectedHex;
        final swatchColor = hexToColor(option.hex);
        // Light swatches (e.g. Silver, White) need a dark checkmark;
        // dark ones need a light checkmark to stay visible.
        final isLightSwatch = swatchColor.computeLuminance() > 0.5;

        return GestureDetector(
          onTap: () => onChanged(option.hex),
          child: SizedBox(
            width: 56,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: swatchColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? AppTheme.gold : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 16,
                          color: isLightSwatch ? Colors.black87 : Colors.white,
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  option.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? AppTheme.gold : AppTheme.textSecondary,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}