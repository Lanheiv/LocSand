import 'package:flutter/material.dart';

import 'package:locsand/view/components/card_style.dart';

class FloatingAppBar extends StatelessWidget {
  const FloatingAppBar({
    super.key,
    required this.title,
    this.loading = false,
    this.showBack = false,
    this.actions = const [],
  });

  final String title;
  final bool loading;
  final bool showBack;
  final List<Widget> actions;

  static const double _height = 56;
  static const double _wideBreakpoint = 700;
  static const double maxWidth = 800;

  static bool _wide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _wideBreakpoint;

  static double sidePadding(BuildContext context) => _wide(context) ? 24 : 12;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = _wide(context);
    final innerPad = (width * 0.02).clamp(8.0, 20.0);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sidePadding(context),
        wide ? 16 : 8,
        sidePadding(context),
        wide ? 12 : 8,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: maxWidth),
          child: Container(
            height: _height,
            padding: EdgeInsets.symmetric(horizontal: innerPad),
            decoration: BoxDecoration(
              color: cardColor(context),
              borderRadius: BorderRadius.circular(_height / 2),
            ),
            child: Row(
              children: [
                if (showBack)
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    onPressed: () => Navigator.maybePop(context),
                  )
                else
                  const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
                ...actions,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
