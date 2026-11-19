import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../design/typography.dart';
import 'chhers_loader.dart';
import 'chhers_loading_transition.dart';

/// Shared reading boundary; no separators or persistent animation when idle.
class ReadingListEnd extends StatelessWidget {
  final bool loading;
  final bool exhausted;
  final double topPadding;
  const ReadingListEnd({
    super.key,
    this.loading = false,
    this.exhausted = true,
    this.topPadding = 0,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final style = AppType.footnote.copyWith(color: t.text3);
    Widget marker(Widget child) => Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: child,
    );
    return ChhersLoadingTransition(
      size: ChhersLoaderSize.list,
      placeholderBuilder: (indicator) =>
          marker(Center(heightFactor: 1, child: indicator)),
      child: loading
          ? null
          : exhausted
          ? marker(
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('—', style: style.copyWith(color: t.fill2)),
                  const SizedBox(width: 10),
                  Flexible(child: Text('已读到这里', style: style)),
                  const SizedBox(width: 10),
                  Text('—', style: style.copyWith(color: t.fill2)),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
