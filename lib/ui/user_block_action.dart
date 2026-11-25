/// Shared block/unblock action for profiles and floor menus.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/display_time.dart';
import '../data/follow_index.dart';
import '../data/user_block_index.dart';
import '../design/sheet_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../di.dart';
import '../pages/thread_detail_page.dart';
import '../widgets/account_widgets.dart';
import '../widgets/expressive_controls.dart';
import 'editor_touch.dart';
import 'feedback.dart';
import 'press.dart';
import 'sheet_scaffold.dart';

Future<bool> toggleUserBlock(
  BuildContext context, {
  required String uid,
  required String name,
  String? avatarUrl,
  UserBlockIndex? index,
  BlockedUserSource? src,
  VoidCallback? onOpenSource,
}) async {
  final blocks = index ?? userBlockIndex;
  final own = blocks.uid;
  if (own == null) {
    AppToast.show(
      context,
      chhSession.loggedIn ? '账号信息尚未就绪，请稍后重试' : '登录后可管理黑名单',
    );
    return false;
  }
  final follows = followIndex.uid == own ? followIndex : null;
  if (!blocks.accountReady || follows?.accountReady == false) {
    AppToast.show(context, '账号信息尚未就绪，请稍后重试');
    return false;
  }
  final sessionRevision = chhSession.identityRevision;
  final epoch = blocks.epoch;
  final followEpoch = follows?.epoch;
  bool isCurrent() =>
      sessionRevision == chhSession.identityRevision && epoch == blocks.epoch;

  await blocks.load();
  await follows?.load();
  if (!context.mounted || !isCurrent()) return false;

  final id = UserBlockIndex.normalizeUid(uid);
  if (id == null || id == own) {
    AppToast.show(context, '无法拉黑这个用户');
    return false;
  }

  final previous = blocks.entryFor(id);
  final wasBlocked = previous != null;
  final blockedAt = DateTime.now();
  String? note;
  if (!wasBlocked) {
    final result = await showUserBlockSheet<({String note, bool openSource})>(
      context,
      index: blocks,
      builder: (_) => _BlockConfirmation(
        uid: id,
        name: name,
        avatarUrl: avatarUrl,
        blockedAt: blockedAt,
        src: src,
        followed: follows?.isFollowed(id) ?? false,
      ),
    );
    if (!context.mounted || result == null || !isCurrent()) {
      return false;
    }
    if (result.openSource && src != null) {
      if (onOpenSource != null) {
        onOpenSource();
      } else {
        await openBlockedUserSource(context, src, index: blocks);
      }
      return false;
    }
    if (blocks.isBlocked(id)) return false;
    note = result.note;
  }
  final save = wasBlocked
      ? blocks.unblock(id)
      : blocks.block(
          uid: id,
          name: name,
          avatarUrl: avatarUrl,
          currentUid: own,
          note: note,
          src: src,
        );
  // Start both mutations before either disk write can outlive this account.
  final unfollow =
      !wasBlocked &&
          follows != null &&
          follows.epoch == followEpoch &&
          follows.isFollowed(id)
      ? follows.unfollow(id)
      : null;
  final ok = await save;
  await unfollow;
  if (!context.mounted || !isCurrent()) return ok;
  if (!ok) {
    AppToast.show(context, blocks.lastError ?? '操作未完成，请重试');
    return false;
  }
  _showUndo(context, blocks, wasBlocked ? '已解除黑名单' : '已加入黑名单', () async {
    if (!context.mounted || !isCurrent()) return;
    final restored = wasBlocked
        ? await blocks.block(
            uid: id,
            name: previous.name,
            avatarUrl: previous.avatarUrl,
            blockedAt: previous.blockedAt,
            note: previous.note,
            src: previous.src,
            currentUid: own,
          )
        : await blocks.unblock(id);
    if (context.mounted && isCurrent()) {
      AppToast.show(context, restored ? '已撤销' : (blocks.lastError ?? '撤销未完成'));
    }
  });
  return true;
}

Future<void> openBlockedUserSource(
  BuildContext context,
  BlockedUserSource source, {
  UserBlockIndex? index,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => ThreadDetailPage(
      tid: source.tid,
      title: source.title,
      blockedSource: source,
      blockIndex: index,
    ),
  ),
);

Future<T?> showUserBlockSheet<T>(
  BuildContext context, {
  required UserBlockIndex index,
  required WidgetBuilder builder,
}) async {
  final epoch = index.epoch;
  ModalRoute<dynamic>? route;
  final result = await showAppSheet<T>(
    context,
    fadeWhenReduced: true,
    holdViewInsetsOnExit: true,
    avoidKeyboard: true,
    builder: (context) {
      final sheet = ModalRoute.of(context);
      route = sheet;
      return ListenableBuilder(
        listenable: index,
        builder: (context, _) {
          if (epoch == index.epoch) return builder(context);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (sheet != null && sheet.isActive) {
              sheet.navigator?.removeRoute(sheet);
            }
          });
          return const SizedBox.shrink();
        },
      );
    },
  );
  await route?.completed;
  return result;
}

String blockedUserMeta(String uid, DateTime blockedAt) {
  final date = blockedAt.millisecondsSinceEpoch == 0
      ? '加入时间未记录'
      : '${formatDisplayTime(at: blockedAt, style: DisplayTimeStyle.section)}加入';
  return 'UID $uid · $date';
}

class UserBlockSheetIdentity extends StatelessWidget {
  const UserBlockSheetIdentity({
    super.key,
    required this.name,
    required this.avatarUrl,
    required this.uid,
    required this.blockedAt,
    required this.avatarSize,
  });

  final String name;
  final String? avatarUrl;
  final String uid;
  final DateTime blockedAt;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
      child: Column(
        children: [
          ExcludeSemantics(
            child: AccountAvatar(name: name, url: avatarUrl, size: avatarSize),
          ),
          const SizedBox(height: 10),
          Semantics(
            header: true,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: UserBlockSheetTokens.name.copyWith(color: t.text),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            blockedUserMeta(uid, blockedAt),
            textAlign: TextAlign.center,
            style: AppType.footnote.copyWith(color: t.text2),
          ),
        ],
      ),
    );
  }
}

class UserBlockSheetGrabber extends StatelessWidget {
  const UserBlockSheetGrabber({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    label: '拖动收起',
    child: SizedBox(
      height: 22,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTokens.of(context).fill2,
            borderRadius: BorderRadius.circular(AppRadii.bar),
          ),
          child: const SizedBox(width: 36, height: 5),
        ),
      ),
    ),
  );
}

class UserBlockSheetButton extends StatelessWidget {
  const UserBlockSheetButton({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
    this.background,
  });

  final String label;
  final Color color;
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    semanticLabel: label,
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? AppTokens.of(context).fill,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: Center(
            child: ExcludeSemantics(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: AppType.headline.copyWith(color: color),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class UserBlockSheetNoteField extends StatelessWidget {
  const UserBlockSheetNoteField({
    super.key,
    required this.controller,
    required this.hint,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return EditorTouchGuard(
      notifyOnUserEntry: autofocus,
      builder: (context, focus, onTap) => TextField(
        controller: controller,
        focusNode: focus,
        onTap: onTap,
        onTapAlwaysCalled: true,
        autofocus: autofocus,
        minLines: 1,
        maxLines: 4,
        maxLength: UserBlockIndex.maxNoteLength,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        style: AppType.callout.copyWith(color: t.text, height: 1.5),
        cursorColor: t.accent,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppType.callout.copyWith(color: t.text3, height: 1.5),
          counterText: '',
          isDense: true,
          filled: false,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}

class _BlockConfirmation extends StatefulWidget {
  const _BlockConfirmation({
    required this.uid,
    required this.name,
    required this.avatarUrl,
    required this.blockedAt,
    required this.src,
    required this.followed,
  });

  final String uid;
  final String name;
  final String? avatarUrl;
  final DateTime blockedAt;
  final BlockedUserSource? src;
  final bool followed;

  @override
  State<_BlockConfirmation> createState() => _BlockConfirmationState();
}

class _BlockConfirmationState extends State<_BlockConfirmation> {
  static const _reasons = ['广告', '引战', '人身攻击', '交易纠纷'];
  static final _reasonSeparator = RegExp(r'[，,、；;\n]+');
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _finish({bool openSource = false}) {
    Navigator.pop(context, (note: _note.text.trim(), openSource: openSource));
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final source = widget.src;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const UserBlockSheetGrabber(),
          UserBlockSheetIdentity(
            name: widget.name,
            avatarUrl: widget.avatarUrl,
            uid: widget.uid,
            blockedAt: widget.blockedAt,
            avatarSize: 56,
          ),
          if (source != null)
            PressHighlight(
              semanticLabel: source.floor > 0
                  ? '定位来源，${source.title}，第 ${source.floor} 楼'
                  : '定位来源，${source.title}',
              onTap: () => _finish(openSource: true),
              child: SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        '来自《${source.title}》',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.footnote.copyWith(color: t.text3),
                      ),
                    ),
                    if (source.floor > 0)
                      Text(
                        '#${source.floor}',
                        style: AppType.footnote.copyWith(color: t.text3),
                      ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 16),
          Focus(
            canRequestFocus: false,
            child: Builder(
              builder: (context) {
                final focused = Focus.of(context).hasFocus;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: t.fill,
                    borderRadius: BorderRadius.circular(
                      UserBlockSheetTokens.cardRadius,
                    ),
                    border: focused
                        ? Border.all(color: t.accent, width: 2)
                        : null,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 13,
                    ),
                    child: UserBlockSheetNoteField(
                      controller: _note,
                      hint: '备注（可选）',
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 7),
          ValueListenableBuilder(
            valueListenable: _note,
            builder: (_, value, _) {
              final existing = value.text.trimRight();
              final added = existing
                  .split(_reasonSeparator)
                  .map((part) => part.trim())
                  .toSet();
              return Wrap(
                spacing: 8,
                runSpacing: 2,
                children: [
                  for (final reason in _reasons)
                    _reasonChip(t, reason, existing, added.contains(reason)),
                ],
              );
            },
          ),
          if (widget.followed) ...[
            const SizedBox(height: 9),
            Text(
              '同时取消关注',
              textAlign: TextAlign.center,
              style: AppType.footnote.copyWith(color: t.text3),
            ),
          ],
          const SizedBox(height: 13),
          UserBlockSheetButton(
            label: '加入黑名单',
            color: t.isDark ? Radix.red11Dark : Radix.red11Light,
            onTap: _finish,
          ),
        ],
      ),
    );
  }

  Widget _reasonChip(AppTokens t, String reason, String existing, bool added) {
    final next = existing.trim().isEmpty ? reason : '$existing，$reason';
    return Semantics(
      selected: added,
      child: PressScale(
        semanticLabel: reason,
        onTap: added || next.characters.length > UserBlockIndex.maxNoteLength
            ? null
            : () => _appendReason(reason),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(AppRadii.full),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              child: ExcludeSemantics(
                child: Text(
                  reason,
                  style: AppType.filter.copyWith(color: t.text2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _appendReason(String reason) {
    final existing = _note.text.trimRight();
    if (existing.split(_reasonSeparator).any((part) => part.trim() == reason)) {
      return;
    }
    final next = existing.trim().isEmpty ? reason : '$existing，$reason';
    if (next.characters.length > UserBlockIndex.maxNoteLength) return;
    _note.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }
}

VoidCallback? _closeBlockToast;
void _showUndo(
  BuildContext context,
  UserBlockIndex index,
  String message,
  Future<void> Function() undo,
) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _closeBlockToast?.call();
  final epoch = index.epoch;
  late final OverlayEntry entry;
  late final Timer timer;
  late final VoidCallback close;
  void accountChanged() {
    if (index.epoch != epoch) close();
  }

  close = () {
    _closeBlockToast = null;
    index.removeListener(accountChanged);
    timer.cancel();
    if (entry.mounted) entry.remove();
  };

  entry = OverlayEntry(
    builder: (context) {
      final t = AppTokens.of(context);
      return Positioned(
        top: MediaQuery.paddingOf(context).top + 8,
        left: 16,
        right: 16,
        child: ExpressivePageReveal(
          active: true,
          animateOnMount: true,
          child: Material(
            color: t.text,
            borderRadius: BorderRadius.circular(AppRadii.full),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        message,
                        style: AppType.footnote.copyWith(color: t.bg),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      close();
                      unawaited(undo());
                    },
                    child: Text(
                      '撤销',
                      style: AppType.footnote.copyWith(color: t.bg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  _closeBlockToast = close;
  index.addListener(accountChanged);
  overlay.insert(entry);
  timer = Timer(const Duration(seconds: 4), close);
}
