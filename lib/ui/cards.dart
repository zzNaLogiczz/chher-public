/// 社区精选瓷片：3:2 图片与单行标题。
library;

import 'package:flutter/material.dart';

import '../design/display_text.dart';
import '../design/shapes.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'press.dart';

class ShelfCard extends StatelessWidget {
  static const double width = HomeTokens.shelfWidth;
  static const _textPadding = EdgeInsets.fromLTRB(10, 11, 10, 9);

  final Widget image;
  final String title;
  final String? source;
  final VoidCallback? onTap;

  const ShelfCard({
    super.key,
    required this.image,
    required this.title,
    this.source,
    this.onTap,
  });

  static double _lineHeight(TextStyle style, TextScaler scaler) =>
      scaler.scale(style.fontSize!) * style.height!;

  /// 固定一行，完整标题保留在语义标签中。
  static double _titleHeight(TextScaler scaler) =>
      scaler.scale(HomeTokens.shelfTitleSize) * 1.4;

  /// 卡片高度跟随系统字号，长标题不挤压图片。
  static double heightFor(TextScaler scaler, {bool withSource = false}) =>
      (width - HomeTokens.shelfPadding * 2) / HomeTokens.shelfImageRatio +
      HomeTokens.shelfPadding * 2 +
      _textPadding.vertical +
      _titleHeight(scaler) +
      (withSource ? _lineHeight(AppType.footnote, scaler) : 0);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final displayTitle = normalizeDisplayText(title);
    return RepaintBoundary(
      child: PressScale(
        onTap: onTap,
        scale: .97,
        semanticLabel: displayTitle,
        child: SizedBox(
          width: width,
          height: heightFor(scaler, withSource: source != null),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: t.surface,
              shape: appShape(HomeTokens.shelfRadius),
              shadows: HomeTokens.cardShadow(t),
            ),
            child: AppClip(
              radius: HomeTokens.shelfRadius,
              child: Padding(
                padding: const EdgeInsets.all(HomeTokens.shelfPadding),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppClip(
                      radius: HomeTokens.shelfImageRadius,
                      child: AspectRatio(
                        aspectRatio: HomeTokens.shelfImageRatio,
                        child: image,
                      ),
                    ),
                    Padding(
                      padding: _textPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            height: _titleHeight(scaler),
                            child: Text(
                              displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.callout.copyWith(
                                fontSize: HomeTokens.shelfTitleSize,
                                height: 1.4,
                                color: t.text,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (source != null)
                            Text(
                              source!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.footnote.copyWith(color: t.text3),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
