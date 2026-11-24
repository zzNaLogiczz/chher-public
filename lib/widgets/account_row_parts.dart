import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../di.dart';
import 'level_badge.dart';

class AddAccountMark extends StatelessWidget {
  const AddAccountMark.switcher({super.key})
    : _size = MeTokens.actionTarget,
      _strokeLength = 18,
      _strokeWidth = 2;

  const AddAccountMark.settings({super.key})
    : _size = EntryIconTokens.size,
      _strokeLength = 14,
      _strokeWidth = 1.8;

  final double _size;
  final double _strokeLength;
  final double _strokeWidth;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: t.accentFill, shape: BoxShape.circle),
      child: CustomPaint(
        size: Size.square(_size),
        painter: _AddAccountPlus(t.accent, _strokeLength, _strokeWidth),
      ),
    );
  }
}

class _AddAccountPlus extends CustomPainter {
  const _AddAccountPlus(this.color, this.length, this.width);

  final Color color;
  final double length;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // The specified length includes both rounded caps.
    final halfSpan = (length - width) / 2;
    final horizontal = Offset(halfSpan, 0);
    final vertical = Offset(0, halfSpan);
    final ink = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center - horizontal, center + horizontal, ink);
    canvas.drawLine(center - vertical, center + vertical, ink);
  }

  @override
  bool shouldRepaint(_AddAccountPlus oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.length != length ||
      oldDelegate.width != width;
}

class CurrentAccountAvatar extends StatelessWidget {
  const CurrentAccountAvatar({
    super.key,
    required this.avatar,
    required this.gapColor,
  });

  final Widget avatar;
  final Color gapColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppTokens.of(context).accent,
      shape: BoxShape.circle,
    ),
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: DecoratedBox(
        decoration: BoxDecoration(color: gapColor, shape: BoxShape.circle),
        child: Padding(padding: const EdgeInsets.all(2), child: avatar),
      ),
    ),
  );
}

/// Shows the existing profile level when its cached UID matches this row.
class AccountLevel extends StatelessWidget {
  const AccountLevel({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final cache = spaceRepo.meCache;
    return ListenableBuilder(
      listenable: cache,
      builder: (_, _) {
        final gid = cache.forUser(uid)?.groupId;
        return gid == null ? const SizedBox.shrink() : LevelBadge(gid: gid);
      },
    );
  }
}
