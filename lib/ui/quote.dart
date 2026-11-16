/// 浅底引用：已读的前四行保持原位，只揭开新增内容。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../design/motion.dart';
import '../design/quote_tokens.dart';
import '../design/tokens.dart';
import 'press.dart';

class QuoteView extends StatefulWidget {
  final String author;
  final String text;
  final int collapsedLines;
  final bool collapsible;
  final VoidCallback? onOpenReference;
  final TextStyle? bodyStyle;

  /// Preserve selectable text and inline actions inside the clipped paragraph.
  final Widget? content;

  /// 门户引用里的图片、链接仍可在展开后使用。
  final Widget? expandedContent;

  const QuoteView({
    super.key,
    required this.author,
    required this.text,
    this.collapsedLines = QuoteTokens.collapsedLines,
    this.collapsible = true,
    this.onOpenReference,
    this.bodyStyle,
    this.content,
    this.expandedContent,
  });

  @override
  State<QuoteView> createState() => _QuoteViewState();
}

class _QuoteViewState extends State<QuoteView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal;
  bool _expanded = false;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(vsync: this);
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _opened = true;
    });
    AppMotion.settle(
      _reveal,
      target: _expanded ? 1 : 0,
      motion: AppMotion.reveal,
      reduced: MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = _expanded ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant QuoteView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.author != widget.author) {
      _expanded = _opened = false;
      _reveal.value = 0;
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final body = (widget.bodyStyle ?? QuoteTokens.body).copyWith(
      color: t.text2,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(QuoteTokens.radius),
      ),
      child: Padding(
        padding: QuoteTokens.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ExcludeSemantics(
                  child: Text(
                    '“',
                    style: QuoteTokens.mark.copyWith(color: t.text3),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.author,
                    style: QuoteTokens.author.copyWith(color: t.text2),
                  ),
                ),
                if (widget.onOpenReference != null)
                  PressHighlight(
                    onTap: widget.onOpenReference,
                    semanticLabel: '定位原楼层',
                    borderRadius: BorderRadius.circular(QuoteTokens.radius),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight: QuoteTokens.actionHeight,
                      ),
                      child: Center(
                        child: Text(
                          '原楼层 ›',
                          style: QuoteTokens.reference.copyWith(color: t.text3),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: QuoteTokens.gap),
            LayoutBuilder(
              builder: (context, constraints) {
                final preview = TextPainter(
                  text: TextSpan(text: widget.text, style: body),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  maxLines: widget.collapsedLines,
                )..layout(maxWidth: constraints.maxWidth);
                final expandable =
                    widget.collapsible &&
                    (preview.didExceedMaxLines ||
                        widget.expandedContent != null);
                final collapsedHeight = preview.height;
                preview.dispose();
                final text = widget.content ?? Text(widget.text, style: body);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (expandable)
                      _QuoteReveal(
                        animation: _reveal,
                        collapsedHeight: collapsedHeight,
                        fadeColor: t.fill,
                        child: _opened && widget.expandedContent != null
                            ? widget.expandedContent!
                            : text,
                      )
                    else
                      text,
                    if (expandable)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PressHighlight(
                          onTap: _toggle,
                          semanticLabel: _expanded ? '收起引用' : '展开引用',
                          borderRadius: BorderRadius.circular(
                            QuoteTokens.radius,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              minHeight: QuoteTokens.actionHeight,
                            ),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: 1,
                              child: Text(
                                _expanded ? '收起' : '展开',
                                style: QuoteTokens.author.copyWith(
                                  color: t.text2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteReveal extends SingleChildRenderObjectWidget {
  final Animation<double> animation;
  final double collapsedHeight;
  final Color fadeColor;

  const _QuoteReveal({
    required this.animation,
    required this.collapsedHeight,
    required this.fadeColor,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderQuoteReveal(animation, collapsedHeight, fadeColor);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderQuoteReveal renderObject,
  ) {
    renderObject
      ..collapsedHeight = collapsedHeight
      ..fadeColor = fadeColor
      ..markNeedsLayout()
      ..markNeedsPaint();
  }
}

class _RenderQuoteReveal extends RenderProxyBox {
  final Animation<double> animation;
  double collapsedHeight;
  Color fadeColor;

  _RenderQuoteReveal(this.animation, this.collapsedHeight, this.fadeColor);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    animation.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    animation.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void performLayout() {
    // Child constraints never change during the spring: reuse its paragraph layout.
    child!.layout(
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
      parentUsesSize: true,
    );
    final firstLines = math.min(collapsedHeight, child!.size.height);
    size = constraints.constrain(
      Size(
        child!.size.width,
        firstLines +
            (child!.size.height - firstLines) * animation.value.clamp(0, 1),
      ),
    );
  }

  @override
  Rect? describeApproximatePaintClip(RenderObject child) => Offset.zero & size;

  @override
  void paint(PaintingContext context, Offset offset) {
    context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      (context, offset) => super.paint(context, offset),
      clipBehavior: Clip.hardEdge,
    );
    if (animation.value >= 1 || child!.size.height <= collapsedHeight) return;
    final rect = Rect.fromLTWH(
      offset.dx,
      offset.dy + size.height - QuoteTokens.fadeHeight,
      size.width,
      QuoteTokens.fadeHeight,
    );
    context.canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            fadeColor.withValues(alpha: 0),
            fadeColor.withValues(alpha: (1 - animation.value).clamp(0, 1)),
          ],
        ).createShader(rect),
    );
  }
}
