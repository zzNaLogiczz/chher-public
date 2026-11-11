/// 外壳宿主:持有当前目的地,把对应页面装进 AppShell
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../di.dart';
import '../design/tokens.dart';
import '../core/app_log.dart';
import '../widgets/app_shell.dart';
import '../widgets/expressive_controls.dart';
import '../widgets/launch_splash.dart';
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
    messageNotifications.openRequests.addListener(_openMessages);
    _restoreSession();
  }

  int _handledOpenRequest = 0;
  int _messagesRevision = 0;
  Timer? _pendingMessageOpen;

  void _openMessages() {
    if (!mounted ||
        !_sessionReady ||
        messageNotifications.openRequests.value == _handledOpenRequest) {
      return;
    }
    _pendingMessageOpen?.cancel();
    // Keep a submitting composer alive; retry the navigation after it unlocks.
    var blocked = false;
    Navigator.of(context).popUntil((route) {
      if (route.isFirst) return true;
      if (route.popDisposition == RoutePopDisposition.doNotPop) {
        blocked = true;
        return true;
      }
      return false;
    });
    if (blocked) {
      _pendingMessageOpen = Timer(
        const Duration(milliseconds: 500),
        _openMessages,
      );
      return;
    }
    _handledOpenRequest = messageNotifications.openRequests.value;
    setState(() {
      _messagesRevision++;
      _visited.remove(AppDestination.messages);
      _dest = AppDestination.messages;
    });
  }

  @override
  void dispose() {
    _pendingMessageOpen?.cancel();
    messageNotifications.openRequests.removeListener(_openMessages);
    super.dispose();
  }

  Future<void> _restoreSession() async {
    setState(() => _sessionError = null);
    try {
      await (widget.initialiseSession ?? chhSession.refresh)();
      if (!mounted) return;
      setState(() => _sessionReady = true);
      _openMessages();
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
      // 会话恢复期间显示品牌启动屏;失败仍是纸面错误态
      return _sessionError == null
          ? const LaunchSplash()
          : Scaffold(
              body: StateView.error(_sessionError!, onRetry: _restoreSession),
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
              // 未读数原本挂在顶栏铃铛上,铃铛删除后由底栏"消息"承接;
              // 外观也在监听里:朱砂红上线引导(我的标签红点)消费后立即消失
              AnimatedBuilder(
                animation: Listenable.merge([chhSession, appUpdater, appearance]),
                builder: (context, _) => AppBottomNavigation(
                  current: _dest,
                  onNavigate: _navigate,
                  messagesBadge: chhSession.badges.total,
                  // 有新版本,或朱砂红上线尚未引导时:从"我的"→设置→外观一路用红点引过去
                  meDot:
                      appUpdater.hasUpdate || !appearance.styleDotSeen,
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
    // 四个一级页都是漆面骨架:标题住进漆面,内容在纸面上
    if (destination == AppDestination.feed) {
      return const FeedPage();
    }
    if (destination == AppDestination.forums) {
      return const ForumIndexView();
    }
    if (destination == AppDestination.messages) {
      return MessagesTabPage(key: ValueKey('messages-$_messagesRevision'));
    }
    return const MePage();
  }

  void _navigate(AppDestination d) {
    if (_dest == d) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (d == AppDestination.messages && chhSession.badges.hasAny) {
        _messagesRevision++;
        _visited.remove(d);
      }
      _dest = d;
    });
  }
}
