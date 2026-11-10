/// 品牌启动屏:漆面渐变 + 白线 chh 标 + 字标(朱漆红 v2 启动页,94.7% 红)
///
/// 会话恢复期间的过渡画面;原生 windowBackground 已是同系渐变,
/// 这里补上品牌元素,首帧(精选页漆面)与启动底色同源不跳变。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/tokens.dart';
import '../design/typography.dart';

class LaunchSplash extends StatelessWidget {
  const LaunchSplash({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
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
