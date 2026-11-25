import 'dart:async';

import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';

import '../core/display_time.dart';
import '../data/history_index.dart';
import '../design/motion.dart';
import '../design/sheet_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/feedback.dart';
import '../ui/plain_rows.dart';
import '../ui/press.dart';
import '../ui/search_field.dart';
import '../ui/sheet_scaffold.dart';
import '../widgets/large_title_scaffold.dart';
import 'article_page.dart';
import 'thread_detail_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.index});

  final HistoryIndex? index;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _search = TextEditingController();
  String? _activeRow;

  HistoryIndex get _index => widget.index ?? historyIndex;

  @override
  void initState() {
    super.initState();
    unawaited(_index.load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _selectRow(String? key) {
    if (key != _activeRow) setState(() => _activeRow = key);
  }

  void _open(HistoryEntry entry) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => switch (entry.type) {
          HistoryType.thread => ThreadDetailPage(
            tid: entry.id,
            title: entry.title,
            fid: entry.fid,
          ),
          HistoryType.article => ArticlePage(aid: entry.id, title: entry.title),
        },
      ),
    );
  }

  Future<void> _delete(HistoryIndex index, HistoryEntry entry) async {
    // A fresh visit may have replaced the row while it was collapsing.
    if (!index.all.contains(entry)) return;
    final undo = await index.remove(entry.key);
    if (!mounted || index != _index || undo == null) return;
    if (_activeRow == entry.key) _selectRow(null);
    if (index.all.isEmpty) _search.clear();
    _showUndo('已删除', undo);
  }

  Future<void> _clear() async {
    FocusScope.of(context).unfocus();
    _selectRow(null);
    final confirmed = MediaQuery.disableAnimationsOf(context)
        ? await showGeneralDialog<bool>(
            context: context,
            useRootNavigator: false,
            barrierDismissible: true,
            barrierLabel: '关闭',
            barrierColor: AppTokens.of(context).scrim,
            transitionDuration: AppMotion.reducedFade,
            transitionBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
            pageBuilder: (_, _, _) => const SafeArea(
              child: Padding(
                padding: EdgeInsets.all(AppSheetTokens.inset),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: AppSheetSurface(child: _ClearHistorySheet()),
                ),
              ),
            ),
          )
        : await showAppSheet<bool>(
            context,
            builder: (_) => const _ClearHistorySheet(),
          );
    if (!mounted || confirmed != true) return;
    final undo = await _index.clear();
    if (!mounted || undo == null) return;
    _search.clear();
    _showUndo('已清空', undo);
  }

  void _showUndo(String message, VoidCallback undo) {
    AppToast.show(
      context,
      message,
      actionLabel: '撤销',
      onAction: () {
        undo();
        if (mounted) AppToast.show(context, '已撤销');
      },
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_index, _search]),
    builder: (context, _) {
      final t = AppTokens.of(context);
      final index = _index;
      final entries = index.all;
      final query = _search.text.trim().toLowerCase();
      final groups = <DateTime, List<HistoryEntry>>{};
      for (final entry in entries) {
        if (entry.title.toLowerCase().contains(query)) {
          final day = DateUtils.dateOnly(entry.at.toLocal());
          (groups[day] ??= []).add(entry);
        }
      }

      return LargeTitleScaffold(
        title: '浏览历史',
        actions: [
          if (entries.isNotEmpty)
            _HistoryPill(
              label: '清空',
              semanticLabel: '清空浏览历史',
              color: t.glass,
              foreground: t.text2,
              shadow: t.shadowE1,
              onTap: _clear,
            ),
        ],
        header: entries.isEmpty
            ? null
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Semantics(
                  label: '搜索标题',
                  child: SearchCapsule(
                    controller: _search,
                    hint: '搜索标题',
                    onChanged: (_) => _selectRow(null),
                    onClear: _search.clear,
                  ),
                ),
              ),
        body: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.only(
            bottom: 60 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            if (groups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 70,
                  horizontal: 20,
                ),
                child: Column(
                  children: [
                    Text(
                      entries.isEmpty ? '还没有浏览记录' : '没有找到',
                      textAlign: TextAlign.center,
                      style: AppType.subhead.copyWith(color: t.text2),
                    ),
                    if (entries.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _HistoryPill(
                        label: '清空搜索',
                        color: t.accentFill,
                        foreground: t.accent,
                        onTap: _search.clear,
                      ),
                    ],
                  ],
                ),
              ),
            for (final MapEntry(key: day, value: visits) in groups.entries) ...[
              Padding(
                key: ValueKey(day),
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.screen,
                  20,
                  AppSpace.screen,
                  2,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    formatDisplayTime(
                      at: day,
                      style: DisplayTimeStyle.section,
                    ).replaceFirst(RegExp(r'^\d+年'), ''),
                    style: AppType.footnote.copyWith(
                      color: t.text3,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              for (final entry in visits)
                _HistoryRow(
                  key: ValueKey(entry.key),
                  entry: entry,
                  query: query,
                  active: _activeRow == entry.key,
                  onSelect: (active) {
                    if (active || _activeRow == entry.key) {
                      _selectRow(active ? entry.key : null);
                    }
                  },
                  onOpen: () {
                    _selectRow(null);
                    _open(entry);
                  },
                  onDelete: () => _delete(index, entry),
                ),
            ],
          ],
        ),
      );
    },
  );
}

class _ClearHistorySheet extends StatelessWidget {
  const _ClearHistorySheet();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final motion = !MediaQuery.disableAnimationsOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (motion)
            SizedBox(
              height: 22,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.fill2,
                    borderRadius: BorderRadius.circular(AppRadii.bar),
                  ),
                  child: const SizedBox(width: 36, height: 5),
                ),
              ),
            )
          else
            const SizedBox(height: 22),
          const SizedBox(height: 12),
          Semantics(
            header: true,
            child: Text(
              '清空浏览历史？',
              textAlign: TextAlign.center,
              style: AppType.title2.copyWith(color: t.text),
            ),
          ),
          const SizedBox(height: 18),
          _HistoryPill(
            label: '清空',
            color: Radix.red11Light,
            foreground: Radix.whiteA12,
            onTap: () => Navigator.pop(context, true),
          ),
          const SizedBox(height: 10),
          _HistoryPill(
            label: '取消',
            color: t.fill,
            foreground: t.text2,
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }
}

class _HistoryPill extends StatelessWidget {
  const _HistoryPill({
    required this.label,
    required this.color,
    required this.foreground,
    required this.onTap,
    this.semanticLabel,
    this.shadow,
  });

  final String label;
  final String? semanticLabel;
  final Color color;
  final Color foreground;
  final List<BoxShadow>? shadow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    semanticLabel: semanticLabel ?? label,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.full),
        boxShadow: shadow,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: ExcludeSemantics(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppType.subhead.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({
    required super.key,
    required this.entry,
    required this.query,
    required this.active,
    required this.onSelect,
    required this.onOpen,
    required this.onDelete,
  });

  final HistoryEntry entry;
  final String query;
  final bool active;
  final ValueChanged<bool> onSelect;
  final VoidCallback onOpen;
  final Future<void> Function() onDelete;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow>
    with TickerProviderStateMixin {
  static const _actionWidth = 88.0;
  static const _flingVelocity = 350.0;

  late final _slide = AnimationController(vsync: this);
  late final _removal = AnimationController(vsync: this);
  double _dragProgress = 0;
  bool _directionDecided = false;
  bool _dragging = false;
  bool _deleting = false;

  @override
  void didUpdateWidget(covariant _HistoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active && !widget.active && _dragProgress != 0) {
      _settle(false);
    }
  }

  @override
  void dispose() {
    _slide.dispose();
    _removal.dispose();
    super.dispose();
  }

  void _startDrag(DragStartDetails details) {
    _dragging = _slide.value > 0;
    _directionDecided = _dragging;
    if (_dragging) {
      _slide.stop();
      _dragProgress = _slide.value;
    }
  }

  void _updateDrag(DragUpdateDetails details) {
    final delta = details.primaryDelta!;
    if (!_directionDecided && delta != 0) {
      _directionDecided = true;
      if (delta > 0) return;
      _dragging = true;
      widget.onSelect(true);
    }
    if (!_dragging) return;
    _dragProgress = (_dragProgress - delta / _actionWidth).clamp(0.0, 1.0);
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_slide.value == 0 && !_slide.isAnimating) {
        _settleVisual(1, 0);
      }
    } else {
      _slide.value = _dragProgress;
    }
  }

  void _endDrag(DragEndDetails details) {
    if (!_dragging) return;
    final velocity = -details.primaryVelocity!;
    final open =
        velocity > _flingVelocity ||
        (velocity >= -_flingVelocity && _dragProgress > .5);
    _settle(open, velocity);
    widget.onSelect(open);
  }

  void _cancelDrag() {
    if (!_dragging) return;
    _settle(false);
    widget.onSelect(false);
  }

  void _settle(bool open, [double velocity = 0]) {
    _dragging = false;
    _dragProgress = open ? 1 : 0;
    _settleVisual(_dragProgress, velocity);
  }

  void _settleVisual(double target, double velocity) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _slide.animateTo(
        target,
        duration: AppMotion.reducedFade,
        curve: Curves.easeOut,
      );
    } else {
      AppMotion.settle(
        _slide,
        target: target,
        motion: AppMotion.reveal,
        velocity: velocity / _actionWidth,
      );
    }
  }

  Future<void> _delete() async {
    if (_deleting) return;
    final remove = widget.onDelete;
    final reduced = MediaQuery.disableAnimationsOf(context);
    setState(() => _deleting = true);
    try {
      await _removal
          .animateTo(
            1,
            duration: reduced ? AppMotion.reducedFade : AppMotion.tap.duration,
            curve: AppMotion.contentFadeCurve,
          )
          .orCancel;
    } on TickerCanceled {
      // Scrolling the row offscreen must still complete the user's deletion.
    }
    await remove();
    if (mounted) {
      setState(() {
        _deleting = false;
        _removal.value = 0;
      });
    }
  }

  void _tap() {
    if (_slide.value > 0 || _slide.isAnimating) {
      _settle(false);
      widget.onSelect(false);
    } else {
      widget.onOpen();
    }
  }

  Widget _foreground(AppTokens t) {
    final entry = widget.entry;
    final article = entry.type == HistoryType.article;
    final fields = [
      if (article) entry.column ?? '' else entry.forumName ?? '',
      if (!article) entry.author,
    ].where((part) => part.isNotEmpty).toList();
    final local = entry.at.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final label = [
      article ? '文章' : '帖子',
      entry.title,
      ...fields,
      time,
    ].join('，');
    final metadata = AppType.footnote.copyWith(color: t.text3);

    return GestureDetector(
      excludeFromSemantics: true,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: _deleting ? null : _startDrag,
      onHorizontalDragUpdate: _deleting ? null : _updateDrag,
      onHorizontalDragEnd: _deleting ? null : _endDrag,
      onHorizontalDragCancel: _deleting ? null : _cancelDrag,
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.delete): _delete},
        child: Semantics(
          customSemanticsActions: {
            const CustomSemanticsAction(label: '删除'): _delete,
          },
          child: ColoredBox(
            color: t.bg,
            child: PressHighlight(
              onTap: _tap,
              semanticLabel: label,
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.screen,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        ThreadRow.highlight(
                          entry.title,
                          widget.query,
                          t.accent,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.headline.copyWith(
                          color: t.text,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          if (article)
                            Text(
                              '文章',
                              style: metadata.copyWith(
                                color: t.accent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (fields.isNotEmpty)
                            Flexible(
                              child: Text(
                                "${article ? ' · ' : ''}${fields.join(' · ')}",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: metadata,
                              ),
                            ),
                          Text(
                            article || fields.isNotEmpty ? ' · $time' : time,
                            style: metadata,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _deleteAction(AppTokens t, double opacity) {
    final enabled = widget.active && !_dragging && !_deleting;
    return Positioned(
      top: 0,
      bottom: 0,
      right: 0,
      width: _actionWidth,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Opacity(
          opacity: opacity,
          child: ColoredBox(
            color: Radix.red11Light,
            child: PressHighlight(
              onTap: enabled ? _delete : null,
              semanticLabel: '删除 ${widget.entry.title}',
              color: t.pressed.withValues(alpha: .18),
              child: Center(
                child: ExcludeSemantics(
                  child: Text(
                    '删除',
                    style: AppType.subhead.copyWith(
                      color: Radix.whiteA12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);

    return AnimatedBuilder(
      animation: _removal,
      child: AnimatedBuilder(
        animation: _slide,
        child: _foreground(t),
        builder: (context, foreground) {
          final progress = _slide.value;
          // Do not paint the red layer at rest, even underneath an opaque row.
          final action = progress == 0
              ? null
              : _deleteAction(t, reduced ? progress : 1);
          return Stack(
            children: [
              if (!reduced) ?action,
              Transform.translate(
                offset: Offset(reduced ? 0 : -_actionWidth * progress, 0),
                child: foreground,
              ),
              if (reduced) ?action,
            ],
          );
        },
      ),
      builder: (_, child) {
        final remaining = 1 - _removal.value;
        return IgnorePointer(
          ignoring: _deleting,
          child: ExcludeSemantics(
            excluding: _deleting,
            child: ExcludeFocus(
              excluding: _deleting,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: reduced ? 1 : remaining,
                  child: Opacity(opacity: remaining, child: child),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
