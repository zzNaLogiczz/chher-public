/// 2–4 个等宽选项的分段控件:胶囊轨道 + 白色滑块,滑块用弹簧滑过去(规格 §6.4)
///
/// 任一标签在当前字号下放不下时,自动换成"当前值 ⌄"选择按钮,选中状态不丢。
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

import '../design/motion.dart';
import '../design/message_tokens.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'chrome_button.dart';
import 'picker.dart';
import 'press.dart';

class AppSegmented<T> extends StatefulWidget {
  static const thumbKey = ValueKey('segmented-thumb');

  final List<PickerOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// 紧凑型:高 32,宽度按文字,放在分区标题右侧
  final bool compact;

  /// 压在漆面顶栏上:奶白轨道、奶白滑块、选中字深红
  final bool onLac;

  /// 降级为选择面板时的面板标题
  final String? fallbackTitle;

  /// A pager supplies the exact finger/spring position to both selectors.
  final ValueListenable<double>? position;
  final bool messageStyle;
  final List<int>? badgeCounts;

  const AppSegmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.onLac = false,
    this.fallbackTitle,
    this.position,
    this.messageStyle = false,
    this.badgeCounts,
  }) : assert(options.length >= 2 && options.length <= 4);

  @override
  State<AppSegmented<T>> createState() => _AppSegmentedState<T>();
}

class _AppSegmentedState<T> extends State<AppSegmented<T>>
    with SingleTickerProviderStateMixin {
  double get _inset => !widget.messageStyle
      ? 2
      : widget.compact
      ? MessageTokens.compactInset
      : MessageTokens.segmentInset;
  double get _radius => !widget.messageStyle
      ? AppRadii.full
      : widget.compact
      ? MessageTokens.compactRadius
      : MessageTokens.segmentRadius;
  double get _thumbRadius => !widget.messageStyle
      ? AppRadii.full
      : widget.compact
      ? MessageTokens.compactThumbRadius
      : MessageTokens.thumbRadius;

  // 在 initState 创建:降级为选择按钮时 build 不会访问它,
  // 若留到 dispose 才惰性创建会在已失效的元素上查找 TickerMode
  late final SingleMotionController _position;

  // 文字宽度只在标签、字号变化时重新测量
  Object? _measuredFor;
  List<double> _labelWidths = const [];

  @override
  void initState() {
    super.initState();
    _position = SingleMotionController(
      motion: AppMotion.select,
      vsync: this,
      initialValue: _indexOf(widget.value).toDouble(),
    );
  }

  int _indexOf(T value) {
    final i = widget.options.indexWhere((o) => o.value == value);
    return i < 0 ? 0 : i;
  }

  void _moveTo(int index) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _position.value = index.toDouble();
    } else {
      _position.animateTo(index.toDouble());
    }
  }

  @override
  void didUpdateWidget(covariant AppSegmented<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position == null && oldWidget.value != widget.value) {
      _moveTo(_indexOf(widget.value));
    }
  }

  void _select(int index) {
    final option = widget.options[index];
    if (option.value == widget.value) return;
    HapticFeedback.selectionClick();
    // 滑块跟随父级确认后的 value 移动(didUpdateWidget);父级异步切换时不会先跑偏
    widget.onChanged(option.value);
  }

  List<double> _measure(TextStyle style, TextScaler scaler) {
    final key = (
      [for (final o in widget.options) o.label].join('\u0000'),
      scaler,
      style,
      widget.badgeCounts?.join(','),
    );
    if (key != _measuredFor) {
      _measuredFor = key;
      _labelWidths = [
        for (final o in widget.options)
          (TextPainter(
                text: TextSpan(text: o.label, style: style),
                textDirection: TextDirection.ltr,
                textScaler: scaler,
                maxLines: 1,
              )..layout()).width +
              (widget.messageStyle && widget.badgeCounts != null
                  ? widget.compact
                        ? MessageTokens.unreadDot + MessageTokens.badgeGap
                        : 30 + MessageTokens.badgeGap
                  : 0),
      ];
    }
    return _labelWidths;
  }

  @override
  void dispose() {
    _position.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final style =
        (widget.messageStyle && !widget.compact
                ? AppType.subhead
                : AppType.footnote)
            .copyWith(fontWeight: FontWeight.w600);
    final widths = _measure(style, scaler);
    final widest = widths.reduce((a, b) => a > b ? a : b);
    final textHeight = scaler.scale(style.fontSize!) * style.height!;
    final height = (textHeight + 12).clamp(
      widget.messageStyle
          ? widget.compact
                ? MessageTokens.compactHeight
                : MessageTokens.segmentHeight
          : widget.compact
          ? 32.0
          : 36.0,
      double.infinity,
    );
    final count = widget.options.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final segment = widget.compact
            ? widget.messageStyle
                  ? ((MessageTokens.compactWidth - _inset * 2) / count).clamp(
                      widest + 16,
                      double.infinity,
                    )
                  : widest + 24
            : (constraints.maxWidth - _inset * 2) / count;
        final total = segment * count + _inset * 2;
        final fits =
            total <= constraints.maxWidth + 0.5 && widest + 16 <= segment;
        if (!fits) {
          return PickerButton<T>(
            sheetTitle: widget.fallbackTitle ?? widget.options.first.label,
            options: widget.options,
            value: widget.value,
            onChanged: widget.onChanged,
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            color: widget.messageStyle
                ? MessageTokens.track(t, widget.onLac)
                : MessageTokens.standardTrack(t, widget.onLac),
            borderRadius: BorderRadius.circular(_radius),
          ),
          child: SizedBox(
            width: total,
            height: height,
            child: AnimatedBuilder(
              animation: widget.position ?? _position,
              builder: (context, _) {
                final position = widget.position?.value ?? _position.value;
                return Stack(
                  children: [
                    Positioned(
                      left: _inset,
                      top: _inset,
                      bottom: _inset,
                      width: segment,
                      child: Transform.translate(
                        offset: Offset(position * segment, 0),
                        child: DecoratedBox(
                          key: AppSegmented.thumbKey,
                          decoration: BoxDecoration(
                            color: widget.messageStyle
                                ? MessageTokens.thumb(t, widget.onLac)
                                : MessageTokens.standardThumb(t, widget.onLac),
                            borderRadius: BorderRadius.circular(_thumbRadius),
                            boxShadow: widget.messageStyle
                                ? MessageTokens.thumbShadow(t)
                                : MessageTokens.standardShadow(t, widget.onLac),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: _inset),
                      child: Row(
                        children: [
                          for (var i = 0; i < count; i++)
                            SizedBox(
                              width: segment,
                              height: height,
                              child: _segment(t, i, position, style),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _badge(AppTokens t, int i, double emphasis) {
    final count = i < widget.badgeCounts!.length ? widget.badgeCounts![i] : 0;
    final foreground = widget.onLac ? MessageTokens.thumb(t, true) : t.onAccent;
    final background = widget.onLac
        ? MessageTokens.selected(t, true)
        : t.accent;
    final color = widget.onLac
        ? Color.lerp(foreground, background, emphasis)!
        : background;
    if (widget.compact) {
      return BadgeAppearance(
        visible: count > 0,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox.square(dimension: MessageTokens.unreadDot),
        ),
      );
    }
    return CountBadge(
      count: count,
      color: color,
      textColor: widget.onLac
          ? Color.lerp(background, foreground, emphasis)
          : foreground,
    );
  }

  Widget _segment(AppTokens t, int i, double position, TextStyle style) {
    // 文字颜色随滑块距离渐变,滑块经过时就亮起,不等动画结束
    final emphasis = (1 - (position - i).abs()).clamp(0.0, 1.0);
    // 漆面上:滑块后的字是深红,未到的字是淡朱
    final selectedColor = widget.messageStyle
        ? MessageTokens.selected(t, widget.onLac)
        : MessageTokens.standardSelected(t, widget.onLac);
    final restingColor = widget.onLac ? t.onLac2 : t.text2;
    // 合并成一个节点:读屏器在同一个按钮上读到名称和"已选中"
    return MergeSemantics(
      key: ValueKey('segment-$i'),
      child: Semantics(
        selected: i == _indexOf(widget.value),
        child: PressScale(
          onTap: () => _select(i),
          semanticLabel: widget.options[i].label,
          child: Center(
            child: widget.messageStyle
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.options[i].label,
                        maxLines: 1,
                        style: style.copyWith(
                          color: Color.lerp(
                            restingColor,
                            selectedColor,
                            emphasis,
                          ),
                        ),
                      ),
                      if (widget.badgeCounts != null) ...[
                        const SizedBox(width: MessageTokens.badgeGap),
                        _badge(t, i, emphasis),
                      ],
                    ],
                  )
                : Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Text(
                        widget.options[i].label,
                        maxLines: 1,
                        style: style.copyWith(
                          color: Color.lerp(
                            restingColor,
                            selectedColor,
                            emphasis,
                          ),
                        ),
                      ),
                      // 新功能引导红点(例如朱砂红上线):悬在文字右上角
                      Positioned(
                        top: -5,
                        right: -10,
                        child: DotBadge(visible: widget.options[i].dot),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
