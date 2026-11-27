import 'package:flutter/rendering.dart'
    show ScrollCacheExtent, SliverConstraints;
import 'package:flutter/widgets.dart';

/// The retained row is the viewport origin; prepended rows grow upward without
/// measuring their heights or changing the retained row's screen position.
class AnchoredReadingList extends StatelessWidget {
  final ScrollController controller;
  final int centerIndex;
  final int itemCount;
  final bool unknownItemCount;
  final int? initialItemLimit;
  final NullableIndexedWidgetBuilder itemBuilder;
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
    this.unknownItemCount = false,
    this.initialItemLimit,
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
      _ReadingSliver(
        key: _center,
        delegate: SliverChildBuilderDelegate(
          (context, index) => itemBuilder(context, centerIndex + index),
          childCount:
              initialItemLimit ??
              (unknownItemCount ? null : itemCount - centerIndex),
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

class _ReadingSliver extends SliverList {
  const _ReadingSliver({required super.key, required super.delegate});

  @override
  SliverMultiBoxAdaptorElement createElement() => _ReadingSliverElement(this);
}

class _ReadingSliverElement extends SliverMultiBoxAdaptorElement {
  _ReadingSliverElement(super.widget) : super(replaceMovedChildren: true);

  @override
  double estimateMaxScrollOffset(
    SliverConstraints? constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) {
    // The viewport has a finite extent while its first rows are generated.
    if (estimatedChildCount == null) return trailingScrollOffset!;
    return super.estimateMaxScrollOffset(
      constraints,
      firstIndex: firstIndex,
      lastIndex: lastIndex,
      leadingScrollOffset: leadingScrollOffset,
      trailingScrollOffset: trailingScrollOffset,
    );
  }
}
