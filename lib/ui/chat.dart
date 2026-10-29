/// 私信:气泡与发送圆钮(规格 §6.12)
library;

import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'press.dart';

/// 气泡:圆角 20,靠外的下角收成 6;对方 fill 底,自己 accent 底
class ChatBubble extends StatelessWidget {
  final String text;
  final bool mine;
  const ChatBubble({super.key, required this.text, required this.mine});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    const round = Radius.circular(20);
    const tail = Radius.circular(6);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: mine ? t.accent : t.fill,
        borderRadius: BorderRadius.only(
          topLeft: round,
          topRight: round,
          bottomLeft: mine ? round : tail,
          bottomRight: mine ? tail : round,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: SelectableText(
          text,
          style: AppType.body.copyWith(
            height: 1.45,
            color: mine ? t.onAccent : t.text,
          ),
        ),
      ),
    );
  }
}

/// 发送圆钮:有文字时以 pop 弹出,没有文字时缩小隐藏;发送中显示转圈
class ChatSendButton extends StatelessWidget {
  final bool visible;
  final bool sending;
  final VoidCallback? onPressed;
  const ChatSendButton({
    super.key,
    required this.visible,
    required this.sending,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final reduced = MediaQuery.disableAnimationsOf(context);
    return SingleMotionBuilder(
      value: visible || sending ? 1.0 : 0.0,
      motion: AppMotion.pop,
      active: !reduced,
      // 可点与否跟随目标状态,不等弹出动画走完
      builder: (_, v, child) => Transform.scale(
        scale: v.clamp(0.0, 2.0),
        // 命中区按完整尺寸计算,弹出过程中也能点到
        transformHitTests: false,
        child: IgnorePointer(ignoring: !(visible || sending), child: child),
      ),
      child: Tooltip(
        message: '发送私信',
        child: PressScale(
          onTap: sending ? null : onPressed,
          semanticLabel: sending ? '发送中' : '发送私信',
          child: SizedBox.square(
            dimension: 44,
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.accent,
                  shape: BoxShape.circle,
                ),
                child: SizedBox.square(
                  dimension: 38,
                  child: sending
                      ? Padding(
                          padding: const EdgeInsets.all(11),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.onAccent,
                          ),
                        )
                      : Icon(AppIcons.up, size: 20, color: t.onAccent),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
