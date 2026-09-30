import 'package:flutter/material.dart';

class FloatingAppBar extends StatelessWidget {
  const FloatingAppBar({
    super.key,
    required this.title,
    this.loading = false,
    this.onSettings,
    this.onUser,
  });

  final String title;
  final bool loading;
  final VoidCallback? onSettings;
  final VoidCallback? onUser;

  static const double _height = 56;
  static const double _maxWidth = 800;
  static const double _wideBreakpoint = 700;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    final wide = width >= _wideBreakpoint;

    // Inner left/right padding, clamped between 8 and 20.
    final innerPad = (width * 0.02).clamp(8.0, 20.0);

    // Always a little different from the background, in light and dark.
    final barColor = Color.alphaBlend(
      scheme.onSurface.withOpacity(dark ? 0.09 : 0.05),
      theme.scaffoldBackgroundColor,
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        wide ? 24 : 12,
        wide ? 16 : 8,
        wide ? 24 : 12,
        wide ? 12 : 8,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Container(
            height: _height,
            padding: EdgeInsets.symmetric(horizontal: innerPad),
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(_height / 2),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: onSettings,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.person_rounded),
                  onPressed: onUser,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}