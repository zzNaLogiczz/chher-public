/// Search-specific controls and result presentation. No source data is invented.
library;

import 'dart:ui' show lerpDouble;
import '../ui/app_button.dart';
import '../design/typography.dart';
import 'package:flutter/material.dart';
import '../ui/plain_rows.dart';
import '../ui/search_field.dart';
import 'expressive_controls.dart';
import 'package:solar_icons/solar_icons.dart';

import '../design/tokens.dart';
import '../design/thread_row_tokens.dart';
import '../ui/feedback.dart';
import '../models/models.dart';

/// Actual queries submitted during this process session, never a fabricated hot list.
final searchSessionHistory = SearchSessionHistory();

class SearchSessionHistory extends ChangeNotifier {
  final _queries = <String>[];
  List<String> get queries => List.unmodifiable(_queries);
  void remember(String query) {
    final value = query.trim();
    if (value.isEmpty) return;
    _queries.remove(value);
    _queries.insert(0, value);
    if (_queries.length > 6) _queries.removeLast();
    notifyListeners();
  }

  void clear() {
    if (_queries.isEmpty) return;
    _queries.clear();
    notifyListeners();
  }
}

/// New search results share the bounded, paint-only content arrival.
class SearchStateReveal extends StatelessWidget {
  final Widget child;
  const SearchStateReveal({super.key, required this.child});
  @override
  Widget build(BuildContext context) =>
      ExpressivePageReveal(active: true, animateOnMount: true, child: child);
}

/// Only the static surface flies; the real EditableText waits on the destination.
class SearchEntryHero extends StatelessWidget {
  final String? tag;
  final Widget child;
  const SearchEntryHero({super.key, required this.tag, required this.child});
  @override
  Widget build(BuildContext context) {
    if (tag == null || MediaQuery.disableAnimationsOf(context)) return child;
    return Hero(
      tag: tag!,
      flightShuttleBuilder: (context, animation, direction, from, to) {
        final t = AppTokens.of(to);
        return AnimatedBuilder(
          animation: animation,
          builder: (context, _) => Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.full),
              child: ColoredBox(
                color: t.fill,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: lerpDouble(11, 12, animation.value)!,
                    ),
                    child: Icon(
                      SolarIconsBold.magnifier,
                      size: 22,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}

class SearchWorkspaceInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool loading;
  final String submitted;
  final VoidCallback onSubmit;
  final VoidCallback onClear;
  const SearchWorkspaceInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.loading,
    required this.submitted,
    required this.onSubmit,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => SearchCapsule(
      key: const ValueKey('search-input-surface'),
      controller: controller,
      focusNode: focusNode,
      hint: '搜索帖子与讨论',
      onClear: onClear,
      // 键盘搜索键提交，检索期间仍可清除。
      onSubmitted: (_) {
        if (controller.text.trim().isNotEmpty) onSubmit();
      },
      busy: submitted.isNotEmpty && controller.text.trim() == submitted
          ? loading
          : null,
    ),
  );
}

class SearchResultCard extends StatelessWidget {
  final ThreadSummary thread;
  final String keyword;
  final VoidCallback onTap;
  final bool trimEmptyTail;
  const SearchResultCard({
    super.key,
    required this.thread,
    required this.keyword,
    required this.onTap,
    this.trimEmptyTail = false,
  });

  @override
  Widget build(BuildContext context) {
    return ReadStateBuilder(
      tid: thread.tid,
      replies: thread.replies,
      builder: (context, state) => ThreadRow(
        thread: thread,
        query: keyword,
        trimEmptySearchTail: trimEmptyTail,
        onTap: onTap,
        readState: state,
      ),
    );
  }
}

class SearchStatusPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SearchStatusPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ListView(
      primary: true,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.screen,
        36,
        AppSpace.screen,
        32,
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: t.fill,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, size: 26, color: t.text2),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: TextStyle(
            fontSize: AppType.sizeTitle2,
            height: 1.45,
            fontWeight: FontWeight.w700,
            color: t.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          message,
          style: TextStyle(
            fontSize: AppType.sizeBody,
            height: 1.75,
            color: t.text2,
          ),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(onPressed: onAction, label: actionLabel!),
          ),
        ],
      ],
    );
  }
}

class SearchLoadingPanel extends StatelessWidget {
  const SearchLoadingPanel({super.key});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '正在搜索',
    liveRegion: true,
    child: ExcludeSemantics(
      child: LoadingPlaceholder(
        child: ListView.builder(
          primary: true,
          padding: EdgeInsets.zero,
          itemCount: ThreadRowTokens.searchSkeletonRows,
          itemBuilder: (context, index) => const PlainRow(
            verticalPadding: ThreadRowTokens.verticalPadding,
            child: SearchThreadRowLayout.skeleton(),
          ),
        ),
      ),
    ),
  );
}
