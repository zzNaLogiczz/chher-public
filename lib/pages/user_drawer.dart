/// 用户主页叠在帖子上方，关闭后继续原位置阅读。
library;

import 'package:flutter/material.dart';

import '../data/space_repository.dart';
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
}) => pushSideDrawer(
  context,
  builder: (_) => UserDrawer(uid: uid, repository: repository),
  barrierLabel: '关闭',
);

class UserDrawer extends StatefulWidget {
  final String uid;
  final SpaceRepository? repository;

  const UserDrawer({super.key, required this.uid, this.repository});

  @override
  State<UserDrawer> createState() => _UserDrawerState();
}

class _UserDrawerState extends State<UserDrawer> {
  String _name = '';

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
