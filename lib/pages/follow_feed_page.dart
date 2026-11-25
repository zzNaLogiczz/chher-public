import 'dart:async';

import 'package:flutter/material.dart';

import '../core/display_time.dart';
import '../data/follow_index.dart';
import '../data/follow_poller.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart' show followPoller;
import '../ui/plain_rows.dart';
import '../ui/press.dart';
import '../widgets/account_widgets.dart';
import '../widgets/chhers_refresh_indicator.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/state_view.dart';
import 'follow_block_page.dart';
import 'thread_detail_page.dart';

class FollowFeedPage extends StatefulWidget {
  final FollowIndex? index;
  final FollowPoller? poller;
  const FollowFeedPage({super.key, this.index, this.poller});

  @override
  State<FollowFeedPage> createState() => _FollowFeedPageState();
}

class _FollowFeedPageState extends State<FollowFeedPage> {
  final _newOnEntry = <int>{};
  FollowIndex get _index => widget.index ?? followIndex;
  late final int _entryEpoch;
  bool _leaving = false;
  void Function()? _cancelCheck;

  @override
  void initState() {
    super.initState();
    _entryEpoch = _index.epoch;
    unawaited(_onEntry());
  }

  Future<void> _onEntry() async {
    await _index.load();
    if (!mounted || _leaving || _index.epoch != _entryEpoch) return;
    // Keep the markers for this visit while clearing the entry points' counts.
    _newOnEntry.addAll(
      _index.activities
          .where((item) => item.unseen)
          .map((item) => item.thread.tid),
    );
    unawaited(_index.markAllSeen());
    await _checkNow();
  }

  Future<void> _checkNow() async {
    if (_leaving) return;
    final poller =
        widget.poller ?? (identical(_index, followIndex) ? followPoller : null);
    final check = poller?.forceCheck();
    if (check == null) return;
    _cancelCheck = check.cancel;
    await check.done;
  }

  void _leave() {
    _leaving = true;
    _cancelCheck?.call();
    _cancelCheck = null;
  }

  @override
  void dispose() {
    _leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _leave();
    },
    child: _buildFeed(),
  );

  Widget _buildFeed() => LargeTitleScaffold(
    title: '关注',
    body: ChhersRefreshIndicator(
      onRefresh: _checkNow,
      child: ListenableBuilder(
        listenable: _index,
        builder: (context, _) {
          final t = AppTokens.of(context);
          final users = _index.all;
          final byUid = {for (final user in users) user.uid: user};
          final activities = _index.activities;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              bottom: 40 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 14, 8, 0),
                child: PressHighlight(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => FollowBlockPage(follows: _index),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        if (users.isNotEmpty) ...[
                          _FollowingAvatars(users: users.take(4).toList()),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            '关注了 ${users.length} 人',
                            style: AppType.subhead.copyWith(color: t.text2),
                          ),
                        ),
                        Icon(AppIcons.forward, size: 15, color: t.text3),
                      ],
                    ),
                  ),
                ),
              ),
              if (activities.isEmpty)
                StateView.empty(message: '还没有新动态')
              else
                for (final item in activities)
                  _threadRow(item, byUid[item.thread.authorUid]?.avatar),
            ],
          );
        },
      ),
    ),
  );

  Widget _threadRow(FollowActivity item, String? avatar) {
    final thread = item.thread;
    return ReadStateBuilder(
      key: ValueKey(thread.tid),
      tid: thread.tid,
      replies: thread.observedReplies,
      builder: (context, readState) => ThreadRow(
        thread: thread,
        readState: readState,
        avatarUrl: avatar,
        authorFirst: true,
        timeLabel: thread.createdAt == null
            ? null
            : formatDisplayTime(at: item.at, style: DisplayTimeStyle.list),
        followUnseen:
            item.unseen ||
            (_index.epoch == _entryEpoch && _newOnEntry.contains(thread.tid)),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ThreadDetailPage(
              tid: thread.tid,
              title: thread.title,
              fid: thread.forumFid,
              seenReplies: thread.observedReplies,
              observedReplies: thread.observedReplies,
            ),
          ),
        ),
      ),
    );
  }
}

class _FollowingAvatars extends StatelessWidget {
  const _FollowingAvatars({required this.users});

  final List<FollowedUser> users;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 26,
      width: 26 + 18.0 * (users.length - 1),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (i, user) in users.indexed)
            Positioned(
              left: 18.0 * i,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: CircleBorder(
                    side: BorderSide(
                      color: AppTokens.of(context).bg,
                      width: 2,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                  ),
                ),
                child: AccountAvatar(
                  name: user.name,
                  url: user.avatar,
                  size: 26,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
