import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

class HorizontalScroller extends StatefulWidget {
  const HorizontalScroller({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = 12,
  });

  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;

  @override
  State<HorizontalScroller> createState() => _HorizontalScrollerState();
}

class _HorizontalScrollerState extends State<HorizontalScroller> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // extra 12 leaves room for the scrollbar under the cards
      height: widget.height + 12,
      child: ScrollConfiguration(
        // lets you drag the row with a mouse or trackpad on desktop
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
            PointerDeviceKind.trackpad,
          },
        ),
        child: Scrollbar(
          controller: _controller,
          child: ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            itemCount: widget.itemCount,
            separatorBuilder: (_, __) => SizedBox(width: widget.spacing),
            itemBuilder: widget.itemBuilder,
          ),
        ),
      ),
    );
  }
}