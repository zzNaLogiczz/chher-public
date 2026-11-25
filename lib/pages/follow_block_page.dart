import 'package:flutter/material.dart';

import '../data/follow_index.dart';
import '../data/user_block_index.dart';
import '../design/tokens.dart';
import '../ui/picker.dart';
import '../ui/segmented.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/large_title_scaffold.dart';
import 'blocked_users_page.dart';
import 'following_page.dart';

enum _Section { following, blocked }

class FollowBlockPage extends StatefulWidget {
  const FollowBlockPage({super.key, this.follows, this.blocks});

  final FollowIndex? follows;
  final UserBlockIndex? blocks;

  @override
  State<FollowBlockPage> createState() => _FollowBlockPageState();
}

class _FollowBlockPageState extends State<FollowBlockPage> {
  static const _title = '关注及黑名单';
  _Section _section = _Section.following;
  bool _visitedBlocked = false;

  void _select(_Section section) {
    if (_section == section) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _section = section;
      if (section == _Section.blocked) _visitedBlocked = true;
    });
  }

  @override
  Widget build(BuildContext context) => LargeTitleScaffold(
    title: _title,
    surface: AppSurface.grouped,
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            0,
            AppSpace.screen,
            8,
          ),
          child: AppSegmented<_Section>(
            options: const [
              PickerOption(value: _Section.following, label: '关注'),
              PickerOption(value: _Section.blocked, label: '黑名单'),
            ],
            value: _section,
            onChanged: _select,
            fallbackTitle: _title,
          ),
        ),
        Expanded(
          // Each mounted list keeps its own scroll position.
          child: PrimaryScrollController.none(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _tab(_Section.following, FollowingBody(index: widget.follows)),
                if (_visitedBlocked)
                  _tab(
                    _Section.blocked,
                    BlockedUsersBody(index: widget.blocks),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _tab(_Section section, Widget body) {
    final active = section == _section;
    return Visibility(
      visible: active,
      maintainState: true,
      child: ExpressivePageReveal(
        active: active,
        animateOnMount: section == _Section.blocked,
        child: body,
      ),
    );
  }
}
