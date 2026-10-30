/// 搜索框:高 40 的胶囊,前置放大镜,有文字时出现圆形清除钮(规格 §6.7、§7 搜索)
///
/// 没有独立的"搜索"按钮,由键盘的搜索键提交。
library;

import 'package:flutter/material.dart';
import 'editor_touch.dart';

import '../design/icons.dart';
import '../design/tokens.dart';
import '../design/typography.dart';
import '../widgets/expressive_controls.dart' show ExpressiveVisibility;
import 'press.dart';

class SearchCapsule extends StatelessWidget {
  static const surfaceKey = ValueKey('search-capsule');

  final TextEditingController controller;
  final String hint;
  final VoidCallback onClear;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final FocusNode? focusNode;

  /// 检索进行中:清除钮前显示小转圈
  final bool busy;

  const SearchCapsule({
    super.key,
    required this.controller,
    required this.hint,
    required this.onClear,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.focusNode,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    final style = AppType.callout.copyWith(color: t.text);
    final lineHeight =
        (MediaQuery.textScalerOf(context).scale(style.fontSize!) *
                style.height!)
            .ceilToDouble();
    final visualHeight = (lineHeight + 8).clamp(40.0, double.infinity);
    return SizedBox(
      height: visualHeight + 4,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 2,
            bottom: 2,
            left: 0,
            right: 0,
            child: DecoratedBox(
              key: surfaceKey,
              decoration: BoxDecoration(
                color: t.fill,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(AppIcons.search, size: 18, color: t.text3),
              ),
              Expanded(
                child: EditorTouchGuard(
                  focusNode: focusNode,
                  notifyOnUserEntry: autofocus,
                  builder: (context, editorFocus, onEditorTap) => TextField(
                    focusNode: editorFocus,
                    onTapAlwaysCalled: true,
                    onTap: onEditorTap,
                    controller: controller,

                    autofocus: autofocus,
                    textInputAction: TextInputAction.search,
                    onChanged: onChanged,
                    onSubmitted: onSubmitted,
                    maxLines: 1,
                    textAlignVertical: TextAlignVertical.center,
                    cursorColor: t.accent,
                    style: style,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: style.copyWith(color: t.text3),
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: (visualHeight + 4 - lineHeight) / 2,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              // 检索中显示小转圈;清除钮始终可用,进行中的检索也能随时清掉
              if (busy)
                SizedBox.square(
                  dimension: 24,
                  child: Center(
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.text3,
                      ),
                    ),
                  ),
                ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => ExpressiveVisibility(
                  visible: value.text.isNotEmpty,
                  axis: Axis.horizontal,
                  child: Center(child: SearchClearButton(onTap: onClear)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 22dp 圆形清除钮,命中区 44
class SearchClearButton extends StatelessWidget {
  final VoidCallback onTap;
  const SearchClearButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = AppTokens.of(context);
    return Tooltip(
      message: '清除搜索',
      child: PressScale(
        onTap: onTap,
        semanticLabel: '清除搜索',
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(color: t.text3, shape: BoxShape.circle),
              child: SizedBox.square(
                dimension: 22,
                child: Icon(AppIcons.dismiss, size: 14, color: t.bg),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
