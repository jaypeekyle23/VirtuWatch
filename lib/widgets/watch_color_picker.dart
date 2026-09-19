import 'package:flutter/material.dart';
import '../constants/watch_colors.dart';
import '../theme/app_theme.dart';

/// Row of tappable color swatches for picking a watch's colors from
/// [watchColorPalette]. Tapping a swatch toggles it in/out of
/// [selectedHexes] — used to build a watch's ordered color list (first
/// selected = primary) rather than a single selection.
class WatchColorPicker extends StatelessWidget {
  final List<String> selectedHexes;
  final ValueChanged<String> onChanged;

  const WatchColorPicker({
    super.key,
    required this.selectedHexes,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 10,
      children: watchColorPalette.map((option) {
        final isSelected = selectedHexes
            .any((hex) => hex.toUpperCase() == option.hex.toUpperCase());
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