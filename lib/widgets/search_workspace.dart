/// Search-specific controls and result presentation. No source data is invented.
library;

import 'dart:ui' show lerpDouble;
import '../design/motion.dart';
import '../ui/app_button.dart';
import '../design/typography.dart';
import 'package:flutter/material.dart';
import '../ui/plain_rows.dart';
import '../ui/search_field.dart';
import 'package:motor/motor.dart';
import 'package:solar_icons/solar_icons.dart';

import '../design/tokens.dart';
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

/// 搜索状态切换用 reveal 弹簧;减少动态效果时直接到位
Motion _motion(BuildContext context) => AppMotion.of(context, AppMotion.reveal);

/// Animate whole search states once. Pagination leaves this keyed subtree intact.
class SearchStateReveal extends StatelessWidget {
  final Widget child;
  const SearchStateReveal({super.key, required this.child});
  @override
  Widget build(BuildContext context) => SingleMotionBuilder(
    motion: _motion(context),
    from: 0,
    value: 1,
    child: child,
    builder: (context, value, child) => Opacity(
      opacity: value.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(
          0,
          MediaQuery.disableAnimationsOf(context) ? 0 : (1 - value) * 7,
        ),
        child: child,
      ),
    ),
  );
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
              borderRadius: BorderRadius.circular(
                lerpDouble(14, 22, animation.value)!,
              ),
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
      // 没有独立的搜索按钮:键盘搜索键提交;检索中清除钮换成小转圈
      onSubmitted: (_) {
        if (controller.text.trim().isNotEmpty) onSubmit();
      },
      busy: loading && controller.text.trim() == submitted,
    ),
  );
}

class SearchResultCard extends StatelessWidget {
  final ThreadSummary thread;
  final String keyword;
  final VoidCallback onTap;
  const SearchResultCard({
    super.key,
    required this.thread,
    required this.keyword,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final source = thread.forumName?.trim();
    final author = thread.author.trim();
    // 监听放在行级:一次 markRead 只重建这一行
    return ReadStateBuilder(
      tid: thread.tid,
      replies: thread.replies,
      builder: (context, state) => SearchResultRow(
        title: thread.title,
        query: keyword,
        snippet: thread.snippet?.trim(),
        meta: [
          if (source != null && source.isNotEmpty) source,
          if (author.isNotEmpty) author,
          '${thread.replies} 回复',
        ],
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
      padding: const EdgeInsets.fromLTRB(24, 36, 24, 32),
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
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Semantics(
      label: '正在搜索',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView.builder(
          primary: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          itemCount: 3,
          itemBuilder: (context, index) => Container(
            padding: const EdgeInsets.all(18),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: t.separator, width: .5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FractionallySizedBox(
                  widthFactor: lerpDouble(.65, .9, index / 2),
                  child: Container(
                    height: 15,
                    decoration: BoxDecoration(
                      color: t.fill,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FractionallySizedBox(
                  widthFactor: .9,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: t.fill,
                      borderRadius: BorderRadius.circular(AppRadii.xs),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 96,
                  height: 11,
                  decoration: BoxDecoration(
                    color: t.fill,
                    borderRadius: BorderRadius.circular(AppRadii.xs),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
