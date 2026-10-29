/// Controls shared by the browse and discovery screens.
library;

import 'package:flutter/material.dart';
import '../ui/search_field.dart';
import 'package:flutter/cupertino.dart';

import 'large_title_scaffold.dart';

class BrowseSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final VoidCallback onClear;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  const BrowseSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onClear,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => SearchCapsule(
    controller: controller,
    hint: hint,
    onClear: onClear,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    autofocus: autofocus,
  );
}

/// An independent destination owns a collapsing title; tab bodies do not.
class BrowseScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  const BrowseScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: title,
    body: body,
    actions: actions,
    floatingActionButton: floatingActionButton,
  );
}

/// Nested scrolling can dispatch notifications during viewport layout. Defer
/// pagination until the frame completes, then recheck the current loading state.
class BrowsePaginationObserver extends StatefulWidget {
  final bool enabled;
  final VoidCallback onLoadMore;
  final Widget child;
  final double threshold;
  const BrowsePaginationObserver({
    super.key,
    required this.enabled,
    required this.onLoadMore,
    required this.child,
    this.threshold = 350,
  });

  @override
  State<BrowsePaginationObserver> createState() =>
      _BrowsePaginationObserverState();
}

class _BrowsePaginationObserverState extends State<BrowsePaginationObserver> {
  bool _scheduled = false;

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (!_scheduled &&
              widget.enabled &&
              notification.metrics.axis == Axis.vertical &&
              notification.metrics.extentAfter < widget.threshold) {
            _scheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _scheduled = false;
              if (mounted && widget.enabled) widget.onLoadMore();
            });
            WidgetsBinding.instance.ensureVisualUpdate();
          }
          return false;
        },
        child: widget.child,
      );
}
