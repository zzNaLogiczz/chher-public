/// 五条命名弹簧与淡入时长(规格 §5.7)。全 app 只能引用这里的动效。
library;

import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:motor/motor.dart';

abstract final class AppMotion {
  /// 按钮、圆钮、方块、卡片的按压与回弹
  static const tap = CupertinoMotion(
    duration: Duration(milliseconds: 250),
    bounce: 0,
    snapToEnd: true,
  );

  /// 漆面入口按压,沿用共享按压核心与减少动态效果规则。
  static const entryTap = tap;

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

  /// Reading and compose controls settle from their current scroll position.
  static const scrollChrome = CupertinoMotion(
    duration: Duration(milliseconds: 260),
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

  /// 通知定位仅淡出，不闪烁或延长停留。
  static const noticeHighlightDuration = Duration(milliseconds: 1600);

  static double noticeHighlight(double progress, {bool reduced = false}) =>
      1 - progress.clamp(0.0, 1.0);

  static final viewerHeroTakeoffCurve = SpringCurve(hero);
  static final heroDuration = viewerHeroTakeoffCurve.duration;

  static const fade = Duration(milliseconds: 180);
  static const mediaFade = Duration(milliseconds: 150);
  static const mediaFadeCurve = Curves.easeOut;
  static const longPress = Duration(milliseconds: 400);
  static const listPressDelay = Duration(milliseconds: 70);
  static const viewerChromeOut = Duration(milliseconds: 100);
  static const viewerChromeIn = mediaFade;
  static const viewerScrimCurve = Curves.easeOut;
  static const viewerHeroCurve = Curves.fastOutSlowIn;
  static const contentFadeCurve = Curves.easeOut;
  static const skeletonFade = Duration(milliseconds: 120);
  static const skeletonFadeCurve = Curves.linear;
  static const skeletonDelay = Duration(milliseconds: 300);
  static const skeletonCycle = Duration(milliseconds: 1600);
  static const skeletonMinOpacity = .55;
  static const loadingDelay = skeletonDelay;
  static const loadingIn = mediaFade;
  static const loadingOut = skeletonFade;
  static const refreshSettleCurve = Cubic(.2, .8, .2, 1);
  static const loadingCycle = Duration(milliseconds: 2100);
  static const loadingSpin = Duration(milliseconds: 820);
  static const loadingStrokeGap = .012;
  static const loadingWriteEnd = .6;
  static const loadingFadeStart = .8;
  static const loadingFadeEnd = .95;
  static const loadingStrokeCurve = Curves.easeInOut;

  static const riffleStep = Duration(milliseconds: 35);

  /// 发送成功后对勾停留多久再收起(规格 §6.3)
  static const successHold = Duration(milliseconds: 1200);

  /// smooth_sheets requires a positive animateTo duration, including reduced motion.
  static const immediateSheet = Duration(milliseconds: 1);
  static const reducedFade = Duration(milliseconds: 150);

  /// 系统开启「减少动态效果」时,所有弹簧退化为无动效
  static Motion of(BuildContext context, Motion motion) =>
      MediaQuery.disableAnimationsOf(context) ? const Motion.none() : motion;

  /// Hand a released gesture to a named spring. Velocity uses the same units
  /// as the controller per second (divide pointer velocity by travel distance
  /// for a 0–1 controller). Interruptions retain the current spring velocity.
  static TickerFuture settle(
    AnimationController controller, {
    required double target,
    required CupertinoMotion motion,
    double? velocity,
    bool reduced = false,
  }) {
    final releaseVelocity = velocity ?? controller.velocity;
    if (reduced) {
      controller.value = target;
      return TickerFuture.complete();
    }
    final simulation = SpringSimulation(
      motion.description,
      controller.value,
      target,
      releaseVelocity,
      snapToEnd: true,
    );
    return target < controller.value
        ? controller.animateBackWith(simulation)
        : controller.animateWith(simulation);
  }

  /// Long jumps build only the final viewport before revealing the destination.
  /// ScrollPosition owns the activity, so a new drag/scroll cancels it naturally.
  static Future<void> scrollTo(
    ScrollPosition position,
    double target, {
    bool reduced = false,
  }) {
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if (reduced) {
      position.jumpTo(target);
      return Future<void>.value();
    }
    final distance = target - position.pixels;
    final viewport = position.viewportDimension;
    if (viewport > 0 && distance.abs() > viewport * 1.5) {
      position.jumpTo(target - distance.sign * viewport);
    }
    if ((target - position.pixels).abs() < .01) {
      return Future<void>.value();
    }
    return position.animateTo(
      target,
      duration: revealDuration,
      curve: revealCurve,
    );
  }

  static Future<void> revealInScroll(
    BuildContext context, {
    double alignment = 0,
  }) {
    final object = context.findRenderObject();
    final scrollable = Scrollable.maybeOf(context);
    if (object == null || scrollable == null) return Future<void>.value();
    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return Future<void>.value();
    return scrollTo(
      scrollable.position,
      viewport.getOffsetToReveal(object, alignment).offset,
      reduced: MediaQuery.disableAnimationsOf(context),
    );
  }

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
