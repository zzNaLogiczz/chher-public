/// 收藏操作共用登录入口、乐观状态与失败恢复。
library;

import 'package:flutter/material.dart';

import '../data/favorite_repository.dart';
import '../di.dart';
import 'feedback.dart';

class FavoriteActionBuilder extends StatefulWidget {
  final FavoriteTarget target;
  final Widget Function(
    BuildContext context,
    bool favorited,
    bool busy,
    VoidCallback toggle,
  )
  builder;
  final FavoriteIndex? index;
  final FavoriteRepository? repository;
  final bool Function()? isLoggedIn;

  const FavoriteActionBuilder({
    super.key,
    required this.target,
    required this.builder,
    this.index,
    this.repository,
    this.isLoggedIn,
  });

  @override
  State<FavoriteActionBuilder> createState() => _FavoriteActionBuilderState();
}

class _FavoriteActionBuilderState extends State<FavoriteActionBuilder> {
  bool? _optimistic;
  bool _busy = false;
  int? _operationEpoch;
  FavoriteIndex get _index => widget.index ?? favoriteIndex;
  bool get _loggedIn => widget.isLoggedIn?.call() ?? chhSession.loggedIn;

  Future<void> _toggle() async {
    if (_busy) return;
    if (!_loggedIn) {
      Navigator.pushNamed(context, '/login');
      return;
    }
    final index = _index;
    final target = widget.target;
    final before = index.contains(target);
    final epoch = index.epoch;
    bool stillCurrent() =>
        _loggedIn &&
        identical(index, _index) &&
        index.epoch == epoch &&
        widget.target.type == target.type &&
        widget.target.targetId == target.targetId;
    setState(() {
      _operationEpoch = epoch;
      _optimistic = !before;
      _busy = true;
    });
    try {
      final repository = widget.repository ?? favoriteRepo;
      final result = await (before
          ? repository.remove(target)
          : repository.add(target));
      if (mounted && stillCurrent()) {
        AppToast.show(context, result.favorited ? '已收藏' : '已取消收藏');
      }
    } catch (_) {
      if (mounted && stillCurrent()) {
        AppToast.show(context, before ? '取消未完成，请重试' : '收藏未完成，请重试');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _optimistic = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([_index, chhSession]),
    builder: (context, _) => widget.builder(
      context,
      _loggedIn &&
          ((_operationEpoch == _index.epoch ? _optimistic : null) ??
              _index.contains(widget.target)),
      _busy,
      _toggle,
    ),
  );
}
