/// 用户主页叠在帖子上方，关闭后继续原位置阅读。
library;

import 'package:flutter/material.dart';

import '../data/space_repository.dart';
import '../data/user_block_index.dart';
import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../ui/chrome_button.dart';
import '../ui/side_drawer.dart';
import 'user_page.dart';

Future<void> showUserDrawer(
  BuildContext context,
  String uid, {
  SpaceRepository? repository,
  UserBlockIndex? blockIndex,
  BlockedUserSource? blockSource,
  VoidCallback? onOpenBlockSource,
}) => pushSideDrawer(
  context,
  builder: (_) => UserDrawer(
    uid: uid,
    repository: repository,
    blockIndex: blockIndex,
    blockSource: blockSource,
    onOpenBlockSource: onOpenBlockSource,
  ),
  barrierLabel: '关闭',
);

class UserDrawer extends StatefulWidget {
  final String uid;
  final SpaceRepository? repository;
  final UserBlockIndex? blockIndex;
  final BlockedUserSource? blockSource;
  final VoidCallback? onOpenBlockSource;

  const UserDrawer({
    super.key,
    required this.uid,
    this.repository,
    this.blockIndex,
    this.blockSource,
    this.onOpenBlockSource,
  });

  @override
  State<UserDrawer> createState() => _UserDrawerState();
}

class _UserDrawerState extends State<UserDrawer> {
  String _name = '';

  Future<void> _openBlockSource() async {
    final open = widget.onOpenBlockSource;
    final route = ModalRoute.of(context);
    Navigator.of(context).pop();
    await route?.completed;
    open?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Material(
      color: t.grouped,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  ChromeButton(
                    icon: AppIcons.dismiss,
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.headline.copyWith(color: t.text),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: UserProfileBody(
              uid: widget.uid,
              repository: widget.repository,
              blockIndex: widget.blockIndex,
              blockSource: widget.blockSource,
              onOpenBlockSource: widget.onOpenBlockSource == null
                  ? null
                  : _openBlockSource,
              onLoaded: (profile) {
                if (_name != profile.name) {
                  setState(() => _name = profile.name);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
