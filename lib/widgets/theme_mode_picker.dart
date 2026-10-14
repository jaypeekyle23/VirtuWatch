import 'package:flutter/material.dart';
import '../services/theme_controller.dart';
import '../theme/app_palette.dart';
import '../theme/app_theme.dart';
import 'luxe.dart';

/// Lets the user choose between the Default, Dark and Light looks.
/// The choice applies right away and is remembered on this device.
class ThemeModePicker extends StatelessWidget {
  const ThemeModePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = ThemeController.instance;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in AppThemeMode.values)
                luxePill(
                  mode.label,
                  selected: controller.mode == mode,
                  onTap: () => controller.setMode(mode),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            controller.mode.description,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
