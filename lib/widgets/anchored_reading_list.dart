import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/widgets.dart';

/// The retained row is the viewport origin; prepended rows grow upward without
/// measuring their heights or changing the retained row's screen position.
class AnchoredReadingList extends StatelessWidget {
  final ScrollController controller;
  final int centerIndex;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ChildIndexGetter findChildIndexCallback;
  final ScrollCacheExtent? scrollCacheExtent;

  const AnchoredReadingList({
    super.key,
    required this.controller,
    required this.centerIndex,
    required this.itemCount,
    required this.itemBuilder,
    required this.findChildIndexCallback,
    this.scrollCacheExtent,
  });

  static const _center = ValueKey('reading-list-center');

  @override
  Widget build(BuildContext context) => CustomScrollView(
    controller: controller,
    scrollCacheExtent: scrollCacheExtent,
    center: _center,
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: [
      if (centerIndex > 0)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => itemBuilder(context, centerIndex - index - 1),
            childCount: centerIndex,
            findChildIndexCallback: (key) {
              final index = findChildIndexCallback(key);
              return index == null || index >= centerIndex
                  ? null
                  : centerIndex - index - 1;
            },
          ),
        ),
      SliverList(
        key: _center,
        delegate: SliverChildBuilderDelegate(
          (context, index) => itemBuilder(context, centerIndex + index),
          childCount: itemCount - centerIndex,
          findChildIndexCallback: (key) {
            final index = findChildIndexCallback(key);
            return index == null || index < centerIndex
                ? null
                : index - centerIndex;
          },
        ),
      ),
    ],
  );
}
