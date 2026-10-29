/// 横滑卡:上方图片 16:9,下方白底标题与来源(规格 §6.8)
library;

import 'package:flutter/material.dart';

import '../design/shapes.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'press.dart';

class ShelfCard extends StatelessWidget {
  static const double width = 236;
  static const _textPadding = EdgeInsets.fromLTRB(14, 10, 14, 12);

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

  /// 标题固定占两行的高度:一行标题的卡片不会比两行的矮
  static double _titleHeight(TextScaler scaler) =>
      _lineHeight(AppType.callout, scaler) * 2;

  /// 卡片总高:16:9 图 + 两行标题 + 一行来源,只随系统字号变化,不随标题字数变化
  static double heightFor(TextScaler scaler, {bool withSource = true}) =>
      width * 9 / 16 +
      _textPadding.vertical +
      _titleHeight(scaler) +
      (withSource ? _lineHeight(AppType.footnote, scaler) : 0);

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    return RepaintBoundary(
      child: PressScale(
        onTap: onTap,
        scale: .97,
        semanticLabel: title,
        child: SizedBox(
          width: width,
          height: heightFor(scaler, withSource: source != null),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: t.surface,
              shape: appShape(AppRadii.md),
              shadows: t.shadowE2,
            ),
            child: AppClip(
              radius: AppRadii.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(aspectRatio: 16 / 9, child: image),
                  Padding(
                    padding: _textPadding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: _titleHeight(scaler),
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.callout.copyWith(
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
    );
  }
}
