import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/accounts.dart';
import '../core/chh_urls.dart';
import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import '../network/chh_session.dart';
import '../pages/login_page.dart';
import '../ui/chrome_button.dart';
import '../ui/press.dart';
import '../ui/sheet_scaffold.dart';
import 'account_row_parts.dart';
import 'account_widgets.dart';
import 'chhers_loader.dart';

List<AccountSummary> orderedAccounts(AccountStore store, String? currentUid) =>
    [...store.accounts]..sort((a, b) {
      final aCurrent = a.uid == currentUid;
      final bCurrent = b.uid == currentUid;
      if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
      final byRecency = b.lastUsedAt.compareTo(a.lastUsedAt);
      return byRecency == 0 ? a.uid.compareTo(b.uid) : byRecency;
    });

Future<void> showAccountSwitcher(BuildContext context) async {
  ModalRoute<bool>? sheet;
  final manage = await showAppSheet<bool>(
    context,
    builder: (context) {
      sheet = ModalRoute.of<bool>(context);
      return const _AccountSwitcher();
    },
  );
  if (manage != true) return;
  await sheet?.completed;
  if (context.mounted) await Navigator.of(context).pushNamed('/settings');
}

class _AccountSwitcher extends StatefulWidget {
  const _AccountSwitcher();

  @override
  State<_AccountSwitcher> createState() => _AccountSwitcherState();
}

class _AccountSwitcherState extends State<_AccountSwitcher> {
  final _expired = <String, int>{};
  final _failed = <String>{};
  final _changes = Listenable.merge([accountStore, chhSession]);
  String? _pendingUid;
  bool _openingLogin = false;

  String? get _currentUid => chhSession.badges.uid ?? accountStore.currentUid;
  bool get _blocked =>
      _pendingUid != null ||
      _openingLogin ||
      chhSession.accountOperationInProgress;

  @override
  void initState() {
    super.initState();
    unawaited(_checkStaleAccounts());
  }

  Future<void> _checkStaleAccounts() async {
    final now = chhClient.now().millisecondsSinceEpoch;
    final limit = const Duration(minutes: 15).inMilliseconds;
    final currentUid = _currentUid;
    final uids = [
      for (final account in accountStore.accounts)
        if (account.uid != currentUid && now - account.checkedAt > limit)
          account.uid,
    ];
    if (uids.isEmpty) return;
    try {
      // The sheet has already applied its own freshness limit.
      await accountStore.check(uids: uids, force: true);
    } on PlatformException {
      // The saved account list remains available.
    }
  }

  Future<void> _openLogin(LoginPage page, {String? uid}) async {
    if (_blocked) return;
    setState(() => _openingLogin = true);
    final loggedIn = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    setState(() {
      _openingLogin = false;
      if (loggedIn == true) _expired.remove(uid);
    });
  }

  Future<void> _switch(AccountSummary account) async {
    if (_blocked) return;
    setState(() {
      _pendingUid = account.uid;
      _failed.remove(account.uid);
    });
    final result = await chhSession.switchAccount(account.uid);
    if (!mounted) return;
    if (result == AccountSwitchResult.success &&
        ModalRoute.isCurrentOf(context) == true) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _pendingUid = null;
      if (result == AccountSwitchResult.expired) {
        _expired[account.uid] =
            accountStore.find(account.uid)?.checkedAt ?? account.checkedAt;
      }
      if (result == AccountSwitchResult.failed) _failed.add(account.uid);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _changes,
    builder: (context, _) {
      final currentUid = _currentUid;
      return SheetScaffold(
        title: '切换账号',
        showClose: false,
        trailingMinWidth: MeTokens.actionTarget,
        trailing: const Align(
          alignment: Alignment.centerRight,
          child: _ManageAccounts(),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, AppSpace.groupInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final account in orderedAccounts(accountStore, currentUid))
                _row(account, currentUid),
              AddAccountRow(
                max: accountStore.max,
                full: accountStore.isFull,
                onPressed: _blocked || accountStore.isFull
                    ? null
                    : () => _openLogin(const LoginPage.addAccount()),
              ),
            ],
          ),
        ),
      );
    },
  );

  Widget _row(AccountSummary account, String? currentUid) {
    final current = account.uid == currentUid;
    final expired =
        _expired[account.uid] == account.checkedAt ||
        account.state == AccountState.expired;
    return AccountListRow(
      key: ValueKey(account.uid),
      account: account,
      current: current,
      expired: expired,
      waiting: (_pendingUid ?? accountStore.switchingUid) == account.uid,
      switchFailed: _failed.contains(account.uid),
      onPressed: current || _blocked
          ? null
          : expired
          ? () => _openLogin(
              LoginPage.relogin(account.uid, account.name),
              uid: account.uid,
            )
          : () => _switch(account),
    );
  }
}

class _ManageAccounts extends StatelessWidget {
  const _ManageAccounts();

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return PressScale(
      semanticLabel: '管理',
      onTap: () => Navigator.of(context).pop(true),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: MeTokens.actionTarget,
          minHeight: MeTokens.actionTarget,
        ),
        child: Align(
          widthFactor: 1,
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.textButtonInset,
            ),
            child: Text(
              '管理',
              style: AppType.subhead.copyWith(
                color: t.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _rowPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
const _rowRadius = BorderRadius.all(Radius.circular(AppRadii.lg));

enum _RowStatus {
  current,
  waiting,
  expired,
  switchFailed,
  checkFailed,
  unread,
  none,
}

class AccountListRow extends StatelessWidget {
  const AccountListRow({
    super.key,
    required this.account,
    required this.current,
    this.onPressed,
    this.expired = false,
    this.waiting = false,
    this.switchFailed = false,
  });

  final AccountSummary account;
  final bool current;
  final VoidCallback? onPressed;
  final bool expired;
  final bool waiting;
  final bool switchFailed;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final isExpired = expired || account.state == AccountState.expired;
    final unread = account.notices + account.messages;
    const retryLabel = '未能切换，点按重试';
    final status = switch ((current, waiting, isExpired, switchFailed)) {
      (true, _, _, _) => _RowStatus.current,
      (_, true, _, _) => _RowStatus.waiting,
      (_, _, true, _) => _RowStatus.expired,
      (_, _, _, true) => _RowStatus.switchFailed,
      _ when account.failures >= 4 => _RowStatus.checkFailed,
      _ when unread > 0 => _RowStatus.unread,
      _ => _RowStatus.none,
    };
    final stateLabel = switch (status) {
      _RowStatus.current => '当前账号',
      _RowStatus.waiting => '正在切换',
      _RowStatus.expired => '登录已失效，重新登录',
      _RowStatus.switchFailed => retryLabel,
      _RowStatus.checkFailed => '未能检查',
      _RowStatus.unread => '$unread 条未读',
      _RowStatus.none => null,
    };
    final name = account.name;
    final action = current || status == _RowStatus.expired ? name : '切换到 $name';
    final label = [
      if (status == _RowStatus.expired) '$action $stateLabel' else action,
      if (current || !isExpired) 'UID ${account.uid}',
      if (status != _RowStatus.expired) ?stateLabel,
    ].join('，');

    final avatar = AccountAvatar(
      name: name,
      url: ChhUrls.avatar(account.uid),
      size: current ? 48 : 44,
    );
    final trailing = switch (status) {
      _RowStatus.current => DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(AppRadii.full),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text('当前', style: AppType.caption.copyWith(color: t.accent)),
        ),
      ),
      _RowStatus.waiting => ChhersSpinner(color: t.accent),
      _RowStatus.expired => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text('重新登录', style: AppType.footnote.copyWith(color: t.red)),
          ),
          const SizedBox(width: 2),
          Icon(AppIcons.forward, size: 11, color: t.red),
        ],
      ),
      _RowStatus.switchFailed => Text(
        retryLabel,
        textAlign: TextAlign.end,
        style: AppType.footnote.copyWith(color: t.red),
      ),
      _RowStatus.checkFailed => Text(
        '未能检查',
        style: AppType.footnote.copyWith(color: t.text3),
      ),
      _RowStatus.unread => CountBadge(count: unread),
      _RowStatus.none => const SizedBox.shrink(),
    };

    final content = ExcludeSemantics(
      child: Padding(
        padding: _rowPadding,
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              if (current)
                CurrentAccountAvatar(
                  key: const ValueKey('account-current-ring'),
                  avatar: avatar,
                  gapColor: t.surface2,
                )
              else
                avatar,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: current
                          ? AppType.headline.copyWith(color: t.text)
                          : AppType.callout.copyWith(
                              color: t.text,
                              fontWeight: FontWeight.w500,
                            ),
                    ),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          !current && isExpired
                              ? '登录已失效'
                              : 'UID ${account.uid}',
                          style: SettingsTokens.badgeLabel.copyWith(
                            color: !current && isExpired ? t.red : t.text2,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        if (current) AccountLevel(uid: account.uid),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .4,
                ),
                child: AnimatedSwitcher(
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? AppMotion.reducedFade
                      : AppMotion.fade,
                  layoutBuilder: (current, _) =>
                      current ?? const SizedBox.shrink(),
                  child: KeyedSubtree(key: ValueKey(status), child: trailing),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (current) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: DecoratedBox(
          key: const ValueKey('account-current-highlight'),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: _rowRadius,
          ),
          child: Semantics(label: label, selected: true, child: content),
        ),
      );
    }
    return PressHighlight(
      onTap: onPressed,
      borderRadius: _rowRadius,
      semanticLabel: label,
      child: content,
    );
  }
}

class AddAccountRow extends StatelessWidget {
  const AddAccountRow({
    super.key,
    required this.max,
    required this.full,
    this.onPressed,
  });

  final int max;
  final bool full;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Opacity(
      opacity: full ? .5 : 1,
      child: PressHighlight(
        onTap: full ? null : onPressed,
        borderRadius: _rowRadius,
        semanticLabel: full ? '添加账号，最多 $max 个' : '添加账号',
        child: ExcludeSemantics(
          child: Padding(
            padding: _rowPadding,
            child: Row(
              children: [
                const AddAccountMark.switcher(),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    '添加账号',
                    style: AppType.callout.copyWith(
                      color: t.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (full)
                  Text(
                    '最多 $max 个',
                    style: SettingsTokens.badgeLabel.copyWith(color: t.text3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
