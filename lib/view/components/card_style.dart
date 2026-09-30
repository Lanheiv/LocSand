import 'package:flutter/material.dart';

Color cardColor(BuildContext context) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  return Color.alphaBlend(
    theme.colorScheme.onSurface.withOpacity(dark ? 0.09 : 0.05),
    theme.scaffoldBackgroundColor,
  );
}