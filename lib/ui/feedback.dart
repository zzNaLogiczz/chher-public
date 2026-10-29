/// 反馈与状态:顶部提示条、静态骨架(规格 §6.14)
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';

/// 深色胶囊提示条:从顶部安全区下方弹入,1.6 秒后淡出;新提示替换旧提示。
abstract final class AppToast {
  static const hold = Duration(milliseconds: 1600);
  static OverlayEntry? _current;

  static void show(BuildContext context, String message, {IconData? icon}) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _current?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastView(
        message: message,
        icon: icon,
        onDone: () {
          if (_current == entry) _current = null;
          if (entry.mounted) entry.remove();
        },
      ),
    );
    _current = entry;
    overlay.insert(entry);
  }
}

class _ToastView extends StatefulWidget {
  final String message;
  final IconData? icon;
  final VoidCallback onDone;
  const _ToastView({required this.message, this.icon, required this.onDone});

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with TickerProviderStateMixin {
  late final SingleMotionController _pop;
  late final AnimationController _life;

  @override
  void initState() {
    super.initState();
    _pop = SingleMotionController(
      motion: AppMotion.pop,
      vsync: this,
      initialValue: 0,
    );
    // 停留 + 淡出用同一条动画计时,期间按帧推进,结束即移除
    _life = AnimationController(
      vsync: this,
      duration: AppToast.hold + AppMotion.fade,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _pop.value = 1;
      } else {
        _pop.animateTo(1);
      }
      _life.forward().whenComplete(() {
        if (mounted) widget.onDone();
      });
    });
  }

  @override
  void dispose() {
    _pop.dispose();
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final fadeStart =
        AppToast.hold.inMilliseconds /
        (AppToast.hold + AppMotion.fade).inMilliseconds;
    return Positioned(
      top: top + 8,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge([_pop, _life]),
            builder: (context, child) {
              final p = _pop.value;
              final fade = _life.value <= fadeStart
                  ? 1.0
                  : 1 - (_life.value - fadeStart) / (1 - fadeStart);
              return Opacity(
                opacity: (p.clamp(0.0, 1.0) * fade).clamp(0.0, 1.0),
                child: Transform.translate(
                  offset: Offset(0, -24 * (1 - p)),
                  child: child,
                ),
              );
            },
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF01E1E20),
                borderRadius: BorderRadius.circular(22),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.icon != null) ...[
                        Icon(widget.icon, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          widget.message,
                          maxLines: 3,
                          style: AppType.subhead.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 列表首屏的静态骨架:fill 色圆角条,不做闪光动画(不占帧)
class SkeletonList extends StatelessWidget {
  final int rows;
  const SkeletonList({super.key, this.rows = 6});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    Widget bar(double widthFactor, double height) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SizedBox(height: height),
        ),
      ),
    );
    return Semantics(
      label: '加载中',
      child: ClipRect(
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpace.screen,
            16,
            AppSpace.screen,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < rows; i++) ...[
                bar(.28, 12),
                bar(.9, 16),
                bar(.5, 12),
                const SizedBox(height: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
