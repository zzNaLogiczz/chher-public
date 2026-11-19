/// 会话恢复期间的品牌启动屏。薄雾白在 Dart 首帧后接管原生渐变底。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/brand.dart';
import '../design/system_ui.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

class LaunchSplash extends StatelessWidget {
  const LaunchSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final misty = t.style == AppearanceStyle.misty;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: misty && !t.isDark
          ? AppSystemUi.darkIcons
          : AppSystemUi.lightIcons,
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: misty
              ? BoxDecoration(color: t.bg)
              : BoxDecoration(gradient: t.lacGradient),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (!misty)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: LacquerMarks.launchGlowCenter,
                      radius: LacquerMarks.launchGlowRadius,
                      colors: [LacquerMarks.launchGlow, Colors.transparent],
                      stops: LacquerMarks.launchGlowStops,
                    ),
                  ),
                ),
              Center(
                child: Semantics(
                  image: true,
                  label: appDisplayName,
                  child: CustomPaint(
                    size: LacquerMarks.launchMarkSize,
                    painter: _LaunchMarkPainter(
                      color: misty ? t.text : t.onLac,
                      shadow: !misty,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: LacquerMarks.launchCaptionBottom,
                child: Text(
                  '非官方 CHH 客户端',
                  textAlign: TextAlign.center,
                  style: AppType.footnote.copyWith(
                    color: misty ? t.text3 : t.onLac2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LaunchMarkPainter extends CustomPainter {
  const _LaunchMarkPainter({required this.color, required this.shadow});

  final Color color;
  final bool shadow;

  // Pre-scale once so the shadow offset and blur stay in logical pixels.
  static final _scale = LacquerMarks.launchMarkScale;
  static final _path = buildChhersMarkPath().transform(
    (Matrix4.identity()
          ..scaleByDouble(_scale, _scale, 1, 1)
          ..translateByDouble(
            -LacquerMarks.launchMarkInkBounds.left,
            -LacquerMarks.launchMarkInkBounds.top,
            0,
            1,
          ))
        .storage,
  );
  static final _shadow = _path.shift(LacquerMarks.launchMarkShadowOffset);
  static final _shadowFilter = MaskFilter.blur(
    BlurStyle.normal,
    Shadow.convertRadiusToSigma(LacquerMarks.launchMarkShadowBlur),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = LacquerMarks.launchMarkStroke * _scale;
    if (shadow) {
      canvas.drawPath(
        _shadow,
        paint
          ..color = LacquerMarks.launchMarkShadow
          ..maskFilter = _shadowFilter,
      );
    }
    canvas.drawPath(
      _path,
      paint
        ..color = color
        ..maskFilter = null,
    );
  }

  @override
  bool shouldRepaint(_LaunchMarkPainter oldDelegate) =>
      color != oldDelegate.color || shadow != oldDelegate.shadow;
}
