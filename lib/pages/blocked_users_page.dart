import 'package:flutter/material.dart';
import '../data/user_block_index.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/user_block_action.dart';
import '../ui/grouped.dart';
import '../ui/press.dart';
import '../ui/search_field.dart';
import '../widgets/account_widgets.dart';
import '../widgets/large_title_scaffold.dart';
import '../widgets/state_view.dart';
import 'user_drawer.dart';

class BlockedUsersPage extends StatefulWidget {
  final UserBlockIndex? index;
  const BlockedUsersPage({super.key, this.index});
  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  final _search = TextEditingController();
  UserBlockIndex get index => widget.index ?? userBlockIndex;
  @override
  void initState() {
    super.initState();
    index.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: '黑名单',
    surface: AppSurface.grouped,
    body: ListenableBuilder(
      listenable: Listenable.merge([index, _search]),
      builder: (context, _) {
        final q = _search.text.trim().toLowerCase();
        final users = index.entries
            .where((u) => u.name.toLowerCase().contains(q) || u.uid.contains(q))
            .toList();
        return ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            if (index.entries.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: SearchCapsule(
                  key: const ValueKey('blocked-user-search'),
                  controller: _search,
                  hint: '搜索昵称或 UID',
                  onClear: _search.clear,
                ),
              ),
            if (index.lastError != null)
              StateView(icon: AppIcons.warning, message: index.lastError!)
            else if (index.entries.isEmpty)
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
                  for (final u in users)
                    _BlockedUserRow(
                      user: u,
                      onOpen: () => showUserDrawer(context, u.uid),
                      onUnblock: () => toggleUserBlock(
                        context,
                        uid: u.uid,
                        name: u.name,
                        avatarUrl: u.avatarUrl,
                        index: index,
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    ),
  );
}

class _BlockedUserRow extends StatelessWidget {
  final BlockedUser user;
  final VoidCallback onOpen;
  final VoidCallback onUnblock;
  const _BlockedUserRow({
    required this.user,
    required this.onOpen,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final date = user.blockedAt.toLocal();
    final added = user.blockedAt.millisecondsSinceEpoch == 0
        ? '加入时间未记录'
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} 加入';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: PressHighlight(
              onTap: onOpen,
              semanticLabel: '查看 ${user.name} 的资料',
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    AccountAvatar(url: user.avatarUrl, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
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
                            'UID ${user.uid}  $added',
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
          const SizedBox(width: 10),
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
        ],
      ),
    );
  }
}
