/// 五条命名弹簧与淡入时长(规格 §5.7)。全 app 只能引用这里的动效。
library;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

abstract final class AppMotion {
  /// 按钮、圆钮、方块、卡片的按压与回弹
  static const tap = CupertinoMotion(
    duration: Duration(milliseconds: 250),
    bounce: 0,
    snapToEnd: true,
  );

  /// 分段滑块、底栏、展开箭头、选择器文字替换
  static const select = CupertinoMotion(
    duration: Duration(milliseconds: 340),
    bounce: 0.18,
    snapToEnd: true,
  );

  /// 内容到达、回复展开、显隐、顶栏小标题与渐隐
  static const reveal = CupertinoMotion(
    duration: Duration(milliseconds: 380),
    bounce: 0,
    snapToEnd: true,
  );

  /// 弹层、编辑器、底部面板开合、图片查看器关闭
  static const sheet = CupertinoMotion(
    duration: Duration(milliseconds: 420),
    bounce: 0.14,
    snapToEnd: true,
  );

  /// 提示条、角标、发送成功对勾、发送圆钮出现
  static const pop = CupertinoMotion(
    duration: Duration(milliseconds: 300),
    bounce: 0.30,
    snapToEnd: true,
  );

  /// 封面展开成文章的 hero 弹簧
  static const hero = SpringDescription(mass: 1, stiffness: 350, damping: 38);

  static const fade = Duration(milliseconds: 180);

  /// 发送成功后对勾停留多久再收起(规格 §6.3)
  static const successHold = Duration(milliseconds: 1200);
  static const reducedFade = Duration(milliseconds: 150);

  /// 系统开启「减少动态效果」时,所有弹簧退化为无动效
  static Motion of(BuildContext context, Motion motion) =>
      MediaQuery.disableAnimationsOf(context) ? const Motion.none() : motion;

  /// 把弹簧折算成"时长 + 曲线",给只接受这两样参数的 API(例如弹层路由的开合)。
  /// 曲线就是弹簧本身的位移,所以过冲和收尾与直接用弹簧一致。
  /// 只接受"时长 + 曲线"的旧式动画(AnimatedSize、AnimatedSwitcher 等)取这些值,
  /// 曲线即弹簧本身
  static Curve get tapCurve => curveOf(tap);
  static Duration get tapDuration => curveOf(tap).duration;
  static Curve get revealCurve => curveOf(reveal);
  static Duration get revealDuration => curveOf(reveal).duration;
  static Curve get sheetCurve => curveOf(sheet);
  static Duration get sheetDuration => curveOf(sheet).duration;

  static SpringCurve curveOf(CupertinoMotion motion) =>
      _curves.putIfAbsent(motion, () => SpringCurve(motion.description));

  // 折算要逐毫秒求静止时间,结果按弹簧缓存,避免每次 build 重算
  static final _curves = <CupertinoMotion, SpringCurve>{};
}

class SpringCurve extends Curve {
  final SpringDescription spring;

  /// 弹簧静止(离终点 < 0.1%)所需的秒数,即曲线覆盖的时长
  final double settle;

  SpringCurve(this.spring) : settle = _settleOf(spring);

  Duration get duration =>
      Duration(microseconds: (settle * Duration.microsecondsPerSecond).round());

  static double _settleOf(SpringDescription spring) {
    final sim = SpringSimulation(spring, 0, 1, 0);
    var last = 0.0;
    for (var ms = 1; ms <= 3000; ms++) {
      final t = ms / 1000;
      if ((1 - sim.x(t)).abs() > 0.001) last = t;
    }
    return last + 0.001;
  }

  @override
  double transformInternal(double t) =>
      SpringSimulation(spring, 0, 1, 0).x(t * settle);
}
