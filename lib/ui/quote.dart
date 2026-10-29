/// 引用:左侧 3px 细线 + 作者 + 正文,全 app 只此一种(规格 §6.13)
///
/// 长引用默认两行,点按展开或收起,高度变化用 reveal 弹簧。
library;

import 'package:flutter/material.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

class QuoteView extends StatefulWidget {
  final String author;
  final String text;
  final int collapsedLines;
  final bool collapsible;

  const QuoteView({
    super.key,
    required this.author,
    required this.text,
    this.collapsedLines = 2,
    this.collapsible = true,
  });

  @override
  State<QuoteView> createState() => _QuoteViewState();
}

class _QuoteViewState extends State<QuoteView> {
  static final _curve = AppMotion.curveOf(AppMotion.reveal);
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    final body = AppType.subhead.copyWith(color: t.text2);
    final quote = DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: t.fill2, width: 3)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 0, 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 只有超过折叠行数时才出现"展开引用",短引用直接完整显示
            final overflows =
                widget.collapsible &&
                (TextPainter(
                  text: TextSpan(text: widget.text, style: body),
                  textDirection: TextDirection.ltr,
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: widget.collapsedLines,
                )..layout(maxWidth: constraints.maxWidth)).didExceedMaxLines;
            return AnimatedSize(
              duration: reduced ? Duration.zero : _curve.duration,
              curve: _curve,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.author.isNotEmpty)
                    Text(
                      widget.author,
                      style: AppType.footnote.copyWith(
                        color: t.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  Text(
                    widget.text,
                    maxLines: _expanded || !overflows
                        ? null
                        : widget.collapsedLines,
                    overflow: _expanded || !overflows
                        ? null
                        : TextOverflow.ellipsis,
                    style: body,
                  ),
                  if (overflows || _expanded)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        _expanded ? '收起引用' : '展开引用',
                        style: AppType.footnote.copyWith(
                          color: t.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
    if (!widget.collapsible) return quote;
    return Semantics(
      button: true,
      label: _expanded ? '收起引用' : '展开引用',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _expanded = !_expanded),
        child: quote,
      ),
    );
  }
}
