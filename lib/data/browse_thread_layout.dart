import 'package:flutter/foundation.dart';

import '../models/models.dart';
import 'user_block_index.dart';

typedef BrowseThreadSlot = ({int index, String? section});
typedef BrowseThreadKeys = ({List<Key> rows, Map<Key, int> indexes});
typedef BrowseThreadLayoutOptions = ({
  bool collapsePinned,
  bool groupCards,
  bool hasHeader,
  bool hasAction,
});

/// Row descriptors for one committed list. Building and moving rows only
/// requires indexed lookups.
class BrowseThreadLayout {
  static final _firstPages =
      Expando<({Object key, BrowseThreadLayout layout})>();

  factory BrowseThreadLayout(
    List<ThreadSummary> source, {
    required BrowseThreadLayoutOptions options,
    required String? Function(ThreadSummary)? sectionLabel,
    bool firstPage = false,
    Object? cacheKey,
  }) {
    final key = cacheKey == null
        ? null
        : (cacheKey, options, userBlockIndex.visibilityRevision);
    if (key != null) {
      final previous = _firstPages[source];
      if (previous != null && previous.key == key) return previous.layout;
    }
    final known = <int>{};
    final layout = BrowseThreadLayout._(
      firstPage
          ? source.where((thread) => known.add(thread.tid)).toList()
          : source,
      options,
      sectionLabel,
    );
    if (key != null) _firstPages[source] = (key: key, layout: layout);
    return layout;
  }

  BrowseThreadLayout._(
    this.source,
    BrowseThreadLayoutOptions options,
    String? Function(ThreadSummary)? sectionLabel,
  ) : items = [
        for (final thread in source)
          if (!userBlockIndex.isBlocked(thread.authorUid)) thread,
      ] {
    if (options.collapsePinned) {
      while (pinned < items.length && items[pinned].sticky) {
        pinned++;
      }
    }
    if (pinned > 0) slots.add((index: -1, section: null));
    String? previousSection;
    for (var i = pinned; i < items.length; i++) {
      final section = sectionLabel?.call(items[i]);
      if (section != previousSection) {
        if (firstSection < 0) firstSection = slots.length;
        slots.add((index: i, section: section ?? ''));
      }
      previousSection = section;
      slots.add((index: i, section: null));
    }
    if (firstSection < 0 && options.hasAction && items.isNotEmpty) {
      firstSection = pinned > 0 ? 1 : 0;
      slots.insert(firstSection, (index: -2, section: ''));
    }
    final last = slots.lastOrNull;
    footerInCard =
        options.groupCards &&
        last != null &&
        last.index >= 0 &&
        last.section == null;

    const sortKey = ValueKey('browse-sort-section');
    final keys = <Key>[
      if (options.hasHeader) const ValueKey('browse-header'),
      if (items.isEmpty) ...[
        if (options.hasAction) sortKey,
        const ValueKey('browse-empty'),
      ] else ...[
        for (final (slot, entry) in slots.indexed)
          if (entry.index == -1)
            const ValueKey('browse-pinned')
          else if (entry.section != null)
            slot == firstSection && options.hasAction
                ? sortKey
                : ValueKey(('browse-section', entry.section, entry.index))
          else
            _threadKey(entry.index),
        const ValueKey('browse-footer'),
      ],
    ];
    collapsed = _index(keys);
    if (pinned > 0) {
      final insertion = options.hasHeader ? 2 : 1;
      expanded = _index([
        ...keys.take(insertion),
        for (var i = 0; i < pinned; i++) _threadKey(i),
        ...keys.skip(insertion),
      ]);
    } else {
      expanded = collapsed;
    }
  }

  Key _threadKey(int index) => ValueKey('browse-thread-${items[index].tid}');

  static BrowseThreadKeys _index(List<Key> keys) => (
    rows: keys,
    indexes: {for (final (index, key) in keys.indexed) key: index},
  );

  final List<ThreadSummary> source;
  final List<ThreadSummary> items;
  final List<BrowseThreadSlot> slots = [];
  int pinned = 0;
  int firstSection = -1;
  late final bool footerInCard;
  late final BrowseThreadKeys collapsed;
  late final BrowseThreadKeys expanded;
}
