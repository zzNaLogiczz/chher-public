import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

/// Shared reading boundary; no separators or persistent animation when idle.
class ReadingListEnd extends StatelessWidget {
  final bool loading;
  const ReadingListEnd({super.key, this.loading = false});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: t.text3),
          ),
          const SizedBox(width: 8),
        ] else ...[
          Text('—', style: AppType.footnote.copyWith(color: t.fill2)),
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            loading ? '正在加载' : '已读到这里',
            style: AppType.footnote.copyWith(color: t.text3),
          ),
        ),
        if (!loading) ...[
          const SizedBox(width: 10),
          Text('—', style: AppType.footnote.copyWith(color: t.fill2)),
        ],
      ],
    );
  }
}
