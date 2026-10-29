/// 选项多时的选择:"当前值 ⌄"按钮 + 底部两列方块面板(规格 §6.5)
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

import '../design/icons.dart';
import '../design/motion.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import 'press.dart';
import 'sheet_scaffold.dart';

class PickerOption<T> {
  final T value;
  final String label;

  /// 一行真实信息,例如数量
  final String? detail;

  /// 独占一整行(例如"全部分区"),其余选项两列均分
  final bool wide;

  const PickerOption({
    required this.value,
    required this.label,
    this.detail,
    this.wide = false,
  });
}

/// 打开选择面板;返回所选值,直接关闭则返回 null。
///
/// 选项值本身可以是 null(如"全部类型"),所以结果包一层,与关闭区分开。
Future<({T value})?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<PickerOption<T>> options,
  required T value,
}) => showAppSheet<({T value})>(
  context,
  builder: (_) => _PickerSheet<T>(title: title, options: options, value: value),
);

class _PickerSheet<T> extends StatefulWidget {
  final String title;
  final List<PickerOption<T>> options;
  final T value;
  const _PickerSheet({
    required this.title,
    required this.options,
    required this.value,
  });

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  /// 选中后先让新状态被看见,再收起面板
  static const _closeDelay = Duration(milliseconds: 200);

  late T _selected = widget.value;
  Timer? _closing;

  void _choose(PickerOption<T> option) {
    // 面板关闭前的再次点击一律忽略
    if (_closing != null) return;
    if (option.value != _selected) HapticFeedback.selectionClick();
    setState(() => _selected = option.value);
    _closing = Timer(_closeDelay, () {
      if (mounted) Navigator.of(context).pop((value: option.value));
    });
  }

  @override
  void dispose() {
    _closing?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return SheetScaffold(
      title: widget.title,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (n, row) in _rows().indexed) ...[
              if (n > 0) const SizedBox(height: _gap),
              // 同一行的方块等高:一侧多一行说明时另一侧不会缩短
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (k, i) in row.indexed) ...[
                      if (k > 0) const SizedBox(width: _gap),
                      Expanded(child: _tile(t, i, widget.options[i])),
                    ],
                    // 末行只剩一个时留出另一半,保持两列宽度一致
                    if (row.length == 1 && !widget.options[row.first].wide) ...[
                      const SizedBox(width: _gap),
                      const Expanded(child: SizedBox.shrink()),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _gap = 10.0;

  /// 按行分组的选项下标:独占行单独成行,其余两两一行
  List<List<int>> _rows() {
    final rows = <List<int>>[];
    List<int>? open;
    for (var i = 0; i < widget.options.length; i++) {
      if (widget.options[i].wide) {
        rows.add([i]);
        open = null;
      } else if (open == null || open.length == 2) {
        rows.add(open = [i]);
      } else {
        open.add(i);
      }
    }
    return rows;
  }

  Widget _tile(AppTokens t, int index, PickerOption<T> option) {
    final selected = option.value == _selected;
    return MergeSemantics(
      key: ValueKey('picker-option-$index'),
      child: Semantics(
        selected: selected,
        child: PressScale(
          onTap: () => _choose(option),
          semanticLabel: option.label,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: selected ? t.accentFill : t.fill,
              borderRadius: BorderRadius.circular(16),
              border: selected ? Border.all(color: t.accent, width: 1.5) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: AppType.subhead.copyWith(
                      fontWeight: FontWeight.w600,
                      color: selected ? t.accent : t.text,
                    ),
                  ),
                  if (option.detail != null)
                    Text(
                      option.detail!,
                      style: AppType.footnote.copyWith(color: t.text3),
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

/// "当前值 ⌄"按钮:点开面板,箭头转 180°,选中后文字滑动替换为新值。
class PickerButton<T> extends StatefulWidget {
  final String sheetTitle;
  final List<PickerOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;

  /// 当前值不在选项里时显示的文字;不给则退回第一项
  final String? placeholder;

  const PickerButton({
    super.key,
    required this.sheetTitle,
    required this.options,
    required this.value,
    required this.onChanged,
    this.placeholder,
  });

  @override
  State<PickerButton<T>> createState() => _PickerButtonState<T>();
}

class _PickerButtonState<T> extends State<PickerButton<T>>
    with TickerProviderStateMixin {
  late final _turn = SingleMotionController(
    motion: AppMotion.select,
    vsync: this,
    initialValue: 0,
  );
  late final _swap = SingleMotionController(
    motion: AppMotion.select,
    vsync: this,
    initialValue: 1,
  );
  String? _previous;
  bool _open = false;

  String _labelOf(T value) =>
      widget.options.where((o) => o.value == value).firstOrNull?.label ??
      widget.placeholder ??
      widget.options.first.label;

  void _animate(SingleMotionController controller, double to) {
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.value = to;
    } else {
      controller.animateTo(to);
    }
  }

  @override
  void didUpdateWidget(covariant PickerButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _labelOf(oldWidget.value);
    if (oldWidget.value != widget.value && previous != _labelOf(widget.value)) {
      // 旧值上移淡出,新值从下方滑入;文字没变时不播放
      _previous = previous;
      _swap.value = 0;
      _animate(_swap, 1);
    }
  }

  Future<void> _openSheet() async {
    if (_open) return;
    _open = true;
    _animate(_turn, 1);
    final picked = await showPickerSheet<T>(
      context,
      title: widget.sheetTitle,
      options: widget.options,
      value: widget.value,
    );
    _open = false;
    if (!mounted) return;
    _animate(_turn, 0);
    if (picked != null && picked.value != widget.value) {
      widget.onChanged(picked.value);
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    _swap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final style = AppType.subhead.copyWith(
      fontWeight: FontWeight.w600,
      color: t.accent,
    );
    final current = _labelOf(widget.value);
    return PressScale(
      onTap: _openSheet,
      semanticLabel: '${widget.sheetTitle} $current',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRect(
              child: AnimatedBuilder(
                animation: _swap,
                builder: (context, _) {
                  final v = _swap.value.clamp(0.0, 1.0);
                  final shift = (style.fontSize ?? 15) * 1.2;
                  return Stack(
                    children: [
                      if (_previous != null && v < 1)
                        Positioned.fill(
                          child: Transform.translate(
                            offset: Offset(0, -shift * v),
                            child: Opacity(
                              opacity: 1 - v,
                              child: Text(
                                _previous!,
                                maxLines: 1,
                                style: style,
                              ),
                            ),
                          ),
                        ),
                      Transform.translate(
                        offset: Offset(0, shift * (1 - v)),
                        child: Opacity(
                          opacity: v,
                          child: Text(current, maxLines: 1, style: style),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: 3),
            AnimatedBuilder(
              animation: _turn,
              builder: (_, child) =>
                  Transform.rotate(angle: math.pi * _turn.value, child: child),
              child: Icon(AppIcons.down, size: 15, color: t.accent),
            ),
          ],
        ),
      ),
    );
  }
}
