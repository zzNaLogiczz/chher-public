/// 应用设置按账号、外观和通用分组。
library;

import 'package:flutter/material.dart';
import '../core/accounts.dart';
import '../core/chh_urls.dart';
import '../design/brand.dart';
import '../design/motion.dart';
import '../ui/chrome_button.dart';
import '../ui/grouped.dart';
import '../ui/press.dart';
import '../ui/sheet_scaffold.dart';
import '../design/icons.dart';
import '../design/shapes.dart';
import '../design/theme.dart';
import '../widgets/settings_appearance.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import '../data/image_disk_cache.dart';
import '../network/chh_session.dart';
import '../widgets/account_row_parts.dart';
import '../widgets/account_switcher_sheet.dart';
import '../widgets/account_widgets.dart';
import '../widgets/chhers_loader.dart';
import '../widgets/large_title_scaffold.dart';
import '../ui/feedback.dart';
import '../update/update_controller.dart';
import '../core/app_info.dart';
import '../core/appearance.dart';
import 'about_page.dart';
import 'login_page.dart';
import 'log_page.dart';

enum _AccountAction { switchTo, relogin, remove }

class SettingsPage extends StatelessWidget {
  final AppearanceController? appearanceController;
  const SettingsPage({super.key, this.appearanceController});

  @override
  Widget build(BuildContext context) {
    final ctrl = appearanceController ?? appearance;
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final outerBrightness = Theme.of(context).brightness;
        final targetBrightness = switch (ctrl.mode) {
          AppearanceMode.light => Brightness.light,
          AppearanceMode.dark => Brightness.dark,
          AppearanceMode.system => outerBrightness,
        };
        return Theme(
          data: buildAppTheme(targetBrightness, ctrl.style),
          child: LargeTitleScaffold(
            title: '设置',
            surface: AppSurface.grouped,
            body: SettingsBody(appearanceController: appearanceController),
          ),
        );
      },
    );
  }
}

class SettingsBody extends StatefulWidget {
  final AppearanceController? appearanceController;
  const SettingsBody({super.key, this.appearanceController});
  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  // 缓存大小异步统计,算完前行上显示占位,不阻塞设置页出现
  String _cacheLabel = '计算中';
  final _accountChanges = Listenable.merge([accountStore, chhSession]);
  bool _changingAccount = false;

  String? get _currentUid => chhSession.badges.uid ?? accountStore.currentUid;
  bool get _canChangeAccount =>
      !_changingAccount && !chhSession.accountOperationInProgress;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  @override
  void dispose() {
    // 朱砂上线引导:用户查看过设置页后消费红点(离开页面时底栏、
    // 设置行、风格选项的红点全部消失并持久化,后续安装更新不再出现)。
    // 放在 dispose 而非 initState:让设置页内"朱砂"选项上的红点
    // 至少可见一次,引导才成立。
    (widget.appearanceController ?? appearance).markStyleDotSeen();
    super.dispose();
  }

  Future<void> _refreshCacheSize() async {
    String label;
    try {
      label = _formatBytes(await imageDiskCache.totalBytes());
    } catch (_) {
      // 统计失败时给中性值,不让占位一直挂着
      label = '—';
    }
    if (mounted) setState(() => _cacheLabel = label);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.groupInset,
        0,
        AppSpace.groupInset,
        64,
      ),
      children: [
        ListenableBuilder(
          listenable: _accountChanges,
          builder: (context, _) {
            if (!chhSession.loggedIn && accountStore.accounts.isEmpty) {
              return const SizedBox.shrink();
            }
            final current = _currentUid;
            final isFull = accountStore.isFull;
            final capacity = '最多 ${accountStore.max} 个';
            return _SettingsSection(
              key: const ValueKey('settings-accounts'),
              title: '账号',
              child: Column(
                children: [
                  for (final account in orderedAccounts(accountStore, current))
                    _accountRow(context, account, current == account.uid),
                  _SettingsRow(
                    key: const ValueKey('settings-add-account'),
                    title: '添加账号',
                    leading: const AddAccountMark.settings(),
                    semanticLabel: isFull ? '添加账号，$capacity' : '添加账号',
                    dimmed: isFull,
                    value: isFull
                        ? Text(
                            capacity,
                            textAlign: TextAlign.end,
                            style: SettingsTokens.badgeLabel.copyWith(
                              color: t.text3,
                              fontWeight: FontWeight.w400,
                            ),
                          )
                        : null,
                    onTap: _canChangeAccount && !isFull
                        ? () => Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => const LoginPage.addAccount(),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            );
          },
        ),
        _SettingsSection(
          key: const ValueKey('settings-appearance'),
          title: '外观',
          card: false,
          child: ListenableBuilder(
            listenable: widget.appearanceController ?? appearance,
            builder: (context, _) => SettingsAppearance(
              controller: widget.appearanceController ?? appearance,
            ),
          ),
        ),
        _SettingsSection(
          key: const ValueKey('settings-storage'),
          title: '通用',
          child: Column(
            children: [
              _SettingsRow(
                title: '图片缓存',
                value: Text(
                  _cacheLabel,
                  style: SettingsTokens.valueLabel.copyWith(color: t.text3),
                ),
                leading: const IconTile(icon: AppIcons.imageBold),
                onTap: () => _clearCache(context),
              ),
              _SettingsRow(
                title: '运行日志',
                leading: const IconTile(icon: AppIcons.logBold),
                onTap: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const LogPage())),
              ),
              ListenableBuilder(
                listenable: appUpdater,
                builder: (context, _) => _SettingsRow(
                  key: const ValueKey('settings-about'),
                  title: '关于 $appDisplayName',
                  value: appUpdater.hasUpdate
                      ? DecoratedBox(
                          key: const ValueKey('settings-update-badge'),
                          decoration: BoxDecoration(
                            color: t.accentFill,
                            borderRadius: BorderRadius.circular(AppRadii.full),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            child: Text(
                              '有新版本',
                              style: SettingsTokens.badgeLabel.copyWith(
                                color: t.accent,
                              ),
                            ),
                          ),
                        )
                      : Text(
                          AppInfo.version,
                          style: SettingsTokens.valueLabel.copyWith(
                            color: t.text3,
                          ),
                        ),
                  leading: const IconTile(icon: AppIcons.infoBold),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const AboutPage())),
                ),
              ),
            ],
          ),
        ),
        ListenableBuilder(
          listenable: _accountChanges,
          builder: (context, _) => chhSession.loggedIn
              ? Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: t.surface,
                      shape: appShape(AppRadii.full),
                      shadows: SettingsTokens.cardShadow(t),
                    ),
                    child: AppClip(
                      radius: AppRadii.full,
                      child: PressHighlight(
                        key: const ValueKey('settings-logout'),
                        semanticLabel: '退出登录',
                        onTap: _canChangeAccount
                            ? () => _logout(context)
                            : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: SettingsTokens.logoutHeight,
                          ),
                          child: Center(
                            child: Text(
                              '退出登录',
                              style: SettingsTokens.rowLabel.copyWith(
                                color: t.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _accountRow(
    BuildContext context,
    AccountSummary account,
    bool current,
  ) {
    final t = AppTokens.of(context);
    final expired = _isExpired(account, current);
    final key = ValueKey('settings-account-${account.uid}');
    final label = '管理${account.name}的账号，UID ${account.uid}';
    final onTap = _canChangeAccount
        ? () => _manageAccount(context, account)
        : null;
    if (current) {
      return Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 2),
        child: PressHighlight(
          semanticLabel: '$label，当前账号${expired ? '，登录已失效' : ''}',
          borderRadius: BorderRadius.circular(SettingsTokens.rowRadius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                AccountAvatar(
                  name: account.name,
                  url: ChhUrls.avatar(account.uid),
                  size: 52,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExcludeSemantics(
                        child: Text(
                          account.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.headline.copyWith(color: t.text),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 7,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ExcludeSemantics(
                            child: Text(
                              expired ? '登录已失效' : 'UID ${account.uid}',
                              style: AppType.footnote.copyWith(
                                color: expired ? t.red : t.text2,
                              ),
                            ),
                          ),
                          if (!expired) AccountLevel(uid: account.uid),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Icon(AppIcons.forward, size: 13, color: t.text3),
              ],
            ),
          ),
        ),
      );
    }

    final unread = account.notices + account.messages;
    final waiting = accountStore.switchingUid == account.uid;
    final status = switch ((waiting, expired, account.failures, unread)) {
      (true, _, _, _) => '正在切换',
      (_, true, _, _) => '已失效',
      (_, _, >= 4, _) => '未能检查',
      (_, _, _, > 0) => '$unread 条未读',
      _ => null,
    };
    return _SettingsRow(
      key: key,
      title: account.name,
      singleLine: true,
      semanticLabel: status == null ? label : '$label，$status',
      leading: AccountAvatar(
        name: account.name,
        url: ChhUrls.avatar(account.uid),
        size: EntryIconTokens.size,
      ),
      value: status == null
          ? null
          : AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? AppMotion.reducedFade
                  : AppMotion.fade,
              layoutBuilder: (current, _) => current ?? const SizedBox.shrink(),
              child: waiting
                  ? ChhersSpinner(color: t.accent)
                  : expired || account.failures >= 4
                  ? Text(
                      status,
                      key: ValueKey(status),
                      textAlign: TextAlign.end,
                      style: AppType.footnote.copyWith(
                        color: expired ? t.red : t.text3,
                      ),
                    )
                  : CountBadge(count: unread),
            ),
      onTap: onTap,
    );
  }

  bool _isExpired(AccountSummary account, bool current) =>
      account.state == AccountState.expired ||
      (current && chhSession.currentExpired);

  Future<void> _clearCache(BuildContext context) async {
    final ok = await _confirm(context, title: '清除图片缓存？', action: '清除');
    if (ok != true) return;
    try {
      await imageDiskCache.clear();
    } catch (_) {
      if (context.mounted) AppToast.show(context, '清除失败，请稍后重试');
    } finally {
      // 无论清除是否成功都重新统计,不显示过期的大小
      await _refreshCacheSize();
    }
  }

  Future<void> _logout(BuildContext context) async {
    if (!_canChangeAccount) return;
    final current = _currentUid;
    final next = orderedAccounts(
      accountStore,
      current,
    ).where((account) => account.uid != current).firstOrNull;
    final ok = await _confirm(
      context,
      title: '退出当前账号？',
      action: '退出',
      description: next == null ? null : '将切换到 ${next.name}',
    );
    if (ok == true && context.mounted && _canChangeAccount) {
      await _changeAccount(context, chhSession.logout, '未能退出，请重试');
    }
  }

  Future<void> _manageAccount(
    BuildContext context,
    AccountSummary account,
  ) async {
    if (!_canChangeAccount) return;
    final uid = account.uid;
    final current = _currentUid == uid;
    final expired = _isExpired(account, current);
    final action = await showAppSheet<_AccountAction>(
      context,
      builder: (context) => _SettingsActionSheet(
        heading: _AccountSheetIdentity(
          account: account,
          current: current,
          expired: expired,
        ),
        actionSpacing: 24,
        actions: [
          if (!current || expired)
            _SettingsSheetButton(
              label: expired ? '重新登录' : '切换到此账号',
              style: _SettingsSheetButtonStyle.primary,
              onTap: () => Navigator.pop(
                context,
                expired ? _AccountAction.relogin : _AccountAction.switchTo,
              ),
            ),
          _SettingsSheetButton(
            label: '移除账号',
            style: _SettingsSheetButtonStyle.destructive,
            onTap: () => Navigator.pop(context, _AccountAction.remove),
          ),
        ],
      ),
    );
    if (!context.mounted ||
        !_canChangeAccount ||
        accountStore.find(uid) == null) {
      return;
    }
    switch (action) {
      case _AccountAction.switchTo:
        await _changeAccount(context, () async {
          final result = await chhSession.switchAccount(uid);
          if (!context.mounted) return;
          if (result == AccountSwitchResult.expired) {
            await _relogin(context, account);
          } else if (result == AccountSwitchResult.failed) {
            AppToast.show(context, '未能切换账号，请重试');
          }
        }, '未能切换账号，请重试');
      case _AccountAction.relogin:
        await _relogin(context, account);
      case _AccountAction.remove:
        final ok = await _confirm(
          context,
          title: '移除 ${account.name}？',
          action: '移除',
          description: '移除后需重新登录',
        );
        if (ok != true || !context.mounted || !_canChangeAccount) return;
        await _changeAccount(context, () async {
          if (_currentUid == uid) {
            await chhSession.logout();
          } else if (!await accountStore.remove(uid) && context.mounted) {
            AppToast.show(context, '未能移除账号，请重试');
          }
        }, '未能移除账号，请重试');
      case null:
        break;
    }
  }

  Future<void> _changeAccount(
    BuildContext context,
    Future<void> Function() action,
    String failure,
  ) async {
    setState(() => _changingAccount = true);
    try {
      await action();
    } catch (_) {
      if (context.mounted) AppToast.show(context, failure);
    } finally {
      if (mounted) setState(() => _changingAccount = false);
    }
  }
}

Future<bool?> _relogin(BuildContext context, AccountSummary account) =>
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LoginPage.relogin(account.uid, account.name),
      ),
    );

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

Color _dangerText(AppTokens t) => t.isDark ? Radix.red11Dark : Radix.red11Light;

class _AccountSheetIdentity extends StatelessWidget {
  const _AccountSheetIdentity({
    required this.account,
    required this.current,
    required this.expired,
  });

  final AccountSummary account;
  final bool current;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final danger = _dangerText(t);
    final unread = account.notices + account.messages;
    final status = switch ((expired, current, unread)) {
      (true, _, _) => (
        label: '登录已失效',
        foreground: danger,
        background: danger.withValues(alpha: .1),
      ),
      (_, true, _) => (
        label: '当前账号',
        foreground: t.accent,
        background: t.accentFill,
      ),
      (_, _, > 0) => (
        label: '$unread 条未读',
        foreground: t.text2,
        background: t.fill,
      ),
      _ => null,
    };
    final uid = 'UID ${account.uid}';
    final avatar = AccountAvatar(
      name: account.name,
      url: ChhUrls.avatar(account.uid),
      size: 64,
    );

    return Semantics(
      label: [account.name, uid, ?status?.label].join('，'),
      container: true,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (current)
            CurrentAccountAvatar(avatar: avatar, gapColor: t.surface)
          else
            avatar,
          const SizedBox(height: 12),
          Text(
            account.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: SettingsTokens.confirmationTitle.copyWith(color: t.text),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              Text(uid, style: AppType.footnote.copyWith(color: t.text2)),
              if (!expired) AccountLevel(uid: account.uid),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: status.background,
                borderRadius: BorderRadius.circular(AppRadii.full),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!current && !expired) ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: t.red,
                          shape: BoxShape.circle,
                        ),
                        child: const SizedBox.square(dimension: 6),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        status.label,
                        style: AppType.caption.copyWith(
                          color: status.foreground,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<bool?> _confirm(
  BuildContext context, {
  required String title,
  required String action,
  String? description,
}) => showAppSheet<bool>(
  context,
  builder: (context) {
    final t = AppTokens.of(context);
    return _SettingsActionSheet(
      heading: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: SettingsTokens.confirmationTitle.copyWith(color: t.text),
          ),
          if (description != null) ...[
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: AppType.footnote.copyWith(color: t.text3),
            ),
          ],
        ],
      ),
      actionSpacing: 26,
      actions: [
        _SettingsSheetButton(
          label: action,
          style: _SettingsSheetButtonStyle.confirmation,
          onTap: () => Navigator.pop(context, true),
        ),
        _SettingsSheetButton(
          label: '取消',
          onTap: () => Navigator.pop(context, false),
        ),
      ],
    );
  },
);

class _SettingsActionSheet extends StatelessWidget {
  const _SettingsActionSheet({
    required this.heading,
    required this.actionSpacing,
    required this.actions,
  });

  final Widget heading;
  final double actionSpacing;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.fill,
                borderRadius: BorderRadius.circular(AppRadii.bar),
              ),
              child: const SizedBox(width: 36, height: 5),
            ),
          ),
          const SizedBox(height: 22),
          heading,
          SizedBox(height: actionSpacing),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: actions,
          ),
        ],
      ),
    );
  }
}

enum _SettingsSheetButtonStyle { secondary, confirmation, primary, destructive }

class _SettingsSheetButton extends StatelessWidget {
  const _SettingsSheetButton({
    required this.label,
    required this.onTap,
    this.style = _SettingsSheetButtonStyle.secondary,
  });

  final String label;
  final VoidCallback onTap;
  final _SettingsSheetButtonStyle style;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final primary = style == _SettingsSheetButtonStyle.primary;
    final foreground = switch (style) {
      _SettingsSheetButtonStyle.secondary => t.text,
      _SettingsSheetButtonStyle.confirmation => SettingsTokens.strongForeground(
        t,
      ),
      _SettingsSheetButtonStyle.primary => t.onAccent,
      _SettingsSheetButtonStyle.destructive => _dangerText(t),
    };
    return PressScale(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: primary
              ? null
              : style == _SettingsSheetButtonStyle.confirmation
              ? t.red
              : t.fill,
          gradient: primary ? t.btnGradient : null,
          boxShadow: primary ? t.btnShadow : null,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SettingsTokens.confirmationButtonHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: SettingsTokens.rowLabel.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final Widget child;
  final bool card;
  const _SettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.card = true,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.groupedRowInset,
              0,
              AppSpace.groupedRowInset,
              10,
            ),
            child: Text(
              title,
              style: AppType.footnote.copyWith(
                color: t.text3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!card)
            child
          else
            DecoratedBox(
              decoration: ShapeDecoration(
                color: t.surface,
                shape: appShape(SettingsTokens.cardRadius),
                shadows: SettingsTokens.cardShadow(t),
              ),
              child: Padding(
                padding: const EdgeInsets.all(SettingsTokens.cardInset),
                child: child,
              ),
            ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String title;
  final Widget leading;
  final Widget? value;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final bool singleLine;
  final bool dimmed;
  const _SettingsRow({
    super.key,
    required this.title,
    required this.leading,
    this.value,
    required this.onTap,
    this.semanticLabel,
    this.singleLine = false,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: SettingsTokens.rowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: singleLine ? 1 : null,
                  overflow: singleLine ? TextOverflow.ellipsis : null,
                  style: SettingsTokens.rowLabel.copyWith(color: t.text),
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 6),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * .45,
                  ),
                  child: value!,
                ),
              ],
              if (!dimmed) ...[
                const SizedBox(width: 6),
                Icon(AppIcons.forward, size: 13, color: t.text3),
              ],
            ],
          ),
        ),
      ),
    );
    final visible = dimmed ? Opacity(opacity: .5, child: content) : content;
    return PressHighlight(
      semanticLabel: semanticLabel ?? title,
      borderRadius: BorderRadius.circular(SettingsTokens.rowRadius),
      onTap: onTap,
      child: semanticLabel == null ? visible : ExcludeSemantics(child: visible),
    );
  }
}
