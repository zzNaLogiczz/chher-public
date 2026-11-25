/// 外壳宿主:持有当前目的地,把对应页面装进 AppShell
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/accounts.dart';
import '../core/app_log.dart';
import '../core/message_notifications.dart';
import '../data/follow_index.dart';
import '../di.dart';
import '../design/tokens.dart';
import '../network/chh_session.dart';
import '../ui/feedback.dart';
import '../widgets/account_switcher_sheet.dart';
import '../widgets/app_shell.dart';
import '../widgets/lacquer_tab_scaffold.dart';
import '../widgets/launch_splash.dart';
import '../widgets/state_view.dart';
import '../update/update_controller.dart';
import '../widgets/update_sheet.dart';
import 'feed_page.dart';
import 'forum_index_view.dart';
import 'login_page.dart';
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
  final _feedReselect = ValueNotifier<int>(0);
  bool _sessionReady = false;
  Object? _sessionError;

  @override
  void initState() {
    super.initState();
    messageNotifications.openRequests.addListener(_receiveNotification);
    _restoreSession();
  }

  int _messagesRevision = 0;
  Timer? _pendingMessageOpen;
  bool _routingNotification = false;

  void _receiveNotification() {
    final request = messageNotifications.openRequests.value;
    if (!mounted || !_sessionReady || request == null) return;
    messageNotifications.openRequests.value = null;
    _pendingMessageOpen?.cancel();
    unawaited(_openNotification(request));
  }

  Future<void> _openNotification(NotificationOpenRequest request) async {
    if (!mounted ||
        _routingNotification ||
        chhSession.accountOperationInProgress) {
      return;
    }
    _routingNotification = true;
    try {
      final uid = request.uid;
      final currentUid = chhSession.badges.uid ?? accountStore.currentUid;
      final relogin = request.action == NotificationAction.relogin;
      AccountSummary? target;
      if (relogin || (uid != null && uid != currentUid)) {
        if (uid == null) return;
        await accountStore.reload();
        if (!mounted || chhSession.accountOperationInProgress) return;
        target = accountStore.find(uid);
        if (target == null) {
          if (relogin ||
              currentUid != null ||
              accountStore.accounts.isNotEmpty ||
              !chhSession.loggedIn) {
            return;
          }
          // A notification from the single-account session can precede migration.
          await chhSession.ensureIdentity();
          if (!mounted ||
              chhSession.accountOperationInProgress ||
              chhSession.badges.uid != uid) {
            return;
          }
        }
      }
      if (relogin) {
        await _openRelogin(target!);
        return;
      }
      if (!_prepareMessageRoute(request)) return;
      if (target != null) {
        final result = await chhSession.switchAccount(target.uid);
        if (!mounted) return;
        switch (result) {
          case AccountSwitchResult.expired:
            await _openRelogin(target);
            return;
          case AccountSwitchResult.failed:
            if (accountStore.find(target.uid) != null) {
              AppToast.show(context, '暂时无法切换账号');
            }
            return;
          case AccountSwitchResult.success:
            if (!_prepareMessageRoute(request)) return;
        }
      }
      setState(() {
        _messagesRevision++;
        _visited.remove(AppDestination.messages);
        _dest = AppDestination.messages;
      });
    } finally {
      _routingNotification = false;
    }
  }

  Future<void> _openRelogin(AccountSummary account) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LoginPage.relogin(account.uid, account.name),
      ),
    );
  }

  bool _prepareMessageRoute(NotificationOpenRequest request) {
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
        () => unawaited(_openNotification(request)),
      );
    }
    return !blocked;
  }

  @override
  void dispose() {
    _pendingMessageOpen?.cancel();
    _feedReselect.dispose();
    messageNotifications.openRequests.removeListener(_receiveNotification);
    super.dispose();
  }

  Future<void> _restoreSession() async {
    setState(() => _sessionError = null);
    try {
      await (widget.initialiseSession ?? chhSession.refresh)();
      if (!mounted) return;
      setState(() => _sessionReady = true);
      _receiveNotification();
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
    final showNavigation = MediaQuery.viewInsetsOf(context).bottom == 0;
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
              // Navigation lays out next to the tab viewport and owns the safe area.
              child: MediaQuery.removePadding(
                context: context,
                removeBottom: showNavigation,
                child: Stack(
                  children: [
                    for (final entry in _visited.entries)
                      Offstage(
                        offstage: entry.key != _dest,
                        child: ExcludeFocus(
                          excluding: entry.key != _dest,
                          child: TickerMode(
                            enabled: entry.key == _dest,
                            // 一级目的地保留原位置与绘制缓存；选择反馈由底栏承接，
                            // 不重播整页入场，以免连同状态栏背景一起移开。
                            child: RepaintBoundary(
                              child: entry.key == AppDestination.feed
                                  ? TabReselectScope(
                                      requests: _feedReselect,
                                      child: entry.value,
                                    )
                                  : entry.value,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (showNavigation)
              // 未读数原本挂在顶栏铃铛上,铃铛删除后由底栏"消息"承接;
              // 外观也在监听里:朱砂红上线引导(我的标签红点)消费后立即消失
              AnimatedBuilder(
                animation: Listenable.merge([
                  chhSession,
                  appUpdater,
                  appearance,
                  followIndex,
                ]),
                builder: (context, _) => AppBottomNavigation(
                  current: _dest,
                  onNavigate: _navigate,
                  onMeLongPress: chhSession.loggedIn
                      ? () {
                          if (chhSession.accountOperationInProgress) return;
                          unawaited(HapticFeedback.selectionClick());
                          unawaited(showAccountSwitcher(context));
                        }
                      : null,
                  messagesBadge: chhSession.badges.total,
                  messagesDot: followIndex.unseenCount > 0,
                  messagesDotEpoch: followIndex.epoch,
                  // 有新版本,或朱砂红上线尚未引导时:从"我的"→设置→外观一路用红点引过去
                  meDot: appUpdater.hasUpdate || !appearance.styleDotSeen,
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
    if (_dest == d) {
      if (d == AppDestination.feed) _feedReselect.value++;
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      if (d == AppDestination.messages &&
          chhSession.badges.notices > 0 &&
          chhSession.badges.messages == 0) {
        _messagesRevision++;
        _visited.remove(d);
      }
      _dest = d;
    });
  }
}
