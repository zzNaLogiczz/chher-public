import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design/icons.dart';
import '../design/support_tokens.dart';
import '../design/tokens.dart';
import '../support/support_actions.dart';
import '../support/support_badge_stage.dart';
import '../ui/chrome_button.dart';
import '../ui/feedback.dart';
import '../ui/press.dart';
import '../widgets/chhers_loader.dart';

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  static const _title = '每一份支持，都算数';
  static const _subtitle = '金额随意，谢谢你喜欢 Chhers。';
  static const _both = {SupportCode.alipay, SupportCode.weChat};
  static const _copyGap = 6.0;
  static const _buttonGap = 10.0;
  static const _bottomGap = 14.0;
  static const _copyToButtons = 26.0;
  static const _cardToCopy = 30.0;

  final _stage = GlobalKey<SupportBadgeStageState>();
  var _saving = false;
  var _openingAlipay = false;

  bool get _onPage => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _pay() async {
    if (_openingAlipay || !_onPage) return;
    _openingAlipay = true;
    _stage.currentState?.animateAction(tug: .8);
    try {
      if (await openAlipay() || !mounted || !_onPage) return;
      AppToast.show(
        context,
        '没有找到支付宝',
        actionLabel: '保存收款码',
        onAction: () => unawaited(_save({SupportCode.alipay})),
      );
    } finally {
      _openingAlipay = false;
    }
  }

  Future<void> _save(Set<SupportCode> kinds, {bool tug = true}) async {
    if (_saving || !_onPage) return;
    setState(() => _saving = true);
    _stage.currentState?.animateAction(tug: tug ? .35 : 0, flash: kinds);
    try {
      final results = await saveCodes(kinds);
      if (!mounted || !_onPage) return;
      if (results.values.every((result) => result == SaveCodeResult.saved)) {
        final canOpenWeChat = kinds.contains(SupportCode.weChat);
        AppToast.show(
          context,
          kinds.length == 1 ? '已保存${kinds.single.label}收款码' : '已保存到相册',
          icon: AppIcons.success,
          actionLabel: canOpenWeChat ? '打开微信' : null,
          onAction: canOpenWeChat ? () => unawaited(_scan()) : null,
          actionColor: canOpenWeChat ? SupportCode.weChat.ink : null,
        );
      } else if (results.values.contains(SaveCodeResult.permissionDenied)) {
        AppToast.show(context, '需要存储权限才能保存');
      } else {
        final failed = kinds
            .where((kind) => results[kind] != SaveCodeResult.saved)
            .toSet();
        AppToast.show(
          context,
          '保存失败',
          actionLabel: '保存收款码',
          onAction: () => unawaited(_save(failed)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scan() async {
    if (!mounted || !_onPage) return;
    if (await openWeChat() == WeChatResult.missing && mounted && _onPage) {
      AppToast.show(context, '没有找到微信');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final insets = MediaQuery.paddingOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final title = SupportTokens.title.copyWith(color: tokens.text);
    final subtitle = SupportTokens.subtitle.copyWith(color: tokens.text2);
    final buttonExtra = math.max(
      0.0,
      scaler.scale(SupportTokens.action.fontSize!) -
          SupportTokens.action.fontSize!,
    );
    final payHeight = 52 + buttonExtra;
    final saveHeight = 48 + buttonExtra;
    final buttonsHeight = payHeight + _buttonGap + saveHeight;
    final copy = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: Text(_title, style: title, textAlign: TextAlign.center),
        ),
        const SizedBox(height: _copyGap),
        Text(_subtitle, style: subtitle, textAlign: TextAlign.center),
      ],
    );
    final buttons = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SupportButton(
          label: '用支付宝支持',
          height: payHeight,
          background: SupportCode.alipay.brandColor,
          foreground: Radix.whiteA12,
          onTap: () => unawaited(_pay()),
        ),
        const SizedBox(height: _buttonGap),
        _SupportButton(
          label: '保存两张收款码',
          icon: AppIcons.saveCodesBold,
          height: saveHeight,
          background: tokens.accentFill,
          foreground: tokens.accent,
          onTap: _saving ? null : () => unawaited(_save(_both)),
        ),
      ],
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, bounds) {
          final size = bounds.biggest;
          final textLeft = insets.left + AppSpace.screen;
          final textRight = insets.right + AppSpace.screen;
          final copyWidth = math.max(1.0, size.width - textLeft - textRight);
          final copyHeight =
              _textHeight(context, _title, title, copyWidth) +
              _copyGap +
              _textHeight(context, _subtitle, subtitle, copyWidth);
          final copyTop =
              size.height -
              insets.bottom -
              _bottomGap -
              buttonsHeight -
              _copyToButtons -
              copyHeight;
          final split = size.width > size.height || copyTop - insets.top < 180;
          final divider = (size.width + insets.left - insets.right) * .52;
          final anchorX = split
              ? (insets.left + divider) / 2
              : (insets.left + size.width - insets.right) / 2;
          final restBottom = split
              ? size.height - insets.bottom - 20
              : copyTop - _cardToCopy;
          final naturalWidth = (size.width * .56).clamp(196.0, 236.0);
          const aspect = 212 / 150;
          final cardWidth = math.max(
            32.0,
            math.min(
              naturalWidth,
              math.min(
                (restBottom - insets.top - 60) / aspect,
                anchorX * 2 - 24,
              ),
            ),
          );
          final cardHeight = cardWidth * aspect;
          final rest = Rect.fromLTWH(
            anchorX - cardWidth / 2,
            restBottom - cardHeight,
            cardWidth,
            cardHeight,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  painter: _SupportBackdrop(tokens, rest.center),
                ),
              ),
              SupportBadgeStage(
                key: _stage,
                viewport: size,
                restingCard: rest,
                topWall: insets.top + 4,
                onSave: (kind) => unawaited(_save({kind}, tug: false)),
              ),
              if (split)
                Positioned(
                  top: insets.top + 6,
                  bottom: insets.bottom + _bottomGap,
                  left: divider + 10,
                  right: textRight,
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            copy,
                            const SizedBox(height: _copyToButtons),
                            buttons,
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else ...[
                Positioned(
                  left: textLeft,
                  right: textRight,
                  top: copyTop,
                  child: copy,
                ),
                Positioned(
                  left: textLeft,
                  right: textRight,
                  bottom: insets.bottom + _bottomGap,
                  child: buttons,
                ),
              ],
              Positioned(
                top: insets.top + 6,
                left: insets.left + 14,
                child: ChromeButton(
                  visualSize: 44,
                  icon: AppIcons.back,
                  tooltip: '返回',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  double _textHeight(
    BuildContext context,
    String text,
    TextStyle style,
    double width,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: width);
    final height = painter.height;
    painter.dispose();
    return height;
  }
}

class _SupportButton extends StatelessWidget {
  const _SupportButton({
    required this.label,
    this.icon,
    required this.height,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final double height;
  final Color background;
  final Color foreground;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    onTap: onTap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.full),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon case final icon?) ...[
                Icon(icon, size: 19, color: foreground),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  label,
                  style: SupportTokens.action.copyWith(color: foreground),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SupportBackdrop extends CustomPainter {
  const _SupportBackdrop(this.tokens, this.center);

  final AppTokens tokens;
  final Offset center;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final gradient = RadialGradient(
      center: const Alignment(0, -.4),
      radius: 1,
      colors: [tokens.surface, tokens.bg],
      stops: const [0, .74],
    );
    canvas.drawRect(bounds, Paint()..shader = gradient.createShader(bounds));
    final markWidth = size.width * 1.28;
    canvas.save();
    canvas.clipRect(bounds);
    paintChhersWordmark(
      canvas,
      Rect.fromCenter(
        center: center,
        width: markWidth,
        height: markWidth * .23,
      ),
      tokens.text.withValues(alpha: tokens.isDark ? .045 : .05),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SupportBackdrop oldDelegate) =>
      oldDelegate.tokens != tokens || oldDelegate.center != center;
}
