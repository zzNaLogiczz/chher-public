/// 品牌启动屏:会话恢复期间的过渡画面。
///
/// 朱砂红=漆面渐变 + 白线 chh 标(1.0.8 启动页);薄雾白=纸面底 +
/// 墨色标,与该风格的首帧(纸面一级页)同源不跳变。原生 windowBackground
/// 固定漆面渐变,薄雾白只在 Dart 首帧之后接管。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../design/system_ui.dart';
import '../design/typography.dart';

class LaunchSplash extends StatelessWidget {
  const LaunchSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final misty = t.style == AppearanceStyle.misty;
    if (misty) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: t.isDark ? AppSystemUi.lightIcons : AppSystemUi.darkIcons,
        child: ColoredBox(
          color: t.bg,
          child: Column(
            children: [
              const Spacer(),
              Text(
                'chh',
                style: TextStyle(
                  fontSize: LacquerMarks.launchMark,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -3,
                  height: 1,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'chher',
                style: TextStyle(
                  fontSize: LacquerMarks.launchWord,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3,
                  color: t.text,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.only(bottom: 58),
                child: Text(
                  '非官方 CHH 客户端',
                  textAlign: TextAlign.center,
                  style: AppType.footnote.copyWith(color: t.text3),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUi.lightIcons,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: t.lacGradient),
        child: Stack(
          children: [
            // 底部径向深红光晕(设计稿 launch.lac 的 radial 叠层)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, 1.12),
                    radius: 1.3,
                    colors: const [LacquerMarks.launchGlow, Colors.transparent],
                    stops: const [0, .62],
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // chh 白标:与漆面水印同形,带落地投影
                  Text(
                    'chh',
                    style: TextStyle(
                      fontSize: LacquerMarks.launchMark,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -3,
                      height: 1,
                      color: t.onLac,
                      shadows: [
                        Shadow(
                          color: LacquerMarks.launchMarkShadow,
                          offset: const Offset(0, 3),
                          blurRadius: 14,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'chher',
                    style: TextStyle(
                      fontSize: LacquerMarks.launchWord,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .3,
                      color: t.onLac,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 58,
              child: Text(
                '非官方 CHH 客户端',
                textAlign: TextAlign.center,
                style: AppType.footnote.copyWith(color: t.onLac2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
