import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Small letter-spaced caps used for section labels and text links.
TextStyle get kLabelStyle => TextStyle(
  color: AppTheme.textSecondary,
  fontSize: 11,
  letterSpacing: 1.4,
  fontWeight: FontWeight.w500,
);

/// A single hairline along the top edge, used to separate sections.
BoxDecoration get kTopRule =>
    BoxDecoration(border: Border(top: BorderSide(color: AppTheme.hairline)));

/// Hairline-topped block: small caps [label], optional [trailing] widget,
/// then [child].
Widget luxeSection(String label, Widget child, {Widget? trailing}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: kTopRule,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: kLabelStyle),
            const Spacer(),
            ?trailing,
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );

/// Neutral toggle pill: a brighter outline and a faint fill when selected.
Widget luxePill(
  String label, {
  required bool selected,
  required VoidCallback onTap,
}) =>
    InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.textPrimary.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.textPrimary
                : AppTheme.textPrimary.withValues(alpha: 0.24),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
          ),
        ),
      ),
    );

/// Underline-only text field styling: a faint line, gold when focused.
InputDecoration luxeFieldDecoration({
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) =>
    InputDecoration(
      filled: false,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixIconConstraints: const BoxConstraints(minWidth: 32),
      suffixIconConstraints: const BoxConstraints(minWidth: 32),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: AppTheme.outline),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: AppTheme.gold),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Colors.redAccent),
      ),
    );
/// Serif section title with an optional small-caps text link on the right.
Widget luxeHeader(String title, {String? action, VoidCallback? onTap}) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title, style: AppTheme.serif(size: 24)),
          const Spacer(),
          if (action != null)
            InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(action,
                    style: kLabelStyle.copyWith(color: AppTheme.textPrimary)),
              ),
            ),
        ],
      ),
    );

/// Cells in one row, with a hairline above, below and between them.
Widget luxeBand(List<Widget> cells) => Container(
      decoration: BoxDecoration(
        border:
            Border.symmetric(horizontal: BorderSide(color: AppTheme.hairline)),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++) ...[
              if (i > 0)
                VerticalDivider(width: 1, color: AppTheme.hairline),
              Expanded(child: cells[i]),
            ],
          ],
        ),
      ),
    );

/// App logo cropped to its visible mark (the source PNG has large
/// transparent margins). Left-aligned by default so it lines up with a
/// title; pass [Alignment.center] to center it.
Widget luxeLogo({Alignment alignment = Alignment.centerLeft}) => Align(
      alignment: alignment,
      child: ClipRect(
        child: Align(
          alignment: const Alignment(0.1477, 0),
          widthFactor: 0.56,
          heightFactor: 0.34,
          child: Image.asset(
            AppTheme.logoAsset,
            width: 260,
            fit: BoxFit.fitWidth,
          ),
        ),
      ),
    );

/// Vertically centers [child] on a short page (auth-style screens) while
/// still letting it scroll when the keyboard or a small screen needs room.
Widget luxeCenteredPage(Widget child) => SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
            child: Center(child: child),
          ),
        ),
      ),
    );

/// Neutral secondary button: a faint outline and white text, so the gold
/// primary button stays the only focal point.
ButtonStyle get luxeOutlinedStyle => OutlinedButton.styleFrom(
  foregroundColor: AppTheme.textPrimary,
  side: BorderSide(color: AppTheme.outline),
  padding: const EdgeInsets.symmetric(vertical: 16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
);