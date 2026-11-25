import 'dart:async';

import 'package:flutter/material.dart';

import '../data/user_block_index.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/sheet_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/grouped.dart';
import '../ui/plain_rows.dart';
import '../ui/press.dart';
import '../ui/search_field.dart';
import '../ui/user_block_action.dart';
import '../widgets/account_widgets.dart';
import '../widgets/state_view.dart';
import 'user_drawer.dart';

class BlockedUsersBody extends StatefulWidget {
  final UserBlockIndex? index;
  const BlockedUsersBody({super.key, this.index});

  @override
  State<BlockedUsersBody> createState() => _BlockedUsersBodyState();
}

class _BlockedUsersBodyState extends State<BlockedUsersBody> {
  final _search = TextEditingController();
  final _leaving = <String, BlockedUser>{};
  final _removalTimers = <String, Timer>{};
  UserBlockIndex get index => widget.index ?? userBlockIndex;
  late int _epoch;

  @override
  void initState() {
    super.initState();
    _epoch = index.epoch;
    index.addListener(_accountChanged);
    unawaited(index.load());
  }

  void _cancelRemovals() {
    for (final timer in _removalTimers.values) {
      timer.cancel();
    }
    _removalTimers.clear();
    _leaving.clear();
  }

  void _accountChanged() {
    if (_epoch == index.epoch) return;
    _epoch = index.epoch;
    _cancelRemovals();
    _search.clear();
  }

  @override
  void dispose() {
    index.removeListener(_accountChanged);
    _cancelRemovals();
    _search.dispose();
    super.dispose();
  }

  void _unblock(BlockedUser user, int epoch) {
    if (epoch != index.epoch || !index.isBlocked(user.uid)) return;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced ? AppMotion.reducedFade : AppMotion.revealDuration;
    setState(() => _leaving[user.uid] = user);
    _removalTimers.remove(user.uid)?.cancel();
    // Allow the first frame to start the collapse before timing its removal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || epoch != index.epoch) return;
      _removalTimers[user.uid] = Timer(duration, () {
        _removalTimers.remove(user.uid);
        setState(() => _leaving.remove(user.uid));
      });
    });
    unawaited(
      toggleUserBlock(
        context,
        uid: user.uid,
        name: user.name,
        avatarUrl: user.avatarUrl,
        index: index,
      ),
    );
  }

  Future<void> _showDetail(BlockedUser user, String query, int epoch) async {
    if (epoch != index.epoch) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final action = await showUserBlockSheet<_DetailAction>(
      context,
      index: index,
      builder: (_) => _BlockedUserDetail(
        user: user,
        index: index,
        query: query,
        epoch: epoch,
      ),
    );
    if (!mounted || epoch != index.epoch) return;
    switch (action) {
      case _DetailAction.profile:
        await showUserDrawer(context, user.uid, blockIndex: index);
      case _DetailAction.unblock:
        _unblock(user, epoch);
      case _DetailAction.source:
        if (index.entryFor(user.uid)?.src case final source?) {
          await openBlockedUserSource(context, source, index: index);
        }
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([index, _search]),
    builder: (context, _) {
      final q = _search.text.trim();
      final term = q.toLowerCase();
      final entries = index.entries;
      final users =
          {
              ..._leaving,
              for (final user in entries) user.uid: user,
            }.values.where((user) {
              return user.name.toLowerCase().contains(term) ||
                  user.uid.contains(term) ||
                  user.note?.toLowerCase().contains(term) == true ||
                  user.src?.excerpt.toLowerCase().contains(term) == true;
            }).toList()
            ..sort((a, b) => b.blockedAt.compareTo(a.blockedAt));
      final reduced = MediaQuery.disableAnimationsOf(context);
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          if (entries.isNotEmpty || _leaving.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.groupInset,
                4,
                AppSpace.groupInset,
                4,
              ),
              child: SearchCapsule(
                key: const ValueKey('blocked-user-search'),
                controller: _search,
                hint: '搜索昵称、UID 或备注',
                onClear: _search.clear,
              ),
            ),
          if (index.lastError != null)
            StateView(icon: AppIcons.warning, message: index.lastError!)
          else if (entries.isEmpty && _leaving.isEmpty)
            StateView.empty(message: '黑名单为空')
          else if (users.isEmpty)
            StateView(
              icon: AppIcons.search,
              message: '没有找到匹配的用户',
              actionLabel: '清空搜索',
              onAction: _search.clear,
            )
          else
            GroupedSection(
              header: '已屏蔽用户',
              headerTrailing: q.isEmpty
                  ? '共 ${users.length} 人'
                  : '匹配 ${users.length} 人',
              children: [
                for (final user in users)
                  _row(user, query: q, reduced: reduced),
              ],
            ),
        ],
      );
    },
  );

  Widget _row(
    BlockedUser user, {
    required String query,
    required bool reduced,
  }) {
    final epoch = index.epoch;
    final present = index.isBlocked(user.uid);
    return TweenAnimationBuilder<double>(
      key: ValueKey(user.uid),
      tween: Tween(begin: 1, end: present ? 1 : 0),
      duration: reduced ? AppMotion.reducedFade : AppMotion.revealDuration,
      curve: reduced ? Curves.linear : AppMotion.revealCurve,
      builder: (_, value, child) {
        if (value == 1) return child!;
        final fade = Opacity(opacity: value, child: child);
        return reduced
            ? fade
            : ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: value,
                  child: fade,
                ),
              );
      },
      child: ExcludeSemantics(
        excluding: !present,
        child: ExcludeFocus(
          excluding: !present,
          child: IgnorePointer(
            ignoring: !present,
            child: _BlockedUserRow(
              user: user,
              query: query,
              onOpen: () => _showDetail(user, query, epoch),
              onUnblock: () => _unblock(user, epoch),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockedUserRow extends StatelessWidget {
  final BlockedUser user;
  final String query;
  final VoidCallback onOpen;
  final VoidCallback onUnblock;

  const _BlockedUserRow({
    required this.user,
    required this.query,
    required this.onOpen,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final excerpt = user.src?.excerpt;
    final summary =
        user.note ?? (excerpt?.isNotEmpty == true ? '“$excerpt”' : null);
    final meta = blockedUserMeta(user.uid, user.blockedAt);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: PressHighlight(
              onTap: onOpen,
              borderRadius: BorderRadius.circular(AppRadii.md),
              semanticLabel: [
                '查看 ${user.name} 的黑名单详情',
                ?summary,
                meta,
              ].join('，'),
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      AccountAvatar(
                        name: user.name,
                        url: user.avatarUrl,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              ThreadRow.highlight(user.name, query, t.accent),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.callout.copyWith(
                                color: t.text,
                                fontWeight: FontWeight.w600,
                                height: 1.3,
                              ),
                            ),
                            if (summary != null) ...[
                              const SizedBox(height: 2),
                              Text.rich(
                                ThreadRow.highlight(summary, query, t.accent),
                                maxLines: user.note == null ? 1 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.subhead.copyWith(
                                  fontSize: AppType.sizeFilter,
                                  color: t.text2,
                                ),
                              ),
                            ],
                            const SizedBox(height: 3),
                            Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(text: 'UID '),
                                  ThreadRow.highlight(
                                    user.uid,
                                    query,
                                    t.accent,
                                  ),
                                  TextSpan(
                                    text: meta.substring(
                                      'UID ${user.uid}'.length,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.footnote.copyWith(color: t.text3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          PressScale(
            key: ValueKey('unblock-${user.uid}'),
            semanticLabel: '解除 ${user.name} 的黑名单',
            onTap: onUnblock,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.accentFill,
                    borderRadius: BorderRadius.circular(AppRadii.full),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    child: ExcludeSemantics(
                      child: Text(
                        '解除',
                        style: AppType.footnote.copyWith(
                          color: t.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DetailAction { profile, unblock, source }

class _BlockedUserDetail extends StatefulWidget {
  const _BlockedUserDetail({
    required this.user,
    required this.index,
    required this.query,
    required this.epoch,
  });

  final BlockedUser user;
  final UserBlockIndex index;
  final String query;
  final int epoch;

  @override
  State<_BlockedUserDetail> createState() => _BlockedUserDetailState();
}

class _BlockedUserDetailState extends State<_BlockedUserDetail> {
  final _note = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String? _error;

  bool get _current => widget.index.epoch == widget.epoch;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _edit(String? note) {
    final draft = note ?? '';
    _note.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    setState(() => _editing = true);
  }

  Future<void> _save() async {
    if (_saving || !_current) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = _note.text;
    final ok = await widget.index.updateNote(widget.user.uid, draft);
    if (!mounted || !_current) return;
    final finished = ok && _note.text == draft;
    if (finished) FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = false;
      _editing = !finished;
      _error = ok ? null : widget.index.lastError ?? '备注未保存，请重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final user = widget.index.entryFor(widget.user.uid) ?? widget.user;
    final source = user.src;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final noteCard = _noteCard(t, user.note);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UserBlockSheetGrabber(),
          UserBlockSheetIdentity(
            name: user.name,
            avatarUrl: user.avatarUrl,
            uid: user.uid,
            blockedAt: user.blockedAt,
            avatarSize: 64,
          ),
          const SizedBox(height: 18),
          if (reduced)
            TweenAnimationBuilder<double>(
              key: ValueKey(_editing),
              tween: Tween(begin: 0, end: 1),
              duration: AppMotion.reducedFade,
              builder: (_, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: noteCard,
            )
          else
            AnimatedSize(
              alignment: Alignment.topCenter,
              duration: AppMotion.revealDuration,
              curve: AppMotion.revealCurve,
              child: noteCard,
            ),
          if (source != null) ...[
            const SizedBox(height: 10),
            _sourceCard(t, source),
          ],
          const SizedBox(height: 18),
          if (_editing)
            UserBlockSheetButton(
              label: '完成',
              color: t.onAccent,
              background: t.btnTop,
              onTap: _saving ? null : _save,
            )
          else ...[
            UserBlockSheetButton(
              label: '查看主页',
              color: t.text,
              onTap: () => Navigator.pop(context, _DetailAction.profile),
            ),
            const SizedBox(height: 10),
            UserBlockSheetButton(
              label: '解除黑名单',
              color: t.accent,
              onTap: () => Navigator.pop(context, _DetailAction.unblock),
            ),
          ],
        ],
      ),
    );
  }

  Widget _noteCard(AppTokens t, String? note) {
    final radius = BorderRadius.circular(UserBlockSheetTokens.cardRadius);
    final label = Text(
      '备注',
      style: AppType.footnote.copyWith(
        color: t.text3,
        fontWeight: FontWeight.w600,
      ),
    );
    if (_editing) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: t.fill,
          borderRadius: radius,
          border: Border.all(color: t.accent, width: AppSpace.focusWidth),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              label,
              const SizedBox(height: 3),
              Semantics(
                label: '备注',
                child: UserBlockSheetNoteField(
                  controller: _note,
                  hint: '写点什么',
                  autofocus: true,
                ),
              ),
              if (_error case final error?)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: AppType.footnote.copyWith(color: t.red),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    final editLabel = note == null ? '添加备注' : '编辑备注';
    return DecoratedBox(
      decoration: BoxDecoration(color: t.surface2, borderRadius: radius),
      child: Tooltip(
        message: editLabel,
        excludeFromSemantics: true,
        child: PressHighlight(
          borderRadius: radius,
          onTap: () => _edit(note),
          semanticLabel: editLabel,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(child: label),
                      const SizedBox(height: 3),
                      Text(
                        note ?? editLabel,
                        semanticsLabel: note == null ? '' : null,
                        style: AppType.callout.copyWith(
                          color: note == null ? t.accent : t.text,
                          fontWeight: note == null ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(AppIcons.pen, size: 18, color: t.text3),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sourceCard(AppTokens t, BlockedUserSource source) {
    final radius = BorderRadius.circular(UserBlockSheetTokens.cardRadius);
    final title = '《${source.title}》';
    final floor = switch (source.floor) {
      1 => '主帖',
      > 1 => '#${source.floor}',
      _ => null,
    };
    final label = AppType.footnote.copyWith(color: t.text3);
    return DecoratedBox(
      decoration: BoxDecoration(color: t.surface2, borderRadius: radius),
      child: PressHighlight(
        borderRadius: radius,
        semanticLabel: ['打开来源', title, ?floor].join('，'),
        onTap: _saving
            ? null
            : () => Navigator.pop(context, _DetailAction.source),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: label,
                            ),
                          ),
                          if (floor != null) ...[
                            const SizedBox(width: 2),
                            Text(floor, style: label),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(AppIcons.forward, size: 12, color: t.text3),
                  ],
                ),
              ),
              if (source.excerpt.isNotEmpty) ...[
                const SizedBox(height: 6),
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: t.fill2, width: 2.5),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Text.rich(
                      ThreadRow.highlight(
                        source.excerpt,
                        widget.query,
                        t.accent,
                      ),
                      style: AppType.subhead.copyWith(color: t.text2),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
