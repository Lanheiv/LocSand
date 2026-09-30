import 'package:flutter/material.dart';

const double cardRadius = 24;

Color cardColor(BuildContext context) {
  final theme = Theme.of(context);
  final dark = theme.brightness == Brightness.dark;
  return Color.alphaBlend(
    theme.colorScheme.onSurface.withValues(alpha: dark ? 0.09 : 0.05),
    theme.scaffoldBackgroundColor,
  );
}

class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.circle, size: 8, color: active ? Colors.green : Colors.grey);
}
