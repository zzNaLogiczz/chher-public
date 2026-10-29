/// 外壳宿主:持有当前目的地,把对应页面装进 AppShell
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../di.dart';
import '../design/tokens.dart';
import '../core/app_log.dart';
import '../widgets/app_shell.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/state_view.dart';
import '../update/update_controller.dart';
import '../widgets/update_sheet.dart';
import 'feed_page.dart';
import 'forum_index_view.dart';
import 'me_page.dart';
import 'messages_page.dart';

class HomePage extends StatefulWidget {
  final Map<AppDestination, WidgetBuilder>? screenBuilders;
  final Future<void> Function()? initialiseSession;
  const HomePage({super.key, this.screenBuilders, this.initialiseSession});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppDestination _dest = AppDestination.feed;
  final _visited = <AppDestination, Widget>{};
  bool _sessionReady = false;
  Object? _sessionError;

  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    setState(() => _sessionError = null);
    try {
      await (widget.initialiseSession ?? chhSession.refresh)();
      if (!mounted) return;
      setState(() => _sessionReady = true);
      if (widget.initialiseSession == null) {
        unawaited(chhSession.ensureIdentity());
        // 会话就绪、首页已显示后再检查更新,不和首屏请求抢网络
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(runLaunchUpdateCheck(context));
        });
      }
    } catch (error) {
      AppLog.w('SESSION', '会话恢复失败 ${error.runtimeType}');
      if (mounted) setState(() => _sessionError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionReady) {
      return Scaffold(
        body: _sessionError == null
            ? StateView.loading()
            : StateView.error(_sessionError!, onRetry: _restoreSession),
      );
    }
    _visited.putIfAbsent(_dest, () => _screenFor(_dest));
    return PopScope(
      canPop: _dest == AppDestination.feed,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _navigate(AppDestination.feed);
      },
      child: Material(
        color: AppTokens.of(context).bg,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  for (final entry in _visited.entries)
                    Offstage(
                      offstage: entry.key != _dest,
                      child: ExcludeFocus(
                        excluding: entry.key != _dest,
                        child: TickerMode(
                          enabled: entry.key == _dest,
                          child: ExpressivePageReveal(
                            active: entry.key == _dest,
                            animateOnMount: true,
                            fade: false,
                            child: entry.value,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (MediaQuery.viewInsetsOf(context).bottom == 0)
              // 未读数原本挂在顶栏铃铛上,铃铛删除后由底栏"消息"承接
              AnimatedBuilder(
                animation: Listenable.merge([chhSession, appUpdater]),
                builder: (context, _) => AppBottomNavigation(
                  current: _dest,
                  onNavigate: _navigate,
                  messagesBadge: chhSession.badges.total,
                  // 有新版本:从"我的"→设置→关于一路用红点引过去
                  meDot: appUpdater.hasUpdate,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _screenFor(AppDestination destination) {
    final builder = widget.screenBuilders?[destination];
    if (builder != null) return builder(context);
    if (destination == AppDestination.feed) {
      return const FeedPage();
    }
    return AppShell(
      title: destination.label,
      current: destination,
      body: _bodyFor(destination),
    );
  }

  void _navigate(AppDestination d) {
    if (_dest == d) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _dest = d);
  }

  Widget _bodyFor(AppDestination d) {
    return switch (d) {
      AppDestination.feed => const SizedBox.shrink(),
      AppDestination.forums => const ForumIndexView(),
      AppDestination.messages => const MessagesBody(),
      AppDestination.me => const MeBody(),
    };
  }
}
