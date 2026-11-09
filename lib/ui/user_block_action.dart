/// Shared block/unblock action for profiles and floor menus.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../data/user_block_index.dart';
import '../di.dart';
import '../design/tokens.dart';
import '../widgets/expressive_controls.dart';
import '../design/typography.dart';
import 'feedback.dart';

Future<bool> toggleUserBlock(
  BuildContext context, {
  required String uid,
  required String name,
  String? avatarUrl,
  UserBlockIndex? index,
}) async {
  final blocks = index ?? userBlockIndex;
  final own = chhSession.badges.uid;
  if (chhSession.loggedIn && UserBlockIndex.normalizeUid(own) == null) {
    AppToast.show(context, '账号信息尚未就绪，请稍后重试');
    return false;
  }
  if (UserBlockIndex.normalizeUid(uid) == null ||
      UserBlockIndex.normalizeUid(uid) == UserBlockIndex.normalizeUid(own)) {
    AppToast.show(context, '无法拉黑这个用户');
    return false;
  }
  final previous = blocks.entries
      .where((e) => e.uid == UserBlockIndex.normalizeUid(uid))
      .firstOrNull;
  final wasBlocked = previous != null;
  final ok = wasBlocked
      ? await blocks.unblock(uid)
      : await blocks.block(
          uid: uid,
          name: name,
          avatarUrl: avatarUrl,
          currentUid: own,
        );
  if (!context.mounted) return ok;
  if (!ok) {
    AppToast.show(context, blocks.lastError ?? '操作未完成，请重试');
    return false;
  }
  _showUndo(context, wasBlocked ? '已解除黑名单' : '已加入黑名单', () async {
    final restored = wasBlocked
        ? await blocks.block(
            uid: uid,
            name: previous.name,
            avatarUrl: previous.avatarUrl,
            blockedAt: previous.blockedAt,
            currentUid: own,
          )
        : await blocks.unblock(uid);
    if (context.mounted) {
      AppToast.show(context, restored ? '已撤销' : (blocks.lastError ?? '撤销未完成'));
    }
  });
  return true;
}

OverlayEntry? _blockToast;
Timer? _blockTimer;
void _showUndo(
  BuildContext context,
  String message,
  Future<void> Function() undo,
) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _blockTimer?.cancel();
  _blockToast?.remove();
  late OverlayEntry entry;
  void close() {
    if (_blockToast == entry) _blockToast = null;
    if (entry.mounted) entry.remove();
  }

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
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      message,
                      style: AppType.footnote.copyWith(color: t.bg),
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
  _blockToast = entry;
  overlay.insert(entry);
  _blockTimer = Timer(const Duration(seconds: 4), close);
}
