import 'dart:async';

import 'package:flutter/material.dart';

import '../core/display_time.dart';
import '../data/follow_index.dart';
import '../data/user_block_index.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/grouped.dart';
import '../ui/press.dart';
import '../ui/search_field.dart';
import '../ui/user_follow_action.dart';
import '../widgets/account_widgets.dart';
import '../widgets/state_view.dart';
import 'user_drawer.dart';

class FollowingBody extends StatefulWidget {
  final FollowIndex? index;
  const FollowingBody({super.key, this.index});

  @override
  State<FollowingBody> createState() => _FollowingBodyState();
}

class _FollowingBodyState extends State<FollowingBody> {
  final _search = TextEditingController();
  final _toggled =
      <String, ({FollowedUser user, DateTime? lastPost, DateTime orderAt})>{};
  FollowIndex get _index => widget.index ?? followIndex;
  late int _epoch;

  @override
  void initState() {
    super.initState();
    _epoch = _index.epoch;
    _index.addListener(_accountChanged);
    unawaited(_index.load());
  }

  void _accountChanged() {
    if (_epoch == _index.epoch) return;
    _epoch = _index.epoch;
    _toggled.clear();
    _search.clear();
  }

  @override
  void dispose() {
    _index.removeListener(_accountChanged);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_index, _search, userBlockIndex]),
    builder: (context, _) {
      final epoch = _index.epoch;
      final latest = <String, DateTime>{};
      for (final item in _index.activities) {
        final uid = item.thread.authorUid;
        final at = item.thread.createdAt;
        if (uid != null && at != null) latest.putIfAbsent(uid, () => at);
      }
      final current = _index.all;
      final users =
          {
            for (final entry in _toggled.entries)
              if (!userBlockIndex.isBlocked(entry.key))
                entry.key: entry.value.user,
            for (final user in current) user.uid: user,
          }.values.toList()..sort((a, b) {
            final first = _toggled[a.uid]?.orderAt ?? a.at;
            final second = _toggled[b.uid]?.orderAt ?? b.at;
            return second.compareTo(first);
          });
      final q = _search.text.trim().toLowerCase();
      final matching = users
          .where((u) => u.name.toLowerCase().contains(q) || u.uid.contains(q))
          .toList();
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.only(
          bottom: 40 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.screen,
              4,
              AppSpace.screen,
              4,
            ),
            child: SearchCapsule(
              controller: _search,
              hint: '搜索昵称或 UID',
              onClear: _search.clear,
            ),
          ),
          if (users.isEmpty)
            StateView.empty(message: '还没有关注任何人')
          else if (matching.isEmpty)
            StateView(
              icon: AppIcons.search,
              message: '没有找到匹配的用户',
              actionLabel: '清空搜索',
              onAction: _search.clear,
            )
          else
            GroupedSection(
              header: q.isEmpty
                  ? '共 ${current.length} 人'
                  : '匹配 ${matching.length} 人',
              children: [
                for (final user in matching)
                  _FollowingRow(
                    key: ValueKey(user.uid),
                    user: user,
                    lastPost: latest[user.uid] ?? _toggled[user.uid]?.lastPost,
                    followed: _index.isFollowed(user.uid),
                    onToggle: () async {
                      if (epoch != _index.epoch) return;
                      if (_index.isFollowed(user.uid)) {
                        final previous = _toggled[user.uid];
                        _toggled[user.uid] = (
                          user: user,
                          lastPost: latest[user.uid] ?? previous?.lastPost,
                          orderAt: previous?.orderAt ?? user.at,
                        );
                      }
                      await toggleUserFollow(
                        context,
                        uid: user.uid,
                        name: user.name,
                        avatarUrl: user.avatar,
                        index: _index,
                      );
                    },
                  ),
              ],
            ),
        ],
      );
    },
  );
}

class _FollowingRow extends StatelessWidget {
  const _FollowingRow({
    super.key,
    required this.user,
    required this.lastPost,
    required this.followed,
    required this.onToggle,
  });

  final FollowedUser user;
  final DateTime? lastPost;
  final bool followed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? AppMotion.reducedFade
        : AppMotion.fade;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: PressHighlight(
              onTap: () => showUserDrawer(context, user.uid),
              semanticLabel: '查看 ${user.name} 的资料',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    AccountAvatar(name: user.name, url: user.avatar, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.callout.copyWith(
                              color: t.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            lastPost == null
                                ? 'UID ${user.uid}'
                                : '最近发帖 ${formatDisplayTime(at: lastPost, style: DisplayTimeStyle.list)}',
                            maxLines: 1,
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
          const SizedBox(width: 12),
          Semantics(
            selected: followed,
            child: PressScale(
              semanticLabel: followed ? '取消关注 ${user.name}' : '关注 ${user.name}',
              onTap: onToggle,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(
                  child: AnimatedContainer(
                    duration: duration,
                    curve: AppMotion.contentFadeCurve,
                    constraints: const BoxConstraints(minHeight: 32),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: followed ? t.fill : t.accentFill,
                      borderRadius: BorderRadius.circular(AppRadii.full),
                    ),
                    child: AnimatedSwitcher(
                      duration: duration,
                      child: Text(
                        followed ? '关注中' : '未关注',
                        key: ValueKey(followed),
                        style: AppType.footnote.copyWith(
                          color: followed ? t.text2 : t.accent,
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
